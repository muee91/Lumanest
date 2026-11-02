import 'package:flutter/material.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/core/config/client_session_bootstrap.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/monitoring/crash_monitoring.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await bootstrapBrokerSession(
    EnvironmentConfig.fromEnvironment(),
  );
  await runLumaNestWithCrashMonitoring(
    config: bootstrap.config,
    appRunner: () => runApp(
      LumaNestApp(
        config: bootstrap.config,
        sessionCredentials: bootstrap.credentials,
      ),
    ),
  );
}
