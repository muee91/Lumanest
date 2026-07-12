import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';

class InspirationPage extends ConsumerStatefulWidget {
  const InspirationPage({super.key, this.snapshotAsync});

  /// Allows deterministic widget tests without starting the live environment.
  final AsyncValue<ContextSnapshot>? snapshotAsync;

  @override
  ConsumerState<InspirationPage> createState() => _InspirationPageState();
}

class _InspirationPageState extends ConsumerState<InspirationPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  void _draw(int count) {
    if (count < 2) return;
    setState(() => _index = (_index + 1) % count);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ContextSnapshot> snapshotAsync =
        widget.snapshotAsync ?? ref.watch(environmentSnapshotProvider);
    return snapshotAsync.when(
      loading: () => _BottleScaffold(
        notes: InspirationNotes.build(_fallbackSnapshot()),
        selectedIndex: _index,
        onDraw: _draw,
        controller: _controller,
        onAction: _performAction,
      ),
      error: (_, _) => _BottleScaffold(
        notes: InspirationNotes.build(_fallbackSnapshot()),
        selectedIndex: _index,
        onDraw: _draw,
        controller: _controller,
        onAction: _performAction,
      ),
      data: (snapshot) => _BottleScaffold(
        notes: InspirationNotes.build(snapshot),
        selectedIndex: _index,
        onDraw: _draw,
        controller: _controller,
        onAction: _performAction,
      ),
    );
  }

  ContextSnapshot _fallbackSnapshot() => ContextSnapshot(
    id: 'inspiration-fallback',
    observedAt: DateTime.now(),
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    primaryScene: SceneType.unknown,
    dayPhase: DayPhase.day,
    weather: WeatherType.clear,
    activeRoute: false,
  );

  void _performAction(InspirationNote note) {
    switch (note.action) {
      case ManifestAction.openExplore:
        context.go('/explore');
      case ManifestAction.openShootingWindow:
      case ManifestAction.openWeather:
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.displayLabel,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(note.detail),
              ],
            ),
          ),
        );
      case ManifestAction.openSafety:
        break;
    }
  }
}

class _BottleScaffold extends StatelessWidget {
  const _BottleScaffold({
    required this.notes,
    required this.selectedIndex,
    required this.onDraw,
    required this.controller,
    required this.onAction,
  });
  final List<InspirationNote> notes;
  final int selectedIndex;
  final void Function(int count) onDraw;
  final AnimationController controller;
  final void Function(InspirationNote note) onAction;

  @override
  Widget build(BuildContext context) {
    final index = notes.isEmpty ? 0 : selectedIndex % notes.length;
    final note = notes[index];
    return Scaffold(
      appBar: AppBar(title: const Text('灵感瓶')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Center(
                child: Text('此时此地的创作线索', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 22),
              Center(
                child: GestureDetector(
                  onTap: () => onDraw(notes.length),
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (_, child) => Transform.rotate(
                      angle: controller.value < .5
                          ? controller.value * .1
                          : (1 - controller.value) * .1,
                      child: child,
                    ),
                    child: Container(
                      width: 250,
                      height: 340,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(55),
                          bottom: Radius.circular(78),
                        ),
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primaryContainer
                                .withValues(alpha: .82),
                            Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: .72),
                          ],
                        ),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: Stack(
                        children: [
                          for (var i = 0; i < notes.length; i++)
                            Positioned(
                              left: 28 + (i % 2) * 62.0,
                              top: 72 + (i ~/ 2) * 56.0,
                              child: Transform.rotate(
                                angle: (i - 2) * .08,
                                child: _Paper(
                                  text: notes[i].displayLabel,
                                  faded: notes[i] != note,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _Paper(
                  key: ValueKey(note.id),
                  text: note.displayLabel,
                  large: true,
                ),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  note.detail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => onAction(note),
                icon: const Icon(Icons.arrow_outward),
                label: const Text('去看看'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => onDraw(notes.length),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('抽一张纸条'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({
    super.key,
    required this.text,
    this.faded = false,
    this.large = false,
  });
  final String text;
  final bool faded;
  final bool large;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: faded ? .55 : 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(1, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 26 : 12,
          vertical: large ? 18 : 9,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: large ? 24 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
