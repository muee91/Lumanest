import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the root intelligence surface currently covers the shell.
///
/// This is presentation lifecycle state only. It prevents hidden shell effects
/// such as the Today ambient renderer from continuing to consume GPU while the
/// intelligence route is visible. It contains no location or conversation data.
class IntelligenceOverlayVisibilityController extends Notifier<bool> {
  @override
  bool build() => false;

  void show() {
    if (!state) state = true;
  }

  void hide() {
    if (state) state = false;
  }
}

final intelligenceOverlayVisibleProvider =
    NotifierProvider<IntelligenceOverlayVisibilityController, bool>(
      IntelligenceOverlayVisibilityController.new,
    );

/// Registers any root-level intelligence route with the application shell.
///
/// Keeping this wrapper outside [V2IntelligencePage] also covers compatibility
/// deep links and any future intelligent surface that uses the same route layer.
class IntelligenceOverlayLifecycle extends ConsumerStatefulWidget {
  const IntelligenceOverlayLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IntelligenceOverlayLifecycle> createState() =>
      _IntelligenceOverlayLifecycleState();
}

class _IntelligenceOverlayLifecycleState
    extends ConsumerState<IntelligenceOverlayLifecycle> {
  late final IntelligenceOverlayVisibilityController _visibilityController;

  @override
  void initState() {
    super.initState();
    _visibilityController = ref.read(
      intelligenceOverlayVisibleProvider.notifier,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _visibilityController.show();
    });
  }

  @override
  void dispose() {
    _visibilityController.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
