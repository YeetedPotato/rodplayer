import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/player_controller.dart';

void main() {
  group('MediaKitPlaybackEngine static configuration', () {
    test('exposes the resilience-focused mpv properties', () {
      // TODO(phase-2): make these PlaybackEnvironment/backend/output-dependent.
      expect(MediaKitPlaybackEngine.mpvProperties['cache'], 'yes');
      expect(MediaKitPlaybackEngine.mpvProperties['network-timeout'], '15');
      expect(MediaKitPlaybackEngine.mpvProperties['demuxer-max-bytes'], '512MiB');
      expect(MediaKitPlaybackEngine.mpvProperties['demuxer-max-back-bytes'], '256MiB');
    });

    test('keeps current passthrough and libass subtitle settings documented', () {
      // TODO(phase-2): make passthrough/subtitle behavior depend on environment capabilities.
      expect(MediaKitPlaybackEngine.mpvProperties['audio-spdif'], 'ac3,eac3,dts,dts-hd,truehd');
      expect(MediaKitPlaybackEngine.mpvProperties['audio-passthrough'], 'yes');
      expect(MediaKitPlaybackEngine.mpvProperties['audio-fallback-to-null'], 'no');
      expect(MediaKitPlaybackEngine.mpvProperties['sub-auto'], 'fuzzy');
      expect(MediaKitPlaybackEngine.mpvProperties['sub-ass'], 'yes');
      expect(MediaKitPlaybackEngine.mpvProperties['sub-forced'], 'yes');
    });

    test('provides platform-safe effective mpv properties', () {
      expect(MediaKitPlaybackEngine.effectiveMpvProperties['audio-device'], anyOf(isNull, 'auto'));
      expect(MediaKitPlaybackEngine.effectiveMpvProperties['sub-auto'], 'fuzzy');
    });
  });
}
