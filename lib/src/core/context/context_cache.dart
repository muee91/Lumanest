import 'package:luma_nest/src/core/context/context_snapshot.dart';

abstract interface class ContextCache {
  Future<ContextSnapshot?> readLatest();

  Future<void> write(ContextSnapshot snapshot);

  Future<void> clear();
}

class InMemoryContextCache implements ContextCache {
  ContextSnapshot? _latest;

  @override
  Future<ContextSnapshot?> readLatest() async => _latest;

  @override
  Future<void> write(ContextSnapshot snapshot) async {
    _latest = snapshot;
  }

  @override
  Future<void> clear() async {
    _latest = null;
  }
}
