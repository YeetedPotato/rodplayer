import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';
import 'package:rodplayer/ui/widgets/rodplayer_logo.dart';

typedef JellyfinClientFactory = JellyfinApiClient Function(String baseUrl, InstallationIdentity identity);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.identity,
    required this.onAuthenticated,
    this.initialServerUrl,
    this.clientFactory = _defaultClientFactory,
    super.key,
  });

  final InstallationIdentity identity;
  final Future<void> Function(String url, JellyfinApiClient client) onAuthenticated;
  final String? initialServerUrl;
  final JellyfinClientFactory clientFactory;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

JellyfinApiClient _defaultClientFactory(String baseUrl, InstallationIdentity identity) => JellyfinApiClient(baseUrl: baseUrl, identity: identity);

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode(debugLabel: 'Password');
  bool _busy = false;
  bool _profilesLoading = false;
  String? _error;
  String? _profilesError;
  List<JellyfinUserProfile> _profiles = const <JellyfinUserProfile>[];
  int _profileGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialServerUrl;
    if (initial != null && initial.isNotEmpty) {
      _url.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfiles());
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String? _normalize() {
    var value = _url.text.trim();
    if (value.isEmpty) return null;
    if (!value.startsWith(RegExp(r'https?://'))) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme)) return null;
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<void> _loadProfiles() async {
    final url = _normalize();
    if (url == null) {
      setState(() => _profilesError = 'Enter a valid server URL to find profiles.');
      return;
    }
    final generation = ++_profileGeneration;
    setState(() {
      _profilesLoading = true;
      _profilesError = null;
    });
    final client = widget.clientFactory(url, widget.identity);
    try {
      final profiles = await client.getPublicUsers();
      if (!mounted || generation != _profileGeneration) return;
      setState(() => _profiles = profiles);
    } catch (_) {
      if (mounted && generation == _profileGeneration) setState(() => _profilesError = 'Could not load public profiles.');
    } finally {
      client.close();
      if (mounted && generation == _profileGeneration) setState(() => _profilesLoading = false);
    }
  }

  Future<void> _login() async {
    final url = _normalize();
    if (url == null || _username.text.trim().isEmpty) {
      setState(() => _error = 'Enter a valid server URL and username.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = widget.clientFactory(url, widget.identity);
    try {
      await client.authenticate(username: _username.text.trim(), password: _password.text);
      if (!mounted) {
        client.close();
        return;
      }
      await widget.onAuthenticated(url, client);
    } on JellyfinAuthException {
      if (mounted) setState(() => _error = 'Invalid username or password.');
      client.close();
    } on ServerConnectionException catch (error) {
      if (mounted) setState(() => _error = 'Connection error: ${error.message}');
      client.close();
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to connect. Check the server URL and try again.');
      client.close();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectProfile(JellyfinUserProfile profile) {
    _username.text = profile.name;
    _passwordFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const RodPlayerLogo(size: 76, glow: true),
                          const SizedBox(height: 18),
                          const Text('RodPlayer', style: TextStyle(color: Color(0xFFEBCF52), fontSize: 30, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 28),
                          TextField(controller: _url, autofocus: true, decoration: InputDecoration(labelText: 'Server URL', suffixIcon: IconButton(tooltip: 'Find profiles', onPressed: _profilesLoading ? null : _loadProfiles, icon: const Icon(Icons.people_outline)))),
                          const SizedBox(height: 12),
                          _ProfilePicker(profiles: _profiles, loading: _profilesLoading, error: _profilesError, onRetry: _loadProfiles, onSelected: _selectProfile),
                          const SizedBox(height: 14),
                          TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
                          const SizedBox(height: 14),
                          TextField(controller: _password, focusNode: _passwordFocus, obscureText: true, onSubmitted: (_) => _login(), decoration: const InputDecoration(labelText: 'Password (if required)')),
                          if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))),
                          const SizedBox(height: 24),
                          SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _login, child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'))),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({required this.profiles, required this.loading, required this.error, required this.onRetry, required this.onSelected});

  final List<JellyfinUserProfile> profiles;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<JellyfinUserProfile> onSelected;

  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator();
    if (error != null) {
      return Row(children: [
        Expanded(child: Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.orangeAccent))),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]);
    }
    if (profiles.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final profile in profiles)
            ActionChip(
              avatar: CircleAvatar(child: Text(profile.initials)),
              label: Text(profile.name.isEmpty ? 'Unnamed' : profile.name, overflow: TextOverflow.ellipsis),
              onPressed: () => onSelected(profile),
            ),
        ],
      ),
    );
  }
}
