import 'package:flutter/material.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/monitoring/crash_monitoring.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runLumaNestWithCrashMonitoring(
    config: EnvironmentConfig.fromEnvironment(),
    appRunner: () => runApp(const LumaNestApp()),
  );
}
