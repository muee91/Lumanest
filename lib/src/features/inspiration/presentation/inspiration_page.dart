import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_recovery.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/device/device_energy_providers.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/manifest/manifest_providers.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';
import 'package:luma_nest/src/features/inspiration/presentation/widgets/inspiration_bottle.dart';

class InspirationPage extends ConsumerWidget {
  const InspirationPage({
    super.key,
    this.snapshotAsync,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
    this.onExplore,
  });

  /// Allows deterministic widget tests without starting the live environment.
  final AsyncValue<ContextSnapshot>? snapshotAsync;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;
  final VoidCallback? onExplore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ContextSnapshot> snapshotAsync =
        this.snapshotAsync ?? ref.watch(environmentSnapshotProvider);
    final preferences = ref.watch(profilePreferencesProvider);
    final reduceMotion =
        preferences.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final conserveDeviceEnergy =
        ref.watch(deviceEnergyProvider).asData?.value.shouldConserveEnergy ??
        false;
    return snapshotAsync.when(
      loading: () => const Scaffold(
        appBar: _InspirationAppBar(),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _InspirationErrorView(
        error: error,
        onRetry:
            onRetry ??
            (this.snapshotAsync == null
                ? () => ref.read(environmentSnapshotProvider.notifier).refresh()
                : null),
        onOpenAppSettings:
            onOpenAppSettings ??
            (this.snapshotAsync == null ? Geolocator.openAppSettings : null),
        onSelectManualLocation:
            onSelectManualLocation ??
            (this.snapshotAsync == null
                ? () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => const ManualLocationSheet(),
                  )
                : null),
      ),
      data: (snapshot) {
        final narrative = ref.watch(manifestNarrativeProvider(snapshot));
        final manifest = ref.watch(personalizedManifestProvider(snapshot));
        final savedNoteIds =
            ref
                .watch(userLibraryProvider)
                .asData
                ?.value
                .savedNotes
                .map((note) => note.id)
                .toSet() ??
            const <String>{};
        return _BottleScaffold(
          notes: InspirationNotes.build(
            snapshot,
            narrative: narrative.asData?.value,
            manifest: manifest,
          ),
          snapshotId: snapshot.id,
          reduceMotion: reduceMotion,
          enableShake:
              preferences.ambientMotionMode == AmbientMotionMode.full &&
              !preferences.highContrast &&
              !conserveDeviceEnergy,
          onExplore: onExplore ?? () => context.go('/explore'),
          onAction: (note) => _performAction(context, note),
          isSaved: (note) => savedNoteIds.contains(
            SavedInspirationNote.idFor(
              snapshotId: snapshot.id,
              noteId: note.id,
            ),
          ),
          onSave: (note) => ref
              .read(userLibraryProvider.notifier)
              .saveInspirationNote(snapshotId: snapshot.id, note: note),
        );
      },
    );
  }

  void _performAction(BuildContext context, InspirationNote note) {
    handleManifestAction(
      context,
      ManifestItem(
        id: note.id,
        title: note.displayLabel,
        action: note.action,
        authorityUri: note.authorityUri,
      ),
      detailOverride: note.detail,
    );
  }
}

class _InspirationAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _InspirationAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: const Text('灵感'));
}

class _InspirationErrorView extends StatelessWidget {
  const _InspirationErrorView({
    required this.error,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
  });

