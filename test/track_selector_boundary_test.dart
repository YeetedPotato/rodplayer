import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TrackSelectorSheet does not import media_kit Player directly', () {
    final source = File('lib/ui/player/track_selector_sheet.dart').readAsStringSync();
    final contract = File('lib/core/player/track_controller.dart').readAsStringSync();
    expect(source, isNot(contains("package:media_kit/media_kit.dart")));
    expect(
      source,
      contains("package:rodplayer/core/player/track_controller.dart"),
    );
    expect(source, contains('RodPlayerTrack'));
    expect(source, contains('PlaybackRuntimeViewBinding'));
    expect(contract, isNot(contains("package:media_kit/media_kit.dart")));
    expect(contract, isNot(contains('AudioTrack')));
    expect(contract, isNot(contains('SubtitleTrack')));
    expect(contract, isNot(contains('Object? raw')));
  });
}
