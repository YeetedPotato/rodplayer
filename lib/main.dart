import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/network/private_network_session_controller.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/managed_private_transport_setup.dart';
import 'package:rodplayer/core/network/private_transport_profile_association.dart';
import 'package:rodplayer/core/network/private_transport_profile.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/platform/network/method_channel_private_network_runtime.dart';
import 'package:rodplayer/platform/playback/platform_playback_runtimes.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';
import 'package:rodplayer/ui/screens/login_screen.dart';
import 'package:rodplayer/ui/shell/rodplayer_app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (mediaKitPlaybackSupportedOn(platformFamilyForCurrentTarget())) {
    MediaKit.ensureInitialized();
  }
  final preferences = await SharedPreferences.getInstance();
  runApp(RodPlayerApp(
      preferences: preferences,
      credentialStore: const SecureCredentialStore()));
}

class RodPlayerApp extends StatelessWidget {
  const RodPlayerApp({
    required this.preferences,
    required this.credentialStore,
    this.clientFactory = _defaultClientFactory,
    this.privateNetworkRuntimeFactory = _defaultPrivateNetworkRuntimeFactory,
    this.enrollmentClientFactory = _defaultEnrollmentClientFactory,
    super.key,
  });

  final SharedPreferences preferences;
  final CredentialStore credentialStore;
  final JellyfinClientFactory clientFactory;
  final PrivateNetworkRuntime Function() privateNetworkRuntimeFactory;
  final EnrollmentClientFactory enrollmentClientFactory;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RodPlayer',
        theme: rodPlayerThemeData(),
        home: RodPlayerShell(
          preferences: preferences,
          credentialStore: credentialStore,
          clientFactory: clientFactory,
          privateNetworkRuntimeFactory: privateNetworkRuntimeFactory,
          enrollmentClientFactory: enrollmentClientFactory,
        ),
      );
}

class RodPlayerShell extends StatefulWidget {
  const RodPlayerShell({
    required this.preferences,
    required this.credentialStore,
    this.clientFactory = _defaultClientFactory,
    this.privateNetworkRuntimeFactory = _defaultPrivateNetworkRuntimeFactory,
    this.enrollmentClientFactory = _defaultEnrollmentClientFactory,
    super.key,
  });

  final SharedPreferences preferences;
  final CredentialStore credentialStore;
  final JellyfinClientFactory clientFactory;
  final PrivateNetworkRuntime Function() privateNetworkRuntimeFactory;
  final EnrollmentClientFactory enrollmentClientFactory;

  @override
  State<RodPlayerShell> createState() => _RodPlayerShellState();
}

class _RodPlayerShellState extends State<RodPlayerShell> {
  JellyfinApiClient? _client;
  InstallationIdentity? _identity;
  bool _loading = true;
  PrivateNetworkSessionController? _privateNetwork;
  PrivateTransportProfile? _privateNetworkProfile;
  final ValueNotifier<PrivateNetworkStatus?> _unavailablePrivateStatus =
      ValueNotifier(null);
  late final PrivateTransportProfileAssociation _privateTransport;
  late final PrivateTransportProfileStore _profiles;

  @override
  void initState() {
    super.initState();
    _privateTransport = PrivateTransportProfileAssociation(widget.preferences);
    _profiles = PrivateTransportProfileStore(widget.preferences);
    _restore();
  }

