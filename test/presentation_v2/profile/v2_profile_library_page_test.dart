import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/presentation_v2/profile/v2_profile_page.dart';

class _FakeStore implements UserLibraryStore {
  _FakeStore(this.value);
  UserLibraryState value;

  @override
  Future<UserLibraryState> read() async => value;

  @override
  Future<void> write(UserLibraryState state) async => value = state;
}

void main() {
  testWidgets('我留下的页面不再展示离线包或 GPX 轨迹数量', (tester) async {
    final store = _FakeStore(
      const UserLibraryState(
        savedNotes: [],
        savedPlaces: [],
        watchedSessions: [],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userLibraryStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: V2ProfileLibraryPage()),
      ),
    );
    await tester.pump();

    expect(find.text('离线包'), findsNothing);
    expect(find.textContaining('离线包'), findsNothing);
    expect(find.textContaining('轨迹'), findsNothing);
  });
}
