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
import 'package:luma_nest/src/shared/widgets/responsive_action_group.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_surface.dart';
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
    if (widget.notes.length < 2) return;
    setState(() => _selectedIndex = (_selectedIndex + 1) % widget.notes.length);
  }

  void _select(InspirationNote note) {
    final index = widget.notes.indexWhere((item) => item.id == note.id);
    if (index >= 0) setState(() => _selectedIndex = index);
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
              LumaNestSurface(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.hourglass_empty_rounded,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '此刻还没有可靠的创作线索',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前规则没有成立的创作事件。环境变化后，新的纸条会按需出现。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: widget.onExplore,
                      icon: const Icon(Icons.explore_outlined),
                      label: const Text('去探索附近'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '安全和风险始终留在独立通道，不会放进灵感瓶。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
            LumaNestEyebrow(
              label: '此时此地的创作线索',
              trailing: Text(
                '${notes.length} 张纸条',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 18),
            LumaNestSurface(
              tone: LumaNestSurfaceTone.paper,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '抽到的纸条',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    child: _Paper(
                      key: Key('selected-inspiration-${note.id}'),
                      text: note.displayLabel,
                      large: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    note.detail,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ResponsiveActionGroup(
              actions: [
                FilledButton.icon(
                  onPressed: () => widget.onAction(note),
                  icon: const Icon(Icons.arrow_outward),
                  label: const Text('去看看'),
                ),
                if (widget.onSave case final onSave?) ...[
                  OutlinedButton.icon(
                    onPressed: widget.isSaved?.call(note) == true
                        ? null
                        : () => onSave(note),
                    icon: Icon(
                      widget.isSaved?.call(note) == true
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    label: Text(
                      widget.isSaved?.call(note) == true ? '已收藏' : '收藏这张纸条',
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _draw,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('再抽一张纸条'),
            ),
          ],
        ),
      ),
    );
  }
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
        style: TextStyle(
          fontSize: large ? 24 : 13,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF2B2924),
        ),
      ),
    ),
  );
}
