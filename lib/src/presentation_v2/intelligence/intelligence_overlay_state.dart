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
