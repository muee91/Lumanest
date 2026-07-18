import 'package:flutter/services.dart';

enum LumaNestSound { click, changeCard, ding, paper, completion }

enum LumaNestHaptic { selection, lightImpact, mediumImpact, success, warning }

class LumaNestFeedbackService {
  LumaNestFeedbackService._();

  static final instance = LumaNestFeedbackService._();
  static const _channel = MethodChannel('com.lumanest/feedback');

  bool _soundEnabled = true;
  bool _hapticEnabled = true;
  bool _completionEnabled = true;

  Future<void> preload() => _invoke('preload', {
    'sounds': LumaNestSound.values.map(_soundName).toList(growable: false),
  });

  Future<void> setEnabled({
    required bool soundEnabled,
    required bool hapticEnabled,
    required bool completionEnabled,
  }) async {
    _soundEnabled = soundEnabled;
    _hapticEnabled = hapticEnabled;
    _completionEnabled = completionEnabled;
    await _invoke('setEnabled', {
      'soundEnabled': soundEnabled,
      'hapticEnabled': hapticEnabled,
      'completionEnabled': completionEnabled,
    });
  }

  Future<void> play(
    LumaNestSound sound, {
    required double volume,
    LumaNestHaptic? haptic,
  }) async {
    if (sound == LumaNestSound.completion && !_completionEnabled) return;
    if (_soundEnabled) {
      await _invoke('play', {'sound': _soundName(sound), 'volume': volume});
    }
    if (_hapticEnabled && haptic != null) await _haptic(haptic);
  }

  Future<void> stop(LumaNestSound sound) =>
      _invoke('stop', {'sound': _soundName(sound)});

  Future<void> dispose() => _invoke('dispose');

  Future<void> _haptic(LumaNestHaptic haptic) async {
    switch (haptic) {
      case LumaNestHaptic.selection:
        await HapticFeedback.selectionClick();
      case LumaNestHaptic.lightImpact:
        await HapticFeedback.lightImpact();
      case LumaNestHaptic.mediumImpact:
        await HapticFeedback.mediumImpact();
      case LumaNestHaptic.success:
        await _invoke('haptic', {'type': 'success'});
      case LumaNestHaptic.warning:
        await _invoke('haptic', {'type': 'warning'});
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Widget tests and unsupported platforms still retain system haptics.
    } on PlatformException {
      // Feedback must never block the primary action.
    }
  }

  static String _soundName(LumaNestSound sound) => switch (sound) {
    LumaNestSound.click => 'click.wav',
    LumaNestSound.changeCard => 'change_card.wav',
    LumaNestSound.ding => 'ding.wav',
    LumaNestSound.paper => 'paper.wav',
    LumaNestSound.completion => 'sec.mp3',
  };
}
