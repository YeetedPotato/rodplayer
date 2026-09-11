import 'package:flutter_test/flutter_test.dart';

import 'package:rodplayer/main.dart';

void main() {
  testWidgets('RodPlayer app renders', (tester) async {
    await tester.pumpWidget(const RodPlayerApp());
    expect(find.text('Configure a Remux server to begin playback.'), findsOneWidget);
  });
}
