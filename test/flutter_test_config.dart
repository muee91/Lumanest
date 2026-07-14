import 'dart:async';

import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  appDatabaseFactory = AppDatabase.inMemory;
  await testMain();
}
