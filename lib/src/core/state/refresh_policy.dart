import 'package:luma_nest/src/core/state/environment_state.dart';

class RefreshPolicy {
  const RefreshPolicy({required this.ttl, required this.trigger});

  final Duration ttl;
  final String trigger;
}

const defaultRefreshPolicies = <EnvironmentSliceKey, RefreshPolicy>{
  EnvironmentSliceKey.location: RefreshPolicy(
    ttl: Duration(minutes: 5),
    trigger: 'movement_or_manual_location',
  ),
  EnvironmentSliceKey.weather: RefreshPolicy(
    ttl: Duration(minutes: 10),
    trigger: 'ttl_or_authority_update',
  ),
  EnvironmentSliceKey.airQuality: RefreshPolicy(
    ttl: Duration(minutes: 45),
    trigger: 'ttl',
  ),
  EnvironmentSliceKey.solar: RefreshPolicy(
    ttl: Duration(minutes: 5),
    trigger: 'phase_boundary',
  ),
  EnvironmentSliceKey.nearby: RefreshPolicy(
    ttl: Duration(minutes: 10),
    trigger: 'movement_or_intent',
  ),
};
