import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_bottle_layout.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';

void main() {
  test('paper positions are deterministic for one snapshot and note set', () {
    final notes = InspirationNotes.build(
      ContextFixtures.lakeSunset(observedAt: DateTime.now()),
    );
    final first = InspirationBottleLayout.build(
      snapshotId: 'lake-1',
      notes: notes,
    );
    final second = InspirationBottleLayout.build(
      snapshotId: 'lake-1',
      notes: notes,
    );

    expect(second.map((item) => item.id), first.map((item) => item.id));
    expect(
      second.map((item) => item.leftFraction),
      first.map((item) => item.leftFraction),
    );
    expect(
      first.every((item) => item.leftFraction >= .1 && item.topFraction <= .61),
      isTrue,
    );
  });

  test('changing the snapshot reseeds positions without creating notes', () {
    final notes = InspirationNotes.build(
      ContextFixtures.lakeSunset(observedAt: DateTime.now()),
    );
    final first = InspirationBottleLayout.build(snapshotId: 'a', notes: notes);
    final second = InspirationBottleLayout.build(snapshotId: 'b', notes: notes);

    expect(
      second.map((item) => item.id).toSet(),
      first.map((item) => item.id).toSet(),
    );
    expect(
      second.map((item) => item.leftFraction).join(','),
      isNot(first.map((item) => item.leftFraction).join(',')),
    );
  });
}
