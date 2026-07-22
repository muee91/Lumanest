from pathlib import Path


source = Path('.github/workflows/apply-region-query-localization.yml').read_text()
marker = "          python - <<'PY'\n"
body = source.split(marker, 1)[1].split("\n          PY", 1)[0]
body = '\n'.join(
    line[10:] if line.startswith('          ') else line
    for line in body.splitlines()
)

worker_start = body.index(
    "worker = Path('services/lumanest-discovery-service/app/worker.py')"
)
worker_end = body.index(
    "\n\ntest_worker = Path('services/lumanest-discovery-service/tests/test_worker.py')"
)
replacement = r"""worker = Path('services/lumanest-discovery-service/app/worker.py')
text = worker.read_text()
old = "    async def search(self, job: RefreshJob) -> list[BrokerSearchResult]:\n"
new = '''    async def resolve_region(self, job: RefreshJob) -> tuple[str, ...]:
        payload = {
            "query": "__region_identity__",
            "addressHint": None,
            "region": {
                "latitude": job.region.latitude,
                "longitude": job.region.longitude,
                "radiusMeters": job.region.radius_meters,
            },
            "locale": job.region.locale,
        }
        try:
            raw = await self._post("/internal/v1/discovery/resolve-place", payload)
        except BrokerFailure:
            return ()
        region = raw.get("region") if isinstance(raw, dict) and raw.get("status") == "resolved" else None
        values = region.get("searchNames") if isinstance(region, dict) else None
        if not isinstance(values, list):
            return ()
        names: list[str] = []
        for value in values:
            if not isinstance(value, str):
                continue
            normalized = " ".join(value.split()).strip()
            if normalized and len(normalized) <= 80 and normalized not in names:
                names.append(normalized)
            if len(names) == 5:
                break
        return tuple(names)

    async def search(self, job: RefreshJob) -> list[BrokerSearchResult]:
'''
if text.count(old) != 1:
    raise SystemExit('search signature mismatch')
text = text.replace(old, new, 1)

old = '''    @staticmethod
    def _queries(job: RefreshJob) -> tuple[str, str, str]:
        # Coordinates are the coarse grid centre, never the app's raw point.
        area = job.region.focus.strip() or f"{job.region.latitude:.3f},{job.region.longitude:.3f}"
'''
new = '''    @staticmethod
    def _localized_focus(job: RefreshJob, region_names: tuple[str, ...] = ()) -> str:
        focus = " ".join(job.region.focus.split()).strip()
        generic = focus in {"区域探索资料", "regional exploration material"}
        if region_names:
            prefix = " ".join(region_names[:3])
            return prefix if generic or not focus else f"{prefix} {focus}"
        if generic or not focus:
            return f"{job.region.latitude:.3f},{job.region.longitude:.3f}附近"
        return focus

    @staticmethod
    def _localized_job(job: RefreshJob, region_names: tuple[str, ...] = ()) -> RefreshJob:
        focus = BrokerClient._localized_focus(job, region_names)
        if focus == job.region.focus:
            return job
        region = RegionReference(
            job.region.region_id,
            job.region.latitude,
            job.region.longitude,
            job.region.locale,
            job.region.mission_type,
            focus,
            job.region.radius_meters,
        )
        return RefreshJob(
            job.fingerprint,
            region,
            job.expires_at,
            job.attempt,
            job.activation_type,
            job.dedupe_key,
        )

    @staticmethod
    def _queries(job: RefreshJob) -> tuple[str, str, str]:
        # Coordinates are the coarse grid centre, never the app's raw point.
        # Reverse-geocoded names are search hints only; product facts still
        # require reviewed evidence during extraction and admission.
        area = job.region.focus.strip() or f"{job.region.latitude:.3f},{job.region.longitude:.3f}"
'''
if text.count(old) != 1:
    raise SystemExit('query block mismatch')
text = text.replace(old, new, 1)

old = '''        else:
            evidence = await broker.search(job)
            if not evidence:
'''
new = '''        else:
            search_job = job
            if isinstance(broker, BrokerClient):
                region_names = await broker.resolve_region(job)
                search_job = broker._localized_job(job, region_names)
            evidence = await broker.search(search_job)
            if not evidence:
'''
if text.count(old) != 1:
    raise SystemExit('process search block mismatch')
text = text.replace(old, new, 1)

old = '''            selected = select_evidence(
                evidence,
                mission_type=job.region.mission_type,
                focus=job.region.focus,
'''
new = '''            selected = select_evidence(
                evidence,
                mission_type=job.region.mission_type,
                focus=search_job.region.focus,
'''
if text.count(old) != 1:
    raise SystemExit('selection focus mismatch')
text = text.replace(old, new, 1)

old = '''                extracted, extracted_insights = await broker.extract_with_insights(
                    job,
                    selected,
                )
'''
new = '''                extracted, extracted_insights = await broker.extract_with_insights(
                    search_job,
                    selected,
                )
'''
if text.count(old) != 1:
    raise SystemExit('extract call mismatch')
text = text.replace(old, new, 1)
text = text.replace(
    "                resolved = await broker.resolve_place(job, candidate)\n",
    "                resolved = await broker.resolve_place(search_job, candidate)\n",
    1,
)
text = text.replace(
    "            admitted = [(candidate, linked) for candidate in resolved_candidates if (linked := is_admissible(candidate, evidence_pool, job))]\n",
    "            admitted = [(candidate, linked) for candidate in resolved_candidates if (linked := is_admissible(candidate, evidence_pool, search_job))]\n",
    1,
)
worker.write_text(text)"""
body = body[:worker_start] + replacement + body[worker_end:]
body = body.replace(
    '    queries = BrokerClient._queries(job(), ("西湖风景名胜区", "北山街道", "西湖区"))\n',
    '    localized = BrokerClient._localized_job(job(), ("西湖风景名胜区", "北山街道", "西湖区"))\n'
    '    queries = BrokerClient._queries(localized)\n',
)
exec(compile(body, 'region-query-localization', 'exec'))
