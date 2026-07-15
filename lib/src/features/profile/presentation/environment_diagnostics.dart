import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';

/// Sanitized, user-facing diagnostic category for the environment stack.
///
/// Values describe only the recovery category and never expose configuration
/// keys, API hosts, tokens or raw exception text.
enum EnvironmentDiagnosticStatus {
  /// Everything is working; the diagnostics widget reserves no space.
  operational,

  /// AMap (map) configuration is not available.
  /// Recovery action: review privacy consent.
  amapConfigMissing,

  /// QWeather configuration is not available; weather data cannot load.
  /// Recovery action: retry after configuration.
  qweatherConfigMissing,

  /// Location permission was denied.
  /// Recovery action: open OS location/app settings.
  locationPermissionDenied,

  /// Location permission was permanently denied.
  /// Recovery action: open OS app settings.
  locationPermissionDeniedForever,

  /// The location service is disabled at the OS level.
  /// Recovery action: open OS location settings.
  locationServiceDisabled,

  /// The environment snapshot is served from stale cache.
  /// Recovery action: retry the environment refresh.
  staleCache,
}

/// Recovery action callbacks injected into [EnvironmentDiagnostics].
///
/// The widget never calls platform APIs directly; the caller wires these
/// callbacks to the appropriate navigation or platform invocation. This keeps
/// the widget fully testable without a real device.
class EnvironmentDiagnosticsActions {
  const EnvironmentDiagnosticsActions({
    this.onRetry,
    this.onOpenAppSettings,
    this.onOpenLocationSettings,
    this.onOpenPrivacyConsent,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onOpenLocationSettings;
  final VoidCallback? onOpenPrivacyConsent;
}

/// Renders concise, sanitized recovery guidance for environment issues.
///
/// When [status] is [EnvironmentDiagnosticStatus.operational], the widget
/// builds a zero-height [SizedBox] — a healthy system reserves no space.
/// Otherwise it renders a single-line message paired with an optional action
/// button whose callback is injected by the caller.
class EnvironmentDiagnostics extends StatelessWidget {
  const EnvironmentDiagnostics({
    super.key,
    required this.status,
    this.actions = const EnvironmentDiagnosticsActions(),
  });

  final EnvironmentDiagnosticStatus status;
  final EnvironmentDiagnosticsActions actions;

  @override
  Widget build(BuildContext context) {
    if (status == EnvironmentDiagnosticStatus.operational) {
      return const SizedBox.shrink();
    }

    final message = _messageFor(status);
    final actionLabel = _actionLabelFor(status);
    final callback = _callbackFor(status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          if (callback != null && actionLabel != null)
            TextButton(onPressed: callback, child: Text(actionLabel)),
        ],
      ),
    );
  }

  String _messageFor(EnvironmentDiagnosticStatus status) {
    return switch (status) {
      EnvironmentDiagnosticStatus.operational => '',
      EnvironmentDiagnosticStatus.amapConfigMissing => '地图配置未完成，无法显示探索地图',
      EnvironmentDiagnosticStatus.qweatherConfigMissing => '天气配置未完成，无法获取实时天气',
      EnvironmentDiagnosticStatus.locationPermissionDenied =>
        '未授予定位权限，无法获取当前位置',
      EnvironmentDiagnosticStatus.locationPermissionDeniedForever =>
        '定位权限被永久拒绝，请在系统设置中开启',
      EnvironmentDiagnosticStatus.locationServiceDisabled =>
        '定位服务已关闭，请在系统设置中开启',
      EnvironmentDiagnosticStatus.staleCache => '网络不可用，正在显示缓存的场景数据',
    };
  }

