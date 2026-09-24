import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/network/private_network_session_controller.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_transport_profile_association.dart';
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
  runApp(RodPlayerApp(preferences: preferences, credentialStore: const SecureCredentialStore()));
}

class RodPlayerApp extends StatelessWidget {
  const RodPlayerApp({
    required this.preferences,
    required this.credentialStore,
    this.clientFactory = _defaultClientFactory,
    this.privateNetworkRuntimeFactory = _defaultPrivateNetworkRuntimeFactory,
    this.activePrivateTransportProfileId,
    super.key,
  });

  final SharedPreferences preferences;
  final CredentialStore credentialStore;
  final JellyfinClientFactory clientFactory;
  final PrivateNetworkRuntime Function() privateNetworkRuntimeFactory;
  final String? activePrivateTransportProfileId;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RodPlayer',
        theme: rodPlayerThemeData(),
        home: RodPlayerShell(
          preferences: preferences,
          credentialStore: credentialStore,
          clientFactory: clientFactory,
          privateNetworkRuntimeFactory: privateNetworkRuntimeFactory,
          activePrivateTransportProfileId: activePrivateTransportProfileId,
        ),
      );
}

class RodPlayerShell extends StatefulWidget {
  const RodPlayerShell({
    required this.preferences,
    required this.credentialStore,
    this.clientFactory = _defaultClientFactory,
    this.privateNetworkRuntimeFactory = _defaultPrivateNetworkRuntimeFactory,
    this.activePrivateTransportProfileId,
    super.key,
  });

  final SharedPreferences preferences;
  final CredentialStore credentialStore;
  final JellyfinClientFactory clientFactory;
  final PrivateNetworkRuntime Function() privateNetworkRuntimeFactory;
  final String? activePrivateTransportProfileId;

  @override
  State<RodPlayerShell> createState() => _RodPlayerShellState();
}

class _RodPlayerShellState extends State<RodPlayerShell> {
  JellyfinApiClient? _client;
  InstallationIdentity? _identity;
  bool _loading = true;
  PrivateNetworkSessionController? _privateNetwork;
  final ValueNotifier<PrivateNetworkStatus?> _unavailablePrivateStatus = ValueNotifier(null);
  late final PrivateTransportProfileAssociation _privateTransport;

  @override
  void initState() {
    super.initState();
    _privateTransport = PrivateTransportProfileAssociation(widget.preferences);
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
    final migration = CredentialMigration(preferences: widget.preferences, credentialStore: widget.credentialStore);
    await migration.migrate();
    final identity = await SharedPreferencesInstallationIdentityStore(widget.preferences).load();
    final url = widget.preferences.getString(CredentialMigration.serverUrlKey);
    final token = await widget.credentialStore.readToken(CredentialMigration.tokenKey);
    final user = widget.preferences.getString(CredentialMigration.userIdKey);
    JellyfinApiClient? client;
    if (url != null && token != null && user != null && url.isNotEmpty && token.isNotEmpty && user.isNotEmpty) {
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
    final previousUrl = widget.preferences.getString(CredentialMigration.serverUrlKey);
    await widget.preferences.setString(CredentialMigration.serverUrlKey, url);
    if (previousUrl != url) {
      await _privateTransport.clear();
    }
    await widget.credentialStore.writeToken(CredentialMigration.tokenKey, client.accessToken!);
    await widget.preferences.setString(CredentialMigration.userIdKey, client.userId!);
    if (mounted) setState(() => _client = client);
  }

  JellyfinApiClient _makeClient(String url, InstallationIdentity identity) {
    final client = widget.clientFactory(url, identity);
    final association = _privateTransport.lookupFor(url);
    if (association.kind == PrivateTransportAssociationKind.associated &&
        association.profileId == widget.activePrivateTransportProfileId) {
      final network = _privateNetwork ??= PrivateNetworkSessionController(widget.privateNetworkRuntimeFactory());
      unawaited(network.start());
      client.usePrivateTransport(network.status);
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
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_client == null) return LoginScreen(identity: _identity!, initialServerUrl: widget.preferences.getString(CredentialMigration.serverUrlKey), clientFactory: _makeClient, onAuthenticated: _authenticated);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context)},
      child: RodPlayerAppShell(client: _client!, onLogout: _logout, onSwitchProfile: _switchProfile),
    );
  }
}

Widget playerRoute(MediaKitPlaybackEngine engine, JellyfinApiClient client, String itemId) => VideoPlayerView(engine: engine, surface: MediaKitPlaybackVideoSurface(engine), client: client, itemId: itemId);

JellyfinApiClient _defaultClientFactory(String baseUrl, InstallationIdentity identity) => JellyfinApiClient(baseUrl: baseUrl, identity: identity);

PrivateNetworkRuntime _defaultPrivateNetworkRuntimeFactory() =>
    MethodChannelPrivateNetworkRuntime();
