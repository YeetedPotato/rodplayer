import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';
import 'package:rodplayer/main.dart';
import 'package:rodplayer/ui/screens/login_screen.dart';
import 'package:rodplayer/ui/shell/rodplayer_app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('switch profile keeps server URL and full logout clears it despite server logout failure', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{CredentialMigration.serverUrlKey: 'https://server', CredentialMigration.userIdKey: 'user'});
    final prefs = await SharedPreferences.getInstance();
    final store = MemoryCredentialStore();
    await store.writeToken(CredentialMigration.tokenKey, 'token');
    final clients = <_RootClient>[];
    await tester.pumpWidget(RodPlayerApp(
      preferences: prefs,
      credentialStore: store,
      clientFactory: (url, identity) {
        final client = _RootClient(baseUrl: url, identity: identity, failLogout: clients.isEmpty);
        clients.add(client);
        return client;
      },
    ));
    await tester.pumpAndSettle();
    expect(find.byType(RodPlayerAppShell), findsOneWidget);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(OutlinedButton, 'Switch profile'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Switch profile'));
    await tester.pumpAndSettle();
    expect(clients.first.logoutCalls, 1);
    expect(clients.first.closed, isTrue);
    expect(await store.readToken(CredentialMigration.tokenKey), isNull);
    expect(prefs.getString(CredentialMigration.serverUrlKey), 'https://server');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'https://server'), findsOneWidget);

    clients.last.accessToken = 'token2';
    clients.last.userId = 'user2';
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'user2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    expect(prefs.getString(CredentialMigration.serverUrlKey), isNull);
    expect(await store.readToken(CredentialMigration.tokenKey), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}

class _RootClient extends JellyfinApiClient {
  _RootClient({required super.baseUrl, required super.identity, this.failLogout = false}) : super(client: http_testing.MockClient((_) async => http.Response('{}', 200)));

  final bool failLogout;
  bool closed = false;
  int logoutCalls = 0;

  @override
  Future<void> reportSessionEnded() async {
    logoutCalls++;
    if (failLogout) throw StateError('offline');
  }

  @override
  Future<JellyfinUserProfile> getCurrentUser() async => const JellyfinUserProfile(id: 'user', name: 'User');

  @override
  Future<void> authenticate({required String username, required String password}) async {
    accessToken ??= 'token';
    userId ??= 'user';
  }

  @override
  void close() => closed = true;
}
