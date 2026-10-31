import 'package:flutter/material.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/core/config/client_session_bootstrap.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/monitoring/crash_monitoring.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await bootstrapBrokerSession(
    EnvironmentConfig.fromEnvironment(),
  );
  await runLumaNestWithCrashMonitoring(
    config: config,
    appRunner: () => runApp(LumaNestApp(config: config)),
  );
}
