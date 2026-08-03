import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';
import 'package:luma_nest/src/presentation_v2/explore/v2_provider_facts_sheet.dart';

void main() {
  testWidgets('summary reserves no space without current signals', (
    tester,
  ) async {
    final bundle = ProviderFactsBundle.fromJson(
      _body(providers: const <Object?>[]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: V2ProviderFactsSummaryCard(bundle: bundle, onTap: () {}),
        ),
      ),
    );

    expect(find.byKey(const Key('v2-provider-facts-summary')), findsNothing);
  });

  testWidgets('summary opens a traceable provider status sheet', (
    tester,
  ) async {
    final bundle = ProviderFactsBundle.fromJson(
      _body(providers: [_readyProvider()]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: V2ProviderFactsSummaryCard(
              bundle: bundle,
              onTap: () => showV2ProviderFactsSheet(context, bundle),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('近期光学观测'), findsOneWidget);
    await tester.tap(find.byKey(const Key('v2-provider-facts-summary')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('v2-provider-facts-sheet')), findsOneWidget);
    expect(find.text('近期光学观测'), findsOneWidget);
    expect(find.text('数据源状态'), findsOneWidget);
    expect(
      find.byKey(const Key('v2-provider-state-sentinel2')),
      findsOneWidget,
    );
    expect(find.text('Copernicus'), findsOneWidget);
  });
}

Map<String, Object?> _body({required List<Object?> providers}) => {
  'contractVersion': 1,
  'requestedCoordinate': {
    'latitude': 30.25,
    'longitude': 120.15,
    'system': 'wgs84',
  },
  'radiusKm': 25,
  'generatedAt': DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 5))
      .toIso8601String(),
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
  'status': providers.isEmpty ? 'unavailable' : 'ready',
  'cacheStatus': 'miss',
  'providers': providers,
};

Map<String, Object?> _readyProvider() {
  final now = DateTime.now().toUtc();
  return {
    'id': 'sentinel2',
    'category': 'surface',
    'status': 'ready',
    'observedAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
    'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
    'source': {
      'id': 'copernicus-sentinel2',
      'title': 'Sentinel-2 catalogue',
      'publisher': 'Copernicus',
      'url': 'https://dataspace.copernicus.eu/',
      'license': 'Copernicus licence',
      'version': 'STAC 1.1',
    },
    'signals': [
      {
        'id': 'signal_111111111111111111111111',
        'kind': 'opticalAcquisition',
        'category': 'surface',
        'title': '近期光学观测',
        'summary': '卫星目录存在近期影像，栅格指标仍需后端计算。',
        'verification': 'observed',
        'observedAt': now
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
        'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
        'sourceUrl': 'https://dataspace.copernicus.eu/',
      },
    ],
    'message': null,
  };
}
