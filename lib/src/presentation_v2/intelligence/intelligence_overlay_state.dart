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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(intelligenceOverlayVisibleProvider.notifier).show();
    });
  }

  @override
  void dispose() {
    ref.read(intelligenceOverlayVisibleProvider.notifier).hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
