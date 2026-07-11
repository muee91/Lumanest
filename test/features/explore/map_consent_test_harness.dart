import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:x_amap_base/x_amap_base.dart';

class FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAmapInitializerGateway implements AmapInitializerGateway {
  bool privacyAgreed = false;
  bool initialized = false;
  int privacyCallIndex = -1;
  int initCallIndex = -1;
  int totalCalls = 0;
  AMapPrivacyStatement? lastStatement;
  AMapApiKey? lastApiKey;

  @override
  void updatePrivacyAgree(AMapPrivacyStatement statement) {
    privacyAgreed = statement.hasAgree == true;
    privacyCallIndex = totalCalls;
    totalCalls++;
    lastStatement = statement;
  }

  @override
  void init(BuildContext context, {AMapApiKey? apiKey}) {
    initialized = true;
    initCallIndex = totalCalls;
    totalCalls++;
    lastApiKey = apiKey;
  }
}

ProviderContainer createMapTestContainer({
  required String amapKey,
  AmapInitializerGateway? gateway,
}) {
  final container = ProviderContainer(
    overrides: [
      environmentConfigProvider.overrideWithValue(
        EnvironmentConfig(amapAndroidKey: amapKey),
      ),
      amapInitializerGatewayProvider.overrideWithValue(
        gateway ?? FakeAmapInitializerGateway(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