  @override
  void dispose() {
    final network = _privateNetwork;
    if (network != null) unawaited(network.close());
    _unavailablePrivateStatus.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final migration = CredentialMigration(
        preferences: widget.preferences,
        credentialStore: widget.credentialStore);
    await migration.migrate();
    final identity =
        await SharedPreferencesInstallationIdentityStore(widget.preferences)
            .load();
    final url = widget.preferences.getString(CredentialMigration.serverUrlKey);
    final token =
        await widget.credentialStore.readToken(CredentialMigration.tokenKey);
    final user = widget.preferences.getString(CredentialMigration.userIdKey);
    JellyfinApiClient? client;
    if (url != null &&
        token != null &&
        user != null &&
        url.isNotEmpty &&
        token.isNotEmpty &&
        user.isNotEmpty) {
      client = _makeClient(url, identity)
        ..accessToken = token
        ..userId = user;
    }
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _client = client;
      _loading = false;
    });
  }

  Future<void> _authenticated(String url, JellyfinApiClient client) async {
    final previousUrl =
        widget.preferences.getString(CredentialMigration.serverUrlKey);
    await widget.preferences.setString(CredentialMigration.serverUrlKey, url);
    if (previousUrl != url) {
      await _privateTransport.clear();
    }
    await widget.credentialStore
        .writeToken(CredentialMigration.tokenKey, client.accessToken!);
    await widget.preferences
        .setString(CredentialMigration.userIdKey, client.userId!);
    if (mounted) setState(() => _client = client);
  }

  Future<void> _configurePrivateAccess(
      String canonicalUrl, String invitationText, String setupCode) async {
    await ManagedPrivateTransportSetup(
      preferences: widget.preferences,
      runtimeFactory: widget.privateNetworkRuntimeFactory,
      enrollmentClientFactory: widget.enrollmentClientFactory,
    ).configure(
      canonicalServerUrl: canonicalUrl,
      invitationText: invitationText,
      setupCode: setupCode,
    );
    final previous = _privateNetwork;
    _privateNetwork = null;
    _privateNetworkProfile = null;
    if (previous != null) await previous.close();
  }

  JellyfinApiClient _makeClient(String url, InstallationIdentity identity) {
    final client = widget.clientFactory(url, identity);
    final association = _privateTransport.lookupFor(url);
    PrivateTransportProfile? profile;
    try {
      if (association.kind == PrivateTransportAssociationKind.associated) {
        profile = _profiles.find(association.profileId!);
      }
    } on FormatException {
      // A malformed profile store must never turn private traffic public.
    }
    if (profile != null) {
      final claim = PrivateNetworkIdentityClaim(
        profileId: profile.id,
        controlUrl: profile.controlUrl,
        homeIpv4: profile.serviceIpv4,
        homePort: profile.servicePort,
        allowLegacyClaim: _profiles.uniquelyMatches(profile),
      );
      if (_privateNetworkProfile?.id != profile.id ||
          _privateNetworkProfile?.controlUrl != profile.controlUrl ||
          _privateNetworkProfile?.serviceIpv4 != profile.serviceIpv4 ||
          _privateNetworkProfile?.servicePort != profile.servicePort) {
        final previous = _privateNetwork;
        if (previous != null) unawaited(previous.close());
        _privateNetwork = PrivateNetworkSessionController(
            widget.privateNetworkRuntimeFactory(), claim);
        _privateNetworkProfile = profile;
      }
      final network = _privateNetwork!;
      unawaited(network.start());
      client.usePrivateTransport(network.status,
          waitUntilReady: network.waitUntilReady);
    } else if (association.kind != PrivateTransportAssociationKind.none) {
      client.usePrivateTransport(_unavailablePrivateStatus);
    }
    return client;
  }

  Future<void> _logout() async {
    await _clearSession(keepServerUrl: false);
  }

  Future<void> _switchProfile() async {
    await _clearSession(keepServerUrl: true);
  }

  Future<void> _clearSession({required bool keepServerUrl}) async {
    final client = _client;
    if (client != null) {
      try {
        await client.reportSessionEnded();
      } catch (_) {}
    }
    if (!keepServerUrl) {
      await widget.preferences.remove(CredentialMigration.serverUrlKey);
      await _privateTransport.clear();
    }
    await widget.credentialStore.deleteToken(CredentialMigration.tokenKey);
    await widget.preferences.remove(CredentialMigration.userIdKey);
    client?.close();
    if (mounted) setState(() => _client = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_client == null) {
      return LoginScreen(
          identity: _identity!,
          initialServerUrl:
              widget.preferences.getString(CredentialMigration.serverUrlKey),
          clientFactory: _makeClient,
          onConfigurePrivateAccess: _configurePrivateAccess,
          onAuthenticated: _authenticated);
    }
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context)
      },
      child: RodPlayerAppShell(
          client: _client!, onLogout: _logout, onSwitchProfile: _switchProfile),
    );
  }
}

Widget playerRoute(MediaKitPlaybackEngine engine, JellyfinApiClient client,
        String itemId) =>
    VideoPlayerView(
        engine: engine,
        surface: MediaKitPlaybackVideoSurface(engine),
        client: client,
        itemId: itemId);

JellyfinApiClient _defaultClientFactory(
        String baseUrl, InstallationIdentity identity) =>
    JellyfinApiClient(baseUrl: baseUrl, identity: identity);

PrivateNetworkRuntime _defaultPrivateNetworkRuntimeFactory() =>
    MethodChannelPrivateNetworkRuntime();

FamilyEnrollmentClient _defaultEnrollmentClientFactory(Uri endpoint) =>
    FamilyEnrollmentClient(endpoint: endpoint);
