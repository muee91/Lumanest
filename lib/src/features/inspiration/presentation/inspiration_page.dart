import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
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
            availableEquipment: EquipmentCapabilityParser.parse(
              preferences.equipmentList,
            ),
          ),
          snapshotId: snapshot.id,
          reduceMotion: reduceMotion,
          enableShake:
              preferences.ambientMotionMode == AmbientMotionMode.full &&
              !preferences.highContrast &&
              !conserveDeviceEnergy,
          allowHaptics: !reduceMotion && !conserveDeviceEnergy,
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
    required this.allowHaptics,
    required this.onExplore,
    required this.onAction,
    this.onSave,
    this.isSaved,
  });
  final List<InspirationNote> notes;
  final String snapshotId;
  final bool reduceMotion;
  final bool enableShake;
  final bool allowHaptics;
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
  var _detailsExpanded = false;

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
    if (widget.allowHaptics) HapticFeedback.selectionClick();
    setState(() {
      if (_hasDrawn) {
        _selectedIndex = (_selectedIndex + 1) % widget.notes.length;
      }
      _hasDrawn = true;
      _detailsExpanded = false;
    });
  }

  void _select(InspirationNote note) {
    final index = widget.notes.indexWhere((item) => item.id == note.id);
    if (index < 0) return;
    if (widget.allowHaptics) HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
      _hasDrawn = true;
      _detailsExpanded = false;
    });
  }

  void _toggleDetails() {
    setState(() => _detailsExpanded = !_detailsExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    // The builder always adds local composition prompts. Keep this defensive
    // recovery in case a future change deliberately suppresses all prompts.
    if (notes.isEmpty) return _emptyBottleScaffold(context);
    final index = _selectedIndex % notes.length;
    final note = notes[index];
    final saved = widget.isSaved?.call(note) == true;
    return Scaffold(
      appBar: AppBar(title: const Text('灵感')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            children: <Widget>[
              Expanded(
                child: AnimatedSwitcher(
                  duration: Duration(
                    milliseconds: widget.reduceMotion ? 0 : 320,
                  ),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: .94,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _hasDrawn
                      ? _NoteHero(
                          key: ValueKey(note.id),
                          note: note,
                          onTap: _toggleDetails,
                        )
                      : InspirationBottle(
                          key: const ValueKey('inspiration-bottle-stage'),
                          snapshotId: widget.snapshotId,
                          notes: notes,
                          selectedId: note.id,
                          reduceMotion: widget.reduceMotion,
                          enableShake: widget.enableShake,
                          onDraw: _draw,
                          onSelect: _select,
                        ),
                ),
              ),
              if (_hasDrawn)
                _DetailPanel(
                  note: note,
                  expanded: _detailsExpanded,
                  reduceMotion: widget.reduceMotion,
                  onToggle: _toggleDetails,
                  isSaved: saved,
                  onAction: () => widget.onAction(note),
                  onSave: widget.onSave == null || saved
                      ? null
                      : () async {
                          await widget.onSave!(note);
                          if (mounted) setState(() {});
                        },
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
      ),
    );
  }

  /// Quiet empty state. It never fabricates weather or safety facts; it only
  /// offers the single forward action that already exists for this page.
  Widget _emptyBottleScaffold(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('灵感')),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('暂时没有纸条', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextButton(onPressed: widget.onExplore, child: const Text('去探索')),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The drawn note as the centered subject. Tapping it toggles the on-demand
/// detail panel; the long detail and action buttons are never dumped here.
class _NoteHero extends StatelessWidget {
  const _NoteHero({super.key, required this.note, required this.onTap});

  final InspirationNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Semantics(
        button: true,
        label:
            '${note.displayLabel}，'
            '${note.isFactual ? '已成立机会' : '创作方向'}，'
            '双击查看详情',
        child: GestureDetector(
          onTap: onTap,
          child: _Paper(
            key: Key('selected-inspiration-${note.id}'),
            text: note.displayLabel,
            large: true,
          ),
        ),
      ),
    ),
  );
}

/// Bottom, on-demand detail expansion. The peek row only states which kind of
/// note this is; the detail text, action and save affordances stay collapsed
/// until the user asks for them.
class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.note,
    required this.expanded,
    required this.reduceMotion,
    required this.onToggle,
    required this.isSaved,
    required this.onAction,
    this.onSave,
  });

  final InspirationNote note;
  final bool expanded;
  final bool reduceMotion;
  final VoidCallback onToggle;
  final bool isSaved;
  final VoidCallback onAction;
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  note.isFactual
                      ? Icons.verified_outlined
                      : Icons.brush_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  note.isFactual ? '已成立机会' : '创作方向',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  expanded ? '收起' : '详情',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(note.detail, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.arrow_outward),
                        label: Text(note.isFactual ? '查看机会' : '去探索'),
                      ),
                    ),
                    if (onSave != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: onSave,
                        icon: const Icon(Icons.bookmark_border),
                        label: const Text('收藏纸条'),
                      ),
                    ] else if (isSaved)
                      TextButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.bookmark_added_outlined),
                        label: const Text('已收藏'),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Paper material with a warm gradient and a soft shadow. In dark mode the
/// surface is solid (not a muddy overlay) so the card lifts cleanly off the
/// dark background while dark ink stays legible.
class _Paper extends StatelessWidget {
  const _Paper({super.key, required this.text, this.large = false});
  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gradient = dark
        ? const <Color>[Color(0xFFF6ECDC), Color(0xFFEADFCB)]
        : const <Color>[Colors.white, Color(0xFFF3E9D9)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(large ? 10 : 6),
        border: Border.all(
          color: const Color(0xFF806C55).withValues(alpha: dark ? .45 : .26),
          width: dark ? 1.2 : 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .28 : .14),
            blurRadius: dark ? 18 : 8,
            offset: Offset(0, dark ? 8 : 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 30 : 12,
          vertical: large ? 22 : 9,
        ),
        child: Text(
          text,
          textAlign: large ? TextAlign.center : null,
          style: TextStyle(
            fontSize: large ? 26 : 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2B2924),
          ),
        ),
      ),
    );
  }
}