  final Object error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied = isPermanentlyDeniedLocationFailure(error);
    final primaryAction = permanentlyDenied
        ? onOpenAppSettings ?? onRetry
        : onRetry;
    final primaryLabel = permanentlyDenied && onOpenAppSettings != null
        ? '打开设置'
        : '重试';
    return Scaffold(
      appBar: const _InspirationAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 44),
              const SizedBox(height: 12),
              const Text('暂时无法读取此刻的创作线索'),
              if (primaryAction != null || onSelectManualLocation != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (primaryAction case final action?)
                      FilledButton.tonal(
                        onPressed: action,
                        child: Text(primaryLabel),
                      ),
                    if (onSelectManualLocation case final action?)
                      OutlinedButton(
                        onPressed: action,
                        child: const Text('手动选择地点'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BottleScaffold extends StatefulWidget {
  const _BottleScaffold({
    required this.notes,
    required this.snapshotId,
    required this.reduceMotion,
    required this.enableShake,
    required this.onExplore,
    required this.onAction,
    this.onSave,
    this.isSaved,
  });
  final List<InspirationNote> notes;
  final String snapshotId;
  final bool reduceMotion;
  final bool enableShake;
  final VoidCallback onExplore;
  final void Function(InspirationNote note) onAction;
  final Future<void> Function(InspirationNote note)? onSave;
  final bool Function(InspirationNote note)? isSaved;

  @override
  State<_BottleScaffold> createState() => _BottleScaffoldState();
}

class _BottleScaffoldState extends State<_BottleScaffold> {
  var _selectedIndex = 0;
  var _hasDrawn = false;

  @override
  void didUpdateWidget(_BottleScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notes.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= widget.notes.length) {
      _selectedIndex = 0;
    }
  }

  void _draw() {
    if (widget.notes.isEmpty) return;
    setState(() {
      if (_hasDrawn) {
        _selectedIndex = (_selectedIndex + 1) % widget.notes.length;
      }
      _hasDrawn = true;
    });
    _openSelectedNote();
  }

  void _select(InspirationNote note) {
    final index = widget.notes.indexWhere((item) => item.id == note.id);
    if (index < 0) return;
    setState(() => _selectedIndex = index);
    _openSelectedNote();
  }

  void _openSelectedNote() {
    final note = widget.notes[_selectedIndex % widget.notes.length];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _InspirationNoteSheet(
        note: note,
        isSaved: widget.isSaved?.call(note) == true,
        onAction: () {
          Navigator.pop(context);
          widget.onAction(note);
        },
        onSave: widget.onSave == null || widget.isSaved?.call(note) == true
            ? null
            : () async {
                await widget.onSave!(note);
                if (context.mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(
                    this.context,
                  ).showSnackBar(const SnackBar(content: Text('已收藏')));
                }
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    if (notes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('灵感')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const SizedBox(height: 72),
              Icon(
                Icons.hourglass_empty_rounded,
                size: 38,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '此刻没有可抽取的纸条',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: widget.onExplore,
                  child: const Text('探索附近'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final index = _selectedIndex % notes.length;
    final note = notes[index];
    return Scaffold(
      appBar: AppBar(title: const Text('灵感')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                Text('此刻灵感', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${notes.length} 张',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: InspirationBottle(
                snapshotId: widget.snapshotId,
                notes: notes,
                selectedId: note.id,
                reduceMotion: widget.reduceMotion,
                enableShake: widget.enableShake,
                onDraw: _draw,
                onSelect: _select,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: FilledButton.icon(
                key: const Key('draw-inspiration-note'),
                onPressed: _draw,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('抽一张'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspirationNoteSheet extends StatelessWidget {
  const _InspirationNoteSheet({
    required this.note,
    required this.isSaved,
    required this.onAction,
    this.onSave,
  });

  final InspirationNote note;
  final bool isSaved;
  final VoidCallback onAction;
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .72,
    child: SingleChildScrollView(
      key: const Key('inspiration-note-sheet-scroll'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Paper(
            key: Key('selected-inspiration-${note.id}'),
            text: note.displayLabel,
            large: true,
          ),
          if (onSave != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_border),
              label: const Text('收藏纸条'),
            ),
          ] else if (isSaved)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: Text('已收藏')),
            ),
          const SizedBox(height: 18),
          Text(note.detail, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.arrow_outward),
            label: const Text('查看'),
          ),
        ],
      ),
    ),
  );
}

class _Paper extends StatelessWidget {
  const _Paper({super.key, required this.text, this.large = false});
  final String text;
  final bool large;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color:
          (Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFFF3E9D9)
                  : Colors.white)
              .withValues(alpha: .86),
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
        textAlign: large ? TextAlign.center : null,
        style: TextStyle(
          fontSize: large ? 24 : 13,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF2B2924),
        ),
      ),
    ),
  );
}
