import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/player_chrome_controller.dart';

void main() {
  group('PlayerChromeController', () {
    test('hides after playback inactivity and activity reveals chrome', () {
      fakeAsync((async) {
        final controller = PlayerChromeController(
          hideAfter: const Duration(seconds: 3),
        );
        controller.playbackStateChanged(playing: true, buffering: false);
        async.elapse(const Duration(seconds: 3));
        expect(controller.visible, isFalse);
        controller.activity(mode: PlayerInputMode.keyboard);
        expect(controller.visible, isTrue);
        expect(controller.inputMode, PlayerInputMode.keyboard);
        controller.dispose();
      });
    });

    test('updated hide interval reschedules the active timer', () {
      fakeAsync((async) {
        final controller = PlayerChromeController();
        controller.playbackStateChanged(playing: true, buffering: false);
        async.elapse(const Duration(seconds: 2));
        controller.configureHideAfter(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 3));
        expect(controller.visible, isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(controller.visible, isFalse);
        controller.dispose();
      });
    });

    test('modal and scrubbing holds cancel hiding until all holds release', () {
      fakeAsync((async) {
        final controller = PlayerChromeController();
        controller.playbackStateChanged(playing: true, buffering: false);
        controller.hold(PlayerChromeHold.modal);
        controller.hold(PlayerChromeHold.scrubbing);
        async.elapse(const Duration(seconds: 10));
        expect(controller.visible, isTrue);
        controller.release(PlayerChromeHold.modal);
        async.elapse(const Duration(seconds: 4));
        expect(controller.visible, isTrue);
        controller.release(PlayerChromeHold.scrubbing);
        async.elapse(const Duration(seconds: 3));
        expect(controller.visible, isFalse);
        controller.dispose();
      });
    });

    test('paused and buffering states keep chrome visible', () {
      final controller = PlayerChromeController();
      controller.playbackStateChanged(playing: true, buffering: false);
      controller.hide();
      expect(controller.visible, isFalse);
      controller.playbackStateChanged(playing: false, buffering: false);
      expect(controller.visible, isTrue);
      controller.hide();
      controller.playbackStateChanged(playing: true, buffering: true);
      expect(controller.visible, isTrue);
      controller.dispose();
    });

    test('transient feedback is bounded and expires', () {
      fakeAsync((async) {
        final controller = PlayerChromeController();
        controller.showFeedback('Seeking');
        expect(controller.transientFeedback, 'Seeking');
        async.elapse(const Duration(seconds: 1));
        expect(controller.transientFeedback, isNull);
        controller.dispose();
      });
    });
  });
}
