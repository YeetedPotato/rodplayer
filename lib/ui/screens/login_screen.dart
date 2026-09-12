import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/ui/widgets/remux_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onAuthenticated, super.key});
  final Future<void> Function(String url, RemuxClient client) onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _normalize() {
    var value = _url.text.trim();
    if (!value.startsWith('http')) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme)) return null;
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<void> _login() async {
    final url = _normalize();
    if (url == null || _username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter a valid server URL, username, and password.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final client = RemuxClient(baseUrl: url);
    try {
      await client.authenticate(username: _username.text.trim(), password: _password.text);
      await widget.onAuthenticated(url, client);
    } on RemuxAuthException {
      setState(() => _error = 'Invalid username or password.');
      client.close();
    } on RemuxConnectionException catch (e) {
      setState(() => _error = 'Connection error: ${e.message}');
      client.close();
    } catch (_) {
      setState(() => _error = 'Unable to connect. Check the server URL and try again.');
      client.close();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Center(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                color: const Color(0xFF171717),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const RemuxLogo(size: 76, glow: true),
                      const SizedBox(height: 18),
                      const Text('Remux', style: TextStyle(color: Color(0xFFEBCF52), fontSize: 30, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 28),
                      TextField(controller: _url, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://media.example.com')),
                      const SizedBox(height: 14),
                      TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
                      const SizedBox(height: 14),
                      TextField(controller: _password, obscureText: true, onSubmitted: (_) => _login(), decoration: const InputDecoration(labelText: 'Password')),
                      if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))),
                      const SizedBox(height: 24),
                      SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _login, child: _busy ? const CircularProgressIndicator() : const Text('Sign in'))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
