import 'dart:math' as math;

import 'inspiration_note.dart';

/// A deterministic, low-cost approximation of paper settling in a bottle.
///
/// It deliberately avoids a physics engine: positions are stable for a given
/// snapshot and note set, while staggered rows and a small seed-derived tilt
/// communicate gravity and collisions without draining the device.
class InspirationBottleLayout {
  const InspirationBottleLayout._();

  static List<BottlePaperLayout> build({
    required String snapshotId,
    required List<InspirationNote> notes,
  }) {
    final seed = _stableHash(
      '$snapshotId:${notes.map((note) => note.id).join('|')}',
    );
    final random = math.Random(seed);
    final order = List<InspirationNote>.from(notes)
      ..sort(
        (a, b) => _stableHash(
          '$snapshotId:${a.id}',
        ).compareTo(_stableHash('$snapshotId:${b.id}')),
      );
    return [
      for (var index = 0; index < order.length; index++)
        BottlePaperLayout(
          id: order[index].id,
          leftFraction: .10 + (index % 3) * .285 + random.nextDouble() * .028,
          topFraction: .61 - (index ~/ 3) * .17 - random.nextDouble() * .025,
          rotation: (random.nextDouble() - .5) * .34,
        ),
    ];
  }

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

class BottlePaperLayout {
  const BottlePaperLayout({
    required this.id,
    required this.leftFraction,
    required this.topFraction,
    required this.rotation,
  });

  final String id;
  final double leftFraction;
  final double topFraction;
  final double rotation;
}
