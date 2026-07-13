import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x_amap_base/x_amap_base.dart';

abstract interface class MapConsentStore {
  Future<bool?> readGranted();

  Future<void> writeGranted(bool granted);
}

class SharedPreferencesMapConsentStore implements MapConsentStore {
  SharedPreferencesMapConsentStore(this._preferences);

  static const _key = 'amap_privacy_consent_granted';
  final SharedPreferencesAsync _preferences;

  @override
  Future<bool?> readGranted() => _preferences.getBool(_key);

  @override
  Future<void> writeGranted(bool granted) =>
      _preferences.setBool(_key, granted);
}

final mapConsentStoreProvider = Provider<MapConsentStore>((ref) {
  return SharedPreferencesMapConsentStore(SharedPreferencesAsync());
});

sealed class MapConsentState {
  const MapConsentState();
}

class MapConsentConfigurationMissing extends MapConsentState {
  const MapConsentConfigurationMissing();
}

class MapConsentAwaiting extends MapConsentState {
  const MapConsentAwaiting();
}

class MapConsentReady extends MapConsentState {
  const MapConsentReady();
}

class MapConsentController extends Notifier<MapConsentState> {
  bool _initialized = false;
  bool _changedThisSession = false;
  Future<void> _writeChain = Future<void>.value();

  @override
  MapConsentState build() {
    final config = ref.watch(environmentConfigProvider);
    if (!config.isAmapConfigured) {
      return const MapConsentConfigurationMissing();
    }
    unawaited(_restore());
    return const MapConsentAwaiting();
  }

  Future<void> _restore() async {
    final restored = await ref.read(mapConsentStoreProvider).readGranted();
    if (_changedThisSession || restored != true) return;

    _updatePrivacyAgreement(hasAgree: true);
    state = const MapConsentReady();
  }

  Future<void> grantConsent() async {
    if (state is MapConsentConfigurationMissing) return;
    if (state is MapConsentReady) return;

    _changedThisSession = true;
    _updatePrivacyAgreement(hasAgree: true);
    state = const MapConsentReady();
    await _persist(true);
  }

  Future<void> revokeConsent() async {
    if (state is MapConsentConfigurationMissing) return;
    _changedThisSession = true;
    _updatePrivacyAgreement(hasAgree: false);
    _initialized = false;
    state = const MapConsentAwaiting();
    await _persist(false);
  }

  Future<void> _persist(bool granted) {
    final store = ref.read(mapConsentStoreProvider);
    final next = _writeChain.then(
      (_) => store.writeGranted(granted),
      onError: (_) => store.writeGranted(granted),
    );
    _writeChain = next;
    return next;
  }

  void _updatePrivacyAgreement({required bool hasAgree}) {
    ref
        .read(amapInitializerGatewayProvider)
        .updatePrivacyAgree(
          AMapPrivacyStatement(
            hasContains: true,
            hasShow: true,
            hasAgree: hasAgree,
          ),
        );
  }

  void ensureInitialized(BuildContext context) {
    if (state is! MapConsentReady) {
      throw StateError('Cannot initialize map before consent is granted');
    }
    if (_initialized) return;
    _initialized = true;

    final config = ref.read(environmentConfigProvider);
    ref
        .read(amapInitializerGatewayProvider)
        .init(context, apiKey: AMapApiKey(androidKey: config.amapAndroidKey));
  }
}

final mapConsentControllerProvider =
    NotifierProvider<MapConsentController, MapConsentState>(
      MapConsentController.new,
    );
