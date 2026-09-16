import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/login_screen.dart';

import 'test_support.dart';

void main() {
  Widget app(Widget child, {double textScale = 1}) => MaterialApp(
        theme: rodPlayerThemeData(),
        home: Builder(builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child)),
      );

  testWidgets('initial server loads public profiles and profile selection fills username', (tester) async {
    final clients = <_LoginClient>[];
    await tester.pumpWidget(app(LoginScreen(
      identity: testIdentity,
      initialServerUrl: 'https://server/jellyfin',
      clientFactory: (url, identity) {
        final client = _LoginClient(publicUsers: <JellyfinUserProfile>[const JellyfinUserProfile(id: 'u', name: 'Alice')]);
        clients.add(client);
        return client;
      },
      onAuthenticated: (_, __) async {},
    )));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'https://server/jellyfin'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Alice'), findsOneWidget);
    expect(clients.single.closed, isTrue);
  });

  testWidgets('empty password auth is allowed and malformed input is rejected', (tester) async {
    JellyfinApiClient? authed;
    await tester.pumpWidget(app(LoginScreen(
      identity: testIdentity,
      clientFactory: (_, __) => _LoginClient(),
      onAuthenticated: (_, client) async => authed = client,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid server URL and username.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Server URL'), 'server');
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'passwordless');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(authed, isNotNull);
    expect((authed as _LoginClient).passwords, <String>['']);
  });

  testWidgets('profile discovery failure does not block manual login and compact layout is stable', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    JellyfinApiClient? authed;
    var created = 0;
    await tester.pumpWidget(app(LoginScreen(
      identity: testIdentity,
      initialServerUrl: 'https://server',
      clientFactory: (_, __) => _LoginClient(failPublic: created++ == 0),
      onAuthenticated: (_, client) async => authed = client,
    ), textScale: 1.25));
    await tester.pumpAndSettle();
    expect(find.text('Could not load public profiles.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'manual');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(authed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

class _LoginClient extends JellyfinApiClient {
  _LoginClient({this.publicUsers = const <JellyfinUserProfile>[], this.failPublic = false})
      : super(baseUrl: 'https://server', identity: testIdentity, client: http_testing.MockClient((_) async => http.Response('{}', 200)));

  final List<JellyfinUserProfile> publicUsers;
  final bool failPublic;
  bool closed = false;
  final passwords = <String>[];

  @override
  Future<List<JellyfinUserProfile>> getPublicUsers() async {
    if (failPublic) throw StateError('public');
    return publicUsers;
  }

  @override
  Future<void> authenticate({required String username, required String password}) async {
    passwords.add(password);
    accessToken = 'token';
    userId = 'user';
  }

  @override
  void close() => closed = true;
}
