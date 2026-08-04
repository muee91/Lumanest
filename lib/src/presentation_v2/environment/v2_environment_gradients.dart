import 'package:flutter/material.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';

abstract final class V2EnvironmentGradients {
  static LinearGradient forMetric(EnvironmentMetricType type) => switch (type) {
    EnvironmentMetricType.cloud => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF5F8FA), Color(0xFFE7EEF3)],
    ),
    EnvironmentMetricType.light => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFF8E8), Color(0xFFF4E7CA)],
    ),
    EnvironmentMetricType.precipitation => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF0F7FA), Color(0xFFDCEAF0)],
    ),
    EnvironmentMetricType.wind => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF2F8F5), Color(0xFFDDECE5)],
    ),
    EnvironmentMetricType.visibility => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF7FAFB), Color(0xFFE7F0F2)],
    ),
    EnvironmentMetricType.air => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF5F5FA), Color(0xFFE9E7F1)],
    ),
    EnvironmentMetricType.temperature => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFAF2), Color(0xFFF2E9DC)],
    ),
  };

  static Color iconColor(EnvironmentMetricType type) => switch (type) {
    EnvironmentMetricType.cloud => const Color(0xFF526F82),
    EnvironmentMetricType.light => const Color(0xFFA87525),
    EnvironmentMetricType.precipitation => const Color(0xFF3E7690),
    EnvironmentMetricType.wind => const Color(0xFF4E806C),
    EnvironmentMetricType.visibility => const Color(0xFF527887),
    EnvironmentMetricType.air => const Color(0xFF6F678A),
    EnvironmentMetricType.temperature => const Color(0xFF92704E),
  };
}
