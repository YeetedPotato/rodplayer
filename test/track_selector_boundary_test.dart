import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TrackSelectorSheet does not import media_kit Player directly', () {
    final source = File('lib/ui/player/track_selector_sheet.dart').readAsStringSync();
    expect(source, isNot(contains("package:media_kit/media_kit.dart")));
    expect(source, contains('TrackSelectionController'));
  });
}
