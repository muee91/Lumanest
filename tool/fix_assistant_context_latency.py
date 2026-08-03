from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "services/lumanest-data-broker/src/server.mjs"
TEST = ROOT / "services/lumanest-data-broker/test/server.test.mjs"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected one match in {path}, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")


old_context = """      const assistantContext = await buildAssistantContextEnvelope({
        snapshot,
        providerFactsService: activeProviderFactsService,
        loadRegionBrief: (regionBody) => forwardRegionBrief({
          body: regionBody,
          serviceUrl: configuration.discoveryServiceUrl,
          internalToken: configuration.discoveryInternalToken,
          sourcePolicies: configuration.discoverySearchProfile.sourcePolicies,
          fetcher,
          timeoutMs: Math.min(configuration.settings.upstreamTimeoutMs, 2_000),
        }),
        now: assistantNow,
        timeoutMs: Math.min(configuration.settings.upstreamTimeoutMs, 2_000),
      });
"""
new_context = """      const modelEligible = effectiveQuestionType !== 'safety' &&
        effectiveQuestionType !== 'shootingPlan' &&
        configuration.settings.aiEnabled &&
        configuration.llmRouting.primaryProfileId != null;
      const assistantContext = modelEligible
        ? await buildAssistantContextEnvelope({
            snapshot,
            providerFactsService: activeProviderFactsService,
            loadRegionBrief: (regionBody) => forwardRegionBrief({
              body: regionBody,
              serviceUrl: configuration.discoveryServiceUrl,
              internalToken: configuration.discoveryInternalToken,
              sourcePolicies: configuration.discoverySearchProfile.sourcePolicies,
              fetcher,
              timeoutMs: Math.min(configuration.settings.upstreamTimeoutMs, 2_000),
            }),
            now: assistantNow,
            timeoutMs: Math.min(configuration.settings.upstreamTimeoutMs, 2_000),
          })
        : Object.freeze({
            contextFacts: '',
            sources: Object.freeze([]),
            factIds: Object.freeze([]),
            expiresAt: snapshot.expiresAt,
          });
"""
replace_once(SERVER, old_context, new_context)
replace_once(
    SERVER,
    "      if (effectiveQuestionType !== 'safety' && effectiveQuestionType !== 'shootingPlan' && configuration.settings.aiEnabled && configuration.llmRouting.primaryProfileId != null) {\n",
    "      if (modelEligible) {\n",
)

TEST.write_text(TEST.read_text(encoding="utf-8") + r'''

test('deterministic safety assistant performs no Region Brief or Provider requests', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.assistantContextBinding = {
    locale: 'zh-CN',
    region: { latitude: 30.275, longitude: 120.175, radiusMeters: 5000 },
    sceneProfile: {
      physicalScene: 'urban', facets: [], settlement: 'urbanDistrict',
      remoteness: 'unknown', altitude: 'unknown', poiDensity: 'unknown',
      mobility: 'stationary', routeStage: 'none',
    },
  };
  companionStore.rememberSnapshot(snapshot);

  let upstreamCalls = 0;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        questionType: 'safety',
        question: '现在安全吗？',
        eventIds: [],
        tone: 'balanced',
      }),
    });
    assert.equal(response.status, 200);
    const events = await readSseEvents(response);
    const done = events.find((event) => event.event === 'done');
    assert.equal(done.data.source, 'template');
  }, {
    companionStore,
    now: () => now,
    fetcher: async () => {
      upstreamCalls += 1;
      return new Response('{}', { status: 503, headers: { 'Content-Type': 'application/json' } });
    },
  });

  assert.equal(upstreamCalls, 0);
});
''', encoding="utf-8")

print("assistant deterministic latency boundary applied")