  String? _actionLabelFor(EnvironmentDiagnosticStatus status) {
    return switch (status) {
      EnvironmentDiagnosticStatus.operational => null,
      EnvironmentDiagnosticStatus.amapConfigMissing => '查看隐私授权',
      EnvironmentDiagnosticStatus.qweatherConfigMissing => '重试',
      EnvironmentDiagnosticStatus.locationPermissionDenied => '打开设置',
      EnvironmentDiagnosticStatus.locationPermissionDeniedForever => '打开设置',
      EnvironmentDiagnosticStatus.locationServiceDisabled => '打开设置',
      EnvironmentDiagnosticStatus.staleCache => '重试',
    };
  }

  VoidCallback? _callbackFor(EnvironmentDiagnosticStatus status) {
    return switch (status) {
      EnvironmentDiagnosticStatus.operational => null,
      EnvironmentDiagnosticStatus.amapConfigMissing =>
        actions.onOpenPrivacyConsent,
      EnvironmentDiagnosticStatus.qweatherConfigMissing => actions.onRetry,
      EnvironmentDiagnosticStatus.locationPermissionDenied =>
        actions.onOpenAppSettings,
      EnvironmentDiagnosticStatus.locationPermissionDeniedForever =>
        actions.onOpenAppSettings,
      EnvironmentDiagnosticStatus.locationServiceDisabled =>
        actions.onOpenLocationSettings,
      EnvironmentDiagnosticStatus.staleCache => actions.onRetry,
    };
  }
}

/// Computes the current sanitized diagnostic status from the environment
/// configuration and snapshot providers.
///
/// Configuration is checked first. The Broker is now the primary environment
/// source; legacy direct QWeather configuration is sufficient only as a
/// migration fallback. AMap config is surfaced only when the snapshot itself
/// is healthy. The provider never exposes secret values.
final environmentDiagnosticStatusProvider =
    Provider<EnvironmentDiagnosticStatus>((ref) {
      final EnvironmentConfig config;
      try {
        config = ref.watch(environmentConfigProvider);
      } on Object {
        return EnvironmentDiagnosticStatus.qweatherConfigMissing;
      }

      if (!config.isDataBrokerConfigured && !config.isQWeatherConfigured) {
        return EnvironmentDiagnosticStatus.qweatherConfigMissing;
      }

      if (!ref.watch(environmentConsentProvider)) {
        return EnvironmentDiagnosticStatus.operational;
      }

      final snapshot = ref.watch(environmentSnapshotProvider);

      final snapshotStatus = snapshot.when(
        data: (data) => data.isStale
            ? EnvironmentDiagnosticStatus.staleCache
            : EnvironmentDiagnosticStatus.operational,
        loading: () => EnvironmentDiagnosticStatus.operational,
        error: (error, stackTrace) {
          if (error is EnvironmentLoadFailure) {
            return switch (error.kind) {
              EnvironmentFailureKind.configMissing =>
                EnvironmentDiagnosticStatus.qweatherConfigMissing,
              EnvironmentFailureKind.location => _locationStatus(error.cause),
              EnvironmentFailureKind.weather =>
                EnvironmentDiagnosticStatus.staleCache,
            };
          }
          return EnvironmentDiagnosticStatus.operational;
        },
      );

      if (snapshotStatus == EnvironmentDiagnosticStatus.operational &&
          !config.isAmapConfigured) {
        return EnvironmentDiagnosticStatus.amapConfigMissing;
      }

      return snapshotStatus;
    });

EnvironmentDiagnosticStatus _locationStatus(Object? cause) {
  if (cause is LocationRepositoryFailure) {
    return switch (cause.kind) {
      LocationFailureKind.permissionDenied =>
        EnvironmentDiagnosticStatus.locationPermissionDenied,
      LocationFailureKind.permissionDeniedForever =>
        EnvironmentDiagnosticStatus.locationPermissionDeniedForever,
      LocationFailureKind.serviceDisabled =>
        EnvironmentDiagnosticStatus.locationServiceDisabled,
      LocationFailureKind.unavailable =>
        EnvironmentDiagnosticStatus.locationPermissionDenied,
    };
  }
  return EnvironmentDiagnosticStatus.locationPermissionDenied;
}
