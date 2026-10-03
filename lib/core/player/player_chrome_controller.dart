import 'dart:async';

import 'package:flutter/foundation.dart';

enum PlayerInputMode { pointer, keyboard, dpad, touch }

enum PlayerChromeHold { modal, menu, scrubbing, interaction }

/// Nonvisual owner of OSD visibility, temporary holds, and input mode.
/// Widgets can render [visible] but do not own the timeout or hold policy.
final class PlayerChromeController extends ChangeNotifier {
  PlayerChromeController({Duration hideAfter = const Duration(seconds: 3)})
      : _hideAfter = hideAfter;

  Duration _hideAfter;
  Duration get hideAfter => _hideAfter;
  final Set<PlayerChromeHold> _holds = <PlayerChromeHold>{};
  Timer? _timer;
  bool _visible = true;
  bool _playing = false;
  bool _buffering = false;
  bool _disposed = false;
  PlayerInputMode _inputMode = PlayerInputMode.pointer;
  String? _transientFeedback;
  Timer? _feedbackTimer;

  bool get visible => _visible;
  bool get isHeld => _holds.isNotEmpty;
  PlayerInputMode get inputMode => _inputMode;
  String? get transientFeedback => _transientFeedback;

  void setInputMode(PlayerInputMode value) {
    if (_disposed || _inputMode == value) return;
    _inputMode = value;
    notifyListeners();
  }

  void playbackStateChanged({required bool playing, required bool buffering}) {
    if (_disposed) return;
    _playing = playing;
    _buffering = buffering;
    if (!playing || buffering) {
      _cancelHide();
      _setVisible(true);
    } else {
      _scheduleHide();
    }
  }

  void activity({PlayerInputMode? mode}) {
    if (_disposed) return;
    if (mode != null) _inputMode = mode;
    _setVisible(true);
    _scheduleHide();
  }

  void configureHideAfter(Duration value) {
    if (_disposed || value == _hideAfter) return;
    _hideAfter = value;
    _scheduleHide();
  }

  void setHeld(PlayerChromeHold value, bool held) {
    if (_disposed) return;
    if (held) {
      hold(value);
    } else {
      release(value);
    }
  }

  void hold(PlayerChromeHold value) {
    if (_disposed) return;
    _holds.add(value);
    _cancelHide();
    _setVisible(true);
  }

  void release(PlayerChromeHold value) {
    if (_disposed) return;
    _holds.remove(value);
    _scheduleHide();
  }

  void hide() {
    if (_disposed || !_playing || _buffering || isHeld) return;
    _cancelHide();
    _setVisible(false);
  }

  void showFeedback(
    String value, {
    Duration duration = const Duration(seconds: 1),
  }) {
    if (_disposed) return;
    _feedbackTimer?.cancel();
    _transientFeedback = value;
    notifyListeners();
    _feedbackTimer = Timer(duration, () {
      _transientFeedback = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _scheduleHide() {
    _cancelHide();
    if (_disposed || !_playing || _buffering || isHeld) return;
    _timer = Timer(hideAfter, hide);
  }

  void _cancelHide() {
    _timer?.cancel();
    _timer = null;
  }

  void _setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelHide();
    _feedbackTimer?.cancel();
    super.dispose();
  }
}
