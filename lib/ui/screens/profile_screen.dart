import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.client, required this.onSwitchProfile, required this.onLogout, super.key});

  final JellyfinApiClient client;
  final Future<void> Function() onSwitchProfile;
  final Future<void> Function() onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  JellyfinUserProfile? _profile;
  Object? _error;
  bool _loading = true;
  bool _saving = false;
  String? _saveError;
  int _generation = 0;

  final _audio = TextEditingController();
  final _subtitle = TextEditingController();
  JellyfinSubtitleMode? _subtitleMode;
  bool _playDefaultAudioTrack = true;
  bool _rememberAudio = true;
  bool _rememberSubtitles = true;
  bool _autoplayNext = true;
  bool _hidePlayed = false;
  bool _displayMissing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) _load();
  }

  @override
  void dispose() {
    _audio.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _saving = false;
      _error = null;
      _saveError = null;
    });
    try {
      final profile = await widget.client.getCurrentUser();
      if (!mounted || generation != _generation) return;
      _apply(profile);
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _apply(JellyfinUserProfile profile) {
    final config = profile.configuration;
    _audio.text = config.audioLanguagePreference ?? '';
    _subtitle.text = config.subtitleLanguagePreference ?? '';
    _subtitleMode = config.subtitleMode ?? JellyfinSubtitleMode.defaultMode;
    _playDefaultAudioTrack = config.playDefaultAudioTrack ?? true;
    _rememberAudio = config.rememberAudioSelections ?? true;
    _rememberSubtitles = config.rememberSubtitleSelections ?? true;
    _autoplayNext = config.enableNextEpisodeAutoPlay ?? true;
    _hidePlayed = config.hidePlayedInLatest ?? false;
    _displayMissing = config.displayMissingEpisodes ?? false;
  }

  Future<void> _save() async {
    final profile = _profile;
    if (profile == null || _saving) return;
    final generation = _generation;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final updated = profile.configuration.copyWith(
      audioLanguagePreference: _blank(_audio.text),
      subtitleLanguagePreference: _blank(_subtitle.text),
      subtitleMode: _subtitleMode,
      playDefaultAudioTrack: _playDefaultAudioTrack,
      rememberAudioSelections: _rememberAudio,
      rememberSubtitleSelections: _rememberSubtitles,
      enableNextEpisodeAutoPlay: _autoplayNext,
      hidePlayedInLatest: _hidePlayed,
      displayMissingEpisodes: _displayMissing,
    );
    try {
      await widget.client.updateCurrentUserConfiguration(updated);
      if (!mounted || generation != _generation) return;
      setState(() {
        _profile = JellyfinUserProfile(
          id: profile.id,
          name: profile.name,
          serverId: profile.serverId,
          serverName: profile.serverName,
          primaryImageTag: profile.primaryImageTag,
          primaryImageAspectRatio: profile.primaryImageAspectRatio,
          hasPassword: profile.hasPassword,
          hasConfiguredPassword: profile.hasConfiguredPassword,
          hasConfiguredEasyPassword: profile.hasConfiguredEasyPassword,
          enableAutoLogin: profile.enableAutoLogin,
          lastLoginDate: profile.lastLoginDate,
          lastActivityDate: profile.lastActivityDate,
          configuration: updated,
          policy: profile.policy,
          raw: profile.raw,
        );
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferences saved')));
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _saveError = 'Could not save preferences.');
    } finally {
      if (mounted && generation == _generation) setState(() => _saving = false);
    }
  }

  Future<void> _leave(Future<void> Function() action) async {
    await action();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Could not load profile'), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Retry'))]))
                : _content(context, _profile!),
      );

  Widget _content(BuildContext context, JellyfinUserProfile profile) {
    final imageUri = widget.client.userPrimaryImageUri(profile);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            CircleAvatar(radius: 34, foregroundImage: imageUri == null ? null : NetworkImage(imageUri.toString(), headers: widget.client.headers), child: Text(profile.initials)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile.name.isEmpty ? 'Unnamed profile' : profile.name, style: Theme.of(context).textTheme.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (profile.serverName != null && profile.serverName!.trim().isNotEmpty)
                  Text(profile.serverName!, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(widget.client.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (profile.policy.isAdministrator) const Padding(padding: EdgeInsets.only(top: 6), child: Chip(label: Text('Administrator'))),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          Text('Jellyfin Profile Preferences', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _audio, decoration: const InputDecoration(labelText: 'Preferred audio language', helperText: 'Examples: eng / spa. Blank uses server default.')),
          const SizedBox(height: 12),
          TextField(controller: _subtitle, decoration: const InputDecoration(labelText: 'Preferred subtitle language', helperText: 'Examples: eng / spa. Blank uses server default.')),
          const SizedBox(height: 12),
          DropdownButtonFormField<JellyfinSubtitleMode>(
            initialValue: _subtitleMode,
            decoration: const InputDecoration(labelText: 'Subtitle mode'),
            items: [for (final mode in JellyfinSubtitleMode.values) DropdownMenuItem(value: mode, child: Text(mode.label))],
            onChanged: (value) => setState(() => _subtitleMode = value),
          ),
          SwitchListTile(value: _playDefaultAudioTrack, onChanged: (value) => setState(() => _playDefaultAudioTrack = value), title: const Text('Play default audio track')),
          SwitchListTile(value: _rememberAudio, onChanged: (value) => setState(() => _rememberAudio = value), title: const Text('Remember audio selections')),
          SwitchListTile(value: _rememberSubtitles, onChanged: (value) => setState(() => _rememberSubtitles = value), title: const Text('Remember subtitle selections')),
          SwitchListTile(value: _autoplayNext, onChanged: (value) => setState(() => _autoplayNext = value), title: const Text('Autoplay next episode')),
          SwitchListTile(value: _hidePlayed, onChanged: (value) => setState(() => _hidePlayed = value), title: const Text('Hide played items in Latest')),
          SwitchListTile(value: _displayMissing, onChanged: (value) => setState(() => _displayMissing = value), title: const Text('Display missing episodes')),
          if (_saveError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_saveError!, style: const TextStyle(color: Colors.orangeAccent))),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save preferences')),
          const Divider(height: 36),
          Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton.icon(onPressed: () => _leave(widget.onSwitchProfile), icon: const Icon(Icons.switch_account), label: const Text('Switch profile')),
            OutlinedButton.icon(onPressed: () => _leave(widget.onLogout), icon: const Icon(Icons.logout), label: const Text('Log out')),
          ]),
        ],
      ),
    );
  }
}

String? _blank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
