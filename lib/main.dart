import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/remux_client.dart';
import 'core/player/player_controller.dart';
import 'core/theme/remux_theme.dart';
import 'ui/player/video_player_view.dart';
import 'ui/screens/browse_screen.dart';

const _serverUrlKey = 'remux_server_url';
const _serverTokenKey = 'remux_server_token';

String? _cleanToken(String? token) {
  final value = token?.trim();
  if (value == null || value.isEmpty) return null;
  return value.replaceFirst(RegExp(r'^Bearer\\s+', caseSensitive: false), '').trim();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(RodPlayerApp(preferences: preferences));
}

class RodPlayerApp extends StatelessWidget {
  const RodPlayerApp({required this.preferences, super.key});
  final SharedPreferences preferences;

  @override
  Widget build(BuildContext context) => MaterialApp(title: 'RodPlayer', theme: remuxThemeData(), home: RodPlayerShell(preferences: preferences));
}

class RodPlayerShell extends StatefulWidget {
  const RodPlayerShell({required this.preferences, super.key});
  final SharedPreferences preferences;
  @override
  State<RodPlayerShell> createState() => _RodPlayerShellState();
}

class _RodPlayerShellState extends State<RodPlayerShell> {
  RemuxClient? _client;
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadConfiguration(); }

  void _loadConfiguration() {
    final url = widget.preferences.getString(_serverUrlKey);
    final token = _cleanToken(widget.preferences.getString(_serverTokenKey));
    if (url != null && url.isNotEmpty) {
      _client = RemuxClient(baseUrl: url);
      _client!.accessToken = token;
    }
    setState(() => _loading = false);
  }

  void _connect(String url, String? token) {
    final client = RemuxClient(baseUrl: url);
    client.accessToken = _cleanToken(token);
    setState(() => _client = client);
  }

  void _handleRemoteBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  Widget _browseWithBackHandling() => PopScope<void>(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleRemoteBack();
        },
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): _handleRemoteBack,
            const SingleActivator(LogicalKeyboardKey.browserBack): _handleRemoteBack,
          },
          child: BrowseScreen(client: _client!),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_client == null) return ServerSetupPage(preferences: widget.preferences, onConnected: _connect);
    return _browseWithBackHandling();
  }
}

class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({required this.preferences, required this.onConnected, this.initialUrl, this.initialToken, super.key});
  final SharedPreferences preferences;
  final void Function(String url, String? token) onConnected;
  final String? initialUrl;
  final String? initialToken;
  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  bool _testing = false;
  bool _saving = false;
  String? _message;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
    _tokenController = TextEditingController(text: widget.initialToken ?? '');
  }
  @override
  void dispose() { _urlController.dispose(); _tokenController.dispose(); super.dispose(); }

  String? _normalizedUrl() {
    final value = _urlController.text.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<RemuxClient?> _test() async {
    final url = _normalizedUrl();
    if (url == null) { setState(() { _success = false; _message = 'Enter a valid http:// or https:// server URL.'; }); return null; }
    setState(() { _testing = true; _message = null; });
    final client = RemuxClient(baseUrl: url)..accessToken = _cleanToken(_tokenController.text);
    try {
      await client.search('');
      if (!mounted) return client;
      setState(() { _success = true; _message = 'Connection successful.'; });
      return client;
    } catch (error) {
      if (!mounted) return null;
      setState(() { _success = false; _message = 'Connection failed: $error'; });
      return null;
    } finally { client.close(); if (mounted) setState(() => _testing = false); }
  }

  Future<void> _save() async {
    final url = _normalizedUrl();
    if (url == null) { setState(() { _success = false; _message = 'Enter a valid http:// or https:// server URL.'; }); return; }
    final token = _cleanToken(_tokenController.text);
    setState(() => _saving = true);
    await widget.preferences.setString(_serverUrlKey, url);
    await widget.preferences.setString(_serverTokenKey, token ?? '');
    if (!mounted) return;
    widget.onConnected(url, token);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Remux Server Setup')),
        body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
          const Icon(Icons.dns_outlined, size: 64),
          const SizedBox(height: 16),
          Text('Connect to your Remux server', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Enter a hosted server or a local network address to begin playback.'),
          const SizedBox(height: 24),
          TextField(controller: _urlController, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'Remux server URL', hintText: 'https://media.example.com or http://192.168.1.50:8096', prefixIcon: Icon(Icons.link), border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _tokenController, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'API key / token (optional)', hintText: 'For Jellyfin or Emby authentication', prefixIcon: Icon(Icons.key_outlined), border: OutlineInputBorder())),
          const SizedBox(height: 20),
          if (_message != null) Text(_message!, style: TextStyle(color: _success ? Colors.greenAccent : Colors.orangeAccent)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _testing || _saving ? null : _test, icon: _testing ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find), label: const Text('Test Connection')),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _testing || _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Save & Connect')),
        ]))),
      );
}

// VideoPlayerView is exported for integration screens and route wiring.
// ignore: unused_element
Widget playerRoute(RodPlayerEngine engine, RemuxClient client, String itemId) => VideoPlayerView(engine: engine, client: client, itemId: itemId);
