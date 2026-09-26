import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/main.dart';

void main() {
  testWidgets('Nautilus app title and login branding render', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RodPlayerApp(preferences: prefs, credentialStore: MemoryCredentialStore()));
    await tester.pump();
    expect(find.text('Nautilus'), findsOneWidget);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'Nautilus');
    expect(find.text('RodPlayer'), findsNothing);
  });
}
