# Operational Observability

The Broker exposes authenticated, LAN-only operational aggregates for Region Brief, AI context-envelope coverage, and Provider Hub runtime coverage.

## Privacy boundary

The aggregator stores no exact coordinates, region names, prompts, answers, source URLs, snapshot identifiers, or raw fact text. Labels are fixed enumerations. Metrics are process-local and reset on restart.

## AI context boundary

AI context is resolved server-side from the remembered Context snapshot, Region Brief, route weather, and Provider Facts. Candidate evidence is excluded, missing data is never inferred, and official safety or restriction content remains on the independent safety chain. A structured `coverage` object records component availability without carrying raw facts.

## Admin surface

`GET /admin-api/observability` is authenticated and LAN-only. The Data Observability page reports rates and counts only. Prometheus output includes bounded Region Brief and assistant-context counters.

## Verification scope

CI validates the bounded aggregator, context-envelope coverage contract, authenticated admin endpoint, external-scripted dashboard, the full Broker suite, Flutter analysis and tests, and the Android debug build.