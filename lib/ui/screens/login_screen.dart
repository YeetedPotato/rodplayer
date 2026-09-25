import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';
import 'package:rodplayer/ui/widgets/rodplayer_logo.dart';

typedef JellyfinClientFactory = JellyfinApiClient Function(
    String baseUrl, InstallationIdentity identity);
typedef PrivateAccessSetup = Future<void> Function(
    String canonicalServerUrl, String invitationText, String setupCode);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.identity,
    required this.onAuthenticated,
    this.initialServerUrl,
    this.clientFactory = _defaultClientFactory,
    this.onConfigurePrivateAccess,
    super.key,
  });

  final InstallationIdentity identity;
  final Future<void> Function(String url, JellyfinApiClient client)
      onAuthenticated;
  final String? initialServerUrl;
  final JellyfinClientFactory clientFactory;
  final PrivateAccessSetup? onConfigurePrivateAccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

JellyfinApiClient _defaultClientFactory(
        String baseUrl, InstallationIdentity identity) =>
    JellyfinApiClient(baseUrl: baseUrl, identity: identity);

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode(debugLabel: 'Password');
  bool _busy = false;
  bool _profilesLoading = false;
  String? _error;
  String? _profilesError;
  String? _profilesUrl;
  String? _setupMessage;
  List<JellyfinUserProfile> _profiles = const <JellyfinUserProfile>[];
  int _profileGeneration = 0;

  @override
  void initState() {
    super.initState();
    _url.addListener(_onUrlChanged);
    final initial = widget.initialServerUrl;
    if (initial != null && initial.isNotEmpty) {
      _url.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfiles());
    }
  }

  @override
  void dispose() {
    _url.removeListener(_onUrlChanged);
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
    if (uri == null ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme)) {
      return null;
    }
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  void _onUrlChanged() {
    final profilesUrl = _profilesUrl;
    if (profilesUrl == null || _normalize() == profilesUrl) return;
    _profileGeneration++;
    setState(() {
      _profiles = const <JellyfinUserProfile>[];
      _profilesUrl = null;
      _profilesError = null;
      _profilesLoading = false;
    });
  }

  Future<void> _loadProfiles() async {
    final url = _normalize();
    if (url == null) {
      setState(
          () => _profilesError = 'Enter a valid server URL to find profiles.');
      return;
    }
    final generation = ++_profileGeneration;
    setState(() {
      _profilesLoading = true;
      _profilesError = null;
      _profilesUrl = url;
    });
    final client = widget.clientFactory(url, widget.identity);
    try {
      final profiles = await client.getPublicUsers();
      if (!mounted || generation != _profileGeneration || _normalize() != url) {
        return;
      }
      setState(() => _profiles = profiles);
    } catch (_) {
      if (mounted && generation == _profileGeneration && _normalize() == url) {
        setState(() => _profilesError = 'Could not load public profiles.');
      }
    } finally {
      client.close();
      if (mounted && generation == _profileGeneration && _normalize() == url) {
        setState(() => _profilesLoading = false);
      }
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
      await client.authenticate(
          username: _username.text.trim(), password: _password.text);
      if (!mounted) {
        client.close();
        return;
      }
      await widget.onAuthenticated(url, client);
    } on JellyfinAuthException {
      if (mounted) setState(() => _error = 'Invalid username or password.');
      client.close();
    } on ServerConnectionException catch (error) {
      if (mounted) {
        setState(() => _error = 'Connection error: ${error.message}');
      }
      client.close();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Unable to connect. Check the server URL and try again.');
      }
      client.close();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectProfile(JellyfinUserProfile profile) {
    _username.text = profile.name;
    _passwordFocus.requestFocus();
  }

  Future<void> _setupPrivateAccess() async {
    final url = _normalize();
    final parsed = url == null ? null : Uri.tryParse(url);
    if (parsed == null ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      setState(() => _setupMessage = 'Enter a valid server URL first.');
      return;
    }
    final configured = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PrivateAccessDialog(
        canonicalServerUrl: url!,
        configure: widget.onConfigurePrivateAccess!,
      ),
    );
    if (!mounted || configured != true) return;
    setState(() {
      _setupMessage = 'Private access configured.';
      _profiles = const [];
    });
    await _loadProfiles();
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
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const RodPlayerLogo(size: 76, glow: true),
                          const SizedBox(height: 18),
                          const Text('RodPlayer',
                              style: TextStyle(
                                  color: Color(0xFFEBCF52),
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 28),
                          TextField(
                              controller: _url,
                              autofocus: true,
                              decoration: InputDecoration(
                                  labelText: 'Server URL',
                                  suffixIcon: IconButton(
                                      tooltip: 'Find profiles',
                                      onPressed: _profilesLoading
                                          ? null
                                          : _loadProfiles,
                                      icon: const Icon(Icons.people_outline)))),
                          if (widget.onConfigurePrivateAccess != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _busy ? null : _setupPrivateAccess,
                                icon: const Icon(Icons.lock_outline),
                                label: const Text('Set up private access'),
                              ),
                            ),
                          if (_setupMessage != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_setupMessage!,
                                  style: TextStyle(
                                      color: _setupMessage ==
                                              'Private access configured.'
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent)),
                            ),
                          const SizedBox(height: 12),
                          _ProfilePicker(
                              profiles: _profiles,
                              loading: _profilesLoading,
                              error: _profilesError,
                              onRetry: _loadProfiles,
                              onSelected: _selectProfile),
                          const SizedBox(height: 14),
                          TextField(
                              controller: _username,
                              decoration:
                                  const InputDecoration(labelText: 'Username')),
                          const SizedBox(height: 14),
                          TextField(
                              controller: _password,
                              focusNode: _passwordFocus,
                              obscureText: true,
                              onSubmitted: (_) => _login(),
                              decoration: const InputDecoration(
                                  labelText: 'Password (if required)')),
                          if (_error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(_error!,
                                    style: const TextStyle(
                                        color: Colors.orangeAccent))),
                          const SizedBox(height: 24),
                          SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                  onPressed: _busy ? null : _login,
                                  child: _busy
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Text('Sign in'))),
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

class _PrivateAccessDialog extends StatefulWidget {
  const _PrivateAccessDialog({
    required this.canonicalServerUrl,
    required this.configure,
  });

  final String canonicalServerUrl;
  final PrivateAccessSetup configure;

  @override
  State<_PrivateAccessDialog> createState() => _PrivateAccessDialogState();
}

class _PrivateAccessDialogState extends State<_PrivateAccessDialog> {
  final _invitation = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _invitation.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _configure() async {
    final invitation = _invitation.text;
    final code = _code.text.trim();
    _code.clear();
    if (invitation.trim().isEmpty || code.isEmpty) {
      setState(() => _error = 'Enter an invitation and setup code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.configure(widget.canonicalServerUrl, invitation, code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Private access setup failed. Check the invitation and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('Set up private access'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: _invitation,
                  maxLines: 5,
                  minLines: 3,
                  decoration: const InputDecoration(labelText: 'Invitation'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Setup code'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.orangeAccent)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: _busy ? null : _configure,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Configure private access'),
            ),
          ],
        ),
      );
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker(
      {required this.profiles,
      required this.loading,
      required this.error,
      required this.onRetry,
      required this.onSelected});

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
        Expanded(
            child: Text(error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.orangeAccent))),
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
              label: Text(profile.name.isEmpty ? 'Unnamed' : profile.name,
                  overflow: TextOverflow.ellipsis),
              onPressed: () => onSelected(profile),
            ),
        ],
      ),
    );
  }
}
