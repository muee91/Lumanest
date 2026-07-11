import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls whether the app may begin loading current-location environment
/// data. This is distinct from the operating system location permission:
/// users opt in here first, then the platform may ask for location access.
class EnvironmentConsentController extends Notifier<bool> {
  @override
  bool build() => false;

  void grant() => state = true;
}

final environmentConsentProvider =
    NotifierProvider<EnvironmentConsentController, bool>(
      EnvironmentConsentController.new,
    );
