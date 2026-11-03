import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/mission/mission_repository.dart';

final missionRemoteRepositoryProvider = Provider<MissionRemoteRepository?>((
  ref,
) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured || config.lumaNestServiceToken.isEmpty) {
    return null;
  }
  return DioMissionRemoteRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 5),
      ),
    ),
  );
});
