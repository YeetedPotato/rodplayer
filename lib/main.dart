import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';
import 'package:rodplayer/ui/screens/browse_screen.dart';
import 'package:rodplayer/ui/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(RodPlayerApp(preferences: preferences, credentialStore: const SecureCredentialStore()));
}

class RodPlayerApp extends StatelessWidget {
  const RodPlayerApp({required this.preferences, required this.credentialStore, super.key});

  final SharedPreferences preferences;
  final CredentialStore credentialStore;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RodPlayer',
        theme: rodPlayerThemeData(),
        home: RodPlayerShell(preferences: preferences, credentialStore: credentialStore),
      );
}

class RodPlayerShell extends StatefulWidget {
  const RodPlayerShell({required this.preferences, required this.credentialStore, super.key});

  final SharedPreferences preferences;
  final CredentialStore credentialStore;

  @override
  State<RodPlayerShell> createState() => _RodPlayerShellState();
}

class _RodPlayerShellState extends State<RodPlayerShell> {
  JellyfinApiClient? _client;
  InstallationIdentity? _identity;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
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
      client = JellyfinApiClient(baseUrl: url, identity: identity)
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
    await widget.preferences.setString(CredentialMigration.serverUrlKey, url);
    await widget.credentialStore.writeToken(CredentialMigration.tokenKey, client.accessToken!);
    await widget.preferences.setString(CredentialMigration.userIdKey, client.userId!);
    if (mounted) setState(() => _client = client);
  }

  Future<void> _logout() async {
    await widget.preferences.remove(CredentialMigration.serverUrlKey);
    await widget.credentialStore.deleteToken(CredentialMigration.tokenKey);
    await widget.preferences.remove(CredentialMigration.userIdKey);
    _client?.close();
    if (mounted) setState(() => _client = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_client == null) return LoginScreen(identity: _identity!, onAuthenticated: _authenticated);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context)},
      child: BrowseScreen(client: _client!, onLogout: _logout),
    );
  }
}

Widget playerRoute(MediaKitPlaybackEngine engine, JellyfinApiClient client, String itemId) => VideoPlayerView(engine: engine, surface: MediaKitPlaybackVideoSurface(engine), client: client, itemId: itemId);
