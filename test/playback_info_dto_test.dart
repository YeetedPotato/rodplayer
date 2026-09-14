import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/playback_info_response.dart';

void main() {
  test('PlaybackInfo DTO preserves multiple streams, indexes, and raw metadata', () {
    final json = jsonDecode(File('test/fixtures/playback_info/direct_play_mkv.json').readAsStringSync()) as Map<String, dynamic>;
    final response = PlaybackInfoResponse.fromJson(json);
    final source = response.mediaSources.single;
    expect(response.playSessionId, 'play-direct');
    expect(source.videoStreams.single.index, 0);
    expect(source.audioStreams.single.audioSpatialFormat, 'Dolby Atmos');
    expect(source.subtitleStreams.single.index, 2);
    expect(source.raw['UnknownFutureField'], {'kept': true});
  });
}
