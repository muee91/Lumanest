import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';

class AmbientPalette {
  const AmbientPalette({
    required this.topColor,
    required this.bottomColor,
  });

  final Color topColor;
  final Color bottomColor;

  @override
  bool operator ==(Object other) =>
      other is AmbientPalette &&
      other.topColor == topColor &&
      other.bottomColor == bottomColor;

  @override
  int get hashCode => Object.hash(topColor, bottomColor);
}

class AmbientVisualMapper {
  const AmbientVisualMapper();

  AmbientPalette resolve(
    WeatherType weather,
    DayPhase dayPhase,
    Brightness brightness,
  ) {
    if (brightness == Brightness.dark) {
      return _darkPalette(weather);
    }
    return _lightPalette(weather);
  }

  static AmbientPalette _lightPalette(WeatherType weather) {
    return switch (weather) {
      WeatherType.clear => const AmbientPalette(
        topColor: Color(0xFFF0E6D3),
        bottomColor: Color(0xFFE8DCC8),
      ),
      WeatherType.cloudy => const AmbientPalette(
        topColor: Color(0xFFDCDBD6),
        bottomColor: Color(0xFFCFCEC8),
      ),
      WeatherType.rain => const AmbientPalette(
        topColor: Color(0xFFC4CDD6),
        bottomColor: Color(0xFFACB7C2),
      ),
      WeatherType.snow => const AmbientPalette(
        topColor: Color(0xFFE4EBF0),
        bottomColor: Color(0xFFD8E1E8),
      ),
      WeatherType.dust => const AmbientPalette(
        topColor: Color(0xFFE6DAC8),
        bottomColor: Color(0xFFD3C4A6),
      ),
    };
  }

  static AmbientPalette _darkPalette(WeatherType weather) {
    return switch (weather) {
      WeatherType.clear => const AmbientPalette(
        topColor: Color(0xFF1A1A2E),
        bottomColor: Color(0xFF0F0F1A),
      ),
      WeatherType.cloudy => const AmbientPalette(
        topColor: Color(0xFF262638),
        bottomColor: Color(0xFF181828),
      ),
      WeatherType.rain => const AmbientPalette(
        topColor: Color(0xFF1A1E28),
        bottomColor: Color(0xFF10141C),
      ),
      WeatherType.snow => const AmbientPalette(
        topColor: Color(0xFF1E2430),
        bottomColor: Color(0xFF161C26),
      ),
      WeatherType.dust => const AmbientPalette(
        topColor: Color(0xFF2C2620),
        bottomColor: Color(0xFF201C16),
      ),
    };
  }
}
