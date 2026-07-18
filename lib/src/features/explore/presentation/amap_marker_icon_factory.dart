import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

class AmapExploreMarkerIcons {
  const AmapExploreMarkerIcons({
    required this.regular,
    required this.selected,
    required this.search,
    required this.selectedSearch,
  });

  final Map<NearbyPlaceCategory, BitmapDescriptor> regular;
  final Map<NearbyPlaceCategory, BitmapDescriptor> selected;
  final BitmapDescriptor search;
  final BitmapDescriptor selectedSearch;
}

abstract final class AmapMarkerIconFactory {
  static Future<AmapExploreMarkerIcons> build() async {
    final regular = <NearbyPlaceCategory, BitmapDescriptor>{};
    final selected = <NearbyPlaceCategory, BitmapDescriptor>{};
    for (final category in NearbyPlaceCategory.values) {
      regular[category] = await _render(
        icon: iconFor(category),
        color: colorFor(category),
      );
      selected[category] = await _render(
        icon: iconFor(category),
        color: colorFor(category),
        selected: true,
      );
    }
    return AmapExploreMarkerIcons(
      regular: Map.unmodifiable(regular),
      selected: Map.unmodifiable(selected),
      search: await _render(
        icon: Icons.search_rounded,
        color: const Color(0xFF303A36),
      ),
      selectedSearch: await _render(
        icon: Icons.search_rounded,
        color: const Color(0xFF303A36),
        selected: true,
      ),
    );
  }

  static IconData iconFor(NearbyPlaceCategory category) => switch (category) {
    NearbyPlaceCategory.viewpoint => Icons.photo_camera_outlined,
    NearbyPlaceCategory.sunriseCandidate => Icons.wb_sunny_rounded,
    NearbyPlaceCategory.nightSkyCandidate => Icons.nightlight_round,
    NearbyPlaceCategory.waterfront => Icons.water_rounded,
    NearbyPlaceCategory.humanity => Icons.account_balance_outlined,
    NearbyPlaceCategory.fuel => Icons.local_gas_station_outlined,
    NearbyPlaceCategory.food => Icons.restaurant_rounded,
    NearbyPlaceCategory.supply => Icons.shopping_bag_outlined,
    NearbyPlaceCategory.parking => Icons.local_parking_rounded,
    NearbyPlaceCategory.medical => Icons.local_hospital_outlined,
  };

  static Color colorFor(NearbyPlaceCategory category) => switch (category) {
    NearbyPlaceCategory.viewpoint => const Color(0xFF789A3E),
    NearbyPlaceCategory.sunriseCandidate => const Color(0xFFF5794B),
    NearbyPlaceCategory.nightSkyCandidate => const Color(0xFF405779),
    NearbyPlaceCategory.waterfront => const Color(0xFF4F9297),
    NearbyPlaceCategory.humanity => const Color(0xFFA86F4F),
    NearbyPlaceCategory.fuel => const Color(0xFFB78638),
    NearbyPlaceCategory.food => const Color(0xFFC96152),
    NearbyPlaceCategory.supply => const Color(0xFF718462),
    NearbyPlaceCategory.parking => const Color(0xFF5C748E),
    NearbyPlaceCategory.medical => const Color(0xFFC54E59),
  };

  static Future<BitmapDescriptor> _render({
    required IconData icon,
    required Color color,
    bool selected = false,
  }) async {
    final side = selected ? 104 : 84;
    final center = ui.Offset(side / 2, side / 2 - 5);
    final radius = selected ? 35.0 : 28.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final shadow = ui.Paint()
      ..color = Colors.black.withValues(alpha: selected ? .28 : .18)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawCircle(center.translate(0, 3), radius + 3, shadow);

    final tail = ui.Path()
      ..moveTo(center.dx - 9, center.dy + radius - 4)
      ..lineTo(center.dx, side - 4)
      ..lineTo(center.dx + 9, center.dy + radius - 4)
      ..close();
    canvas.drawPath(tail, ui.Paint()..color = color);
    canvas.drawCircle(
      center,
      radius,
      ui.Paint()..color = selected ? const Color(0xFF18211E) : color,
    );
    canvas.drawCircle(
      center,
      radius,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = selected ? 6 : 4
        ..color = Colors.white.withValues(alpha: selected ? 1 : .92),
    );

    final family = icon.fontPackage == null
        ? icon.fontFamily
        : 'packages/${icon.fontPackage}/${icon.fontFamily}';
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: Colors.white,
          fontSize: selected ? 38 : 30,
          fontFamily: family,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - ui.Offset(painter.width / 2, painter.height / 2),
    );

    final image = await recorder.endRecording().toImage(side, side);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return BitmapDescriptor.defaultMarker;
    return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
  }
}
