import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:x_amap_base/x_amap_base.dart';

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

  @override
  MapConsentState build() {
    final config = ref.watch(environmentConfigProvider);
    if (!config.isAmapConfigured) {
      return const MapConsentConfigurationMissing();
    }
    return const MapConsentAwaiting();
  }

  void grantConsent() {
    if (state is MapConsentConfigurationMissing) return;
    if (state is MapConsentReady) return;

    final gateway = ref.read(amapInitializerGatewayProvider);
    gateway.updatePrivacyAgree(
      const AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true,
      ),
    );

    state = const MapConsentReady();
  }

  void revokeConsent() {
    if (state is MapConsentConfigurationMissing) return;
    ref
        .read(amapInitializerGatewayProvider)
        .updatePrivacyAgree(
          const AMapPrivacyStatement(
            hasContains: true,
            hasShow: true,
            hasAgree: false,
          ),
        );
    _initialized = false;
    state = const MapConsentAwaiting();
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
