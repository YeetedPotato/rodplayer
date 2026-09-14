import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/main.dart';

void main() {
  testWidgets('RodPlayer app renders', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RodPlayerApp(preferences: prefs, credentialStore: MemoryCredentialStore()));
    await tester.pump();
    expect(find.text('RodPlayer'), findsOneWidget);
  });
}
