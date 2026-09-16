import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/profile_screen.dart';

import 'test_support.dart';

void main() {
  Widget app(Widget child, {double textScale = 1}) => MaterialApp(
        theme: rodPlayerThemeData(),
        home: Builder(builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child)),
      );

  testWidgets('profile loading error retry and display work', (tester) async {
    final client = _ProfileClient(failProfileOnce: true);
    await tester.pumpWidget(app(ProfileScreen(client: client, onSwitchProfile: () async {}, onLogout: () async {})));
    await tester.pumpAndSettle();

    expect(find.text('Could not load profile'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Erick'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('https://server/jellyfin'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
  });

  testWidgets('preference save preserves raw fields prevents duplicates and keeps failed edits', (tester) async {
    final client = _ProfileClient(failSaveOnce: true);
    await tester.pumpWidget(app(ProfileScreen(client: client, onSwitchProfile: () async {}, onLogout: () async {})));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Preferred audio language'), 'spa');
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Save preferences'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(FilledButton, 'Save preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save preferences.'), findsOneWidget);

    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Save preferences'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(FilledButton, 'Save preferences'));
    await tester.pumpAndSettle();
    expect(client.saved!.toUpdateJson()['GroupedFolders'], <String>['keep']);
    expect(client.saved!.audioLanguagePreference, 'spa');
    expect(find.text('Preferences saved'), findsOneWidget);
  });

  testWidgets('callbacks compact layout and stale client replacement are safe', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var switched = false;
    var loggedOut = false;
    final pending = _ProfileClient(pendingProfile: true);
    await tester.pumpWidget(app(ProfileScreen(client: pending, onSwitchProfile: () async => switched = true, onLogout: () async => loggedOut = true), textScale: 1.25));
    await tester.pump();
    await tester.pumpWidget(app(ProfileScreen(client: _ProfileClient(), onSwitchProfile: () async => switched = true, onLogout: () async => loggedOut = true), textScale: 1.25));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Erick'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(OutlinedButton, 'Switch profile'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Switch profile'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
    expect(switched, isTrue);
    expect(loggedOut, isTrue);
  });
  testWidgets('client replacement clears stale in-flight save state', (tester) async {
    final pendingSave = Completer<void>();
    final first = _ProfileClient(pendingSave: pendingSave);
    final second = _ProfileClient();

    await tester.pumpWidget(app(ProfileScreen(
      client: first,
      onSwitchProfile: () async {},
      onLogout: () async {},
    )));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save preferences'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save preferences'));
    await tester.pump();

    await tester.pumpWidget(app(ProfileScreen(
      client: second,
      onSwitchProfile: () async {},
      onLogout: () async {},
    )));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save preferences'),
    );
    expect(saveButton.onPressed, isNotNull);

    pendingSave.complete();
    await tester.pumpAndSettle();
  });
}

class _ProfileClient extends JellyfinApiClient {
  _ProfileClient({
    this.failProfileOnce = false,
    this.failSaveOnce = false,
    this.pendingProfile = false,
    this.pendingSave,
  })
      : super(baseUrl: 'https://server/jellyfin', identity: testIdentity, client: http_testing.MockClient((_) async => http.Response('{}', 200)));

  bool failProfileOnce;
  bool failSaveOnce;
  final bool pendingProfile;
  final Completer<void>? pendingSave;
  JellyfinUserConfiguration? saved;

  @override
  Future<JellyfinUserProfile> getCurrentUser() async {
    if (pendingProfile) return Completer<JellyfinUserProfile>().future;
    if (failProfileOnce) {
      failProfileOnce = false;
      throw StateError('profile');
    }
    return JellyfinUserProfile.fromJson(<String, dynamic>{
      'Id': 'user',
      'Name': 'Erick',
      'ServerName': 'Media',
      'Configuration': <String, dynamic>{
        'AudioLanguagePreference': 'eng',
        'SubtitleLanguagePreference': 'eng',
        'SubtitleMode': 'Smart',
        'GroupedFolders': <String>['keep'],
      },
      'Policy': <String, dynamic>{'IsAdministrator': true},
    });
  }

  @override
  Future<void> updateCurrentUserConfiguration(JellyfinUserConfiguration configuration) async {
    if (failSaveOnce) {
      failSaveOnce = false;
      throw StateError('save');
    }
    saved = configuration;
    final pending = pendingSave;
    if (pending != null) await pending.future;
  }
}
