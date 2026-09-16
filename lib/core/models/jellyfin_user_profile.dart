enum JellyfinSubtitleMode {
  defaultMode('Default', 'Default'),
  smart('Smart', 'Smart'),
  onlyForced('Only forced', 'OnlyForced'),
  always('Always', 'Always'),
  none('None', 'None');

  const JellyfinSubtitleMode(this.label, this.serverValue);
  final String label;
  final String serverValue;

  static JellyfinSubtitleMode? fromServer(Object? value) {
    final normalized = _string(value)?.trim().toLowerCase();
    return switch (normalized) {
      'default' => defaultMode,
      'smart' => smart,
      'onlyforced' || 'only forced' => onlyForced,
      'always' => always,
      'none' => none,
      _ => null,
    };
  }
}

class JellyfinUserPolicy {
  const JellyfinUserPolicy({this.isAdministrator = false, this.isHidden = false, this.isDisabled = false, this.raw = const <String, dynamic>{}});

  final bool isAdministrator;
  final bool isHidden;
  final bool isDisabled;
  final Map<String, dynamic> raw;

  factory JellyfinUserPolicy.fromJson(Object? value) {
    final json = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    return JellyfinUserPolicy(
      isAdministrator: _bool(json['IsAdministrator']) ?? false,
      isHidden: _bool(json['IsHidden']) ?? false,
      isDisabled: _bool(json['IsDisabled']) ?? false,
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }
}

class JellyfinUserConfiguration {
  const JellyfinUserConfiguration({
    this.audioLanguagePreference,
    this.subtitleLanguagePreference,
    this.subtitleMode,
    this.playDefaultAudioTrack,
    this.rememberAudioSelections,
    this.rememberSubtitleSelections,
    this.enableNextEpisodeAutoPlay,
    this.hidePlayedInLatest,
    this.displayMissingEpisodes,
    this.raw = const <String, dynamic>{},
  });

  final String? audioLanguagePreference;
  final String? subtitleLanguagePreference;
  final JellyfinSubtitleMode? subtitleMode;
  final bool? playDefaultAudioTrack;
  final bool? rememberAudioSelections;
  final bool? rememberSubtitleSelections;
  final bool? enableNextEpisodeAutoPlay;
  final bool? hidePlayedInLatest;
  final bool? displayMissingEpisodes;
  final Map<String, dynamic> raw;

  factory JellyfinUserConfiguration.fromJson(Object? value) {
    final json = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    return JellyfinUserConfiguration(
      audioLanguagePreference: _nonEmpty(json['AudioLanguagePreference']),
      subtitleLanguagePreference: _nonEmpty(json['SubtitleLanguagePreference']),
      subtitleMode: JellyfinSubtitleMode.fromServer(json['SubtitleMode']),
      playDefaultAudioTrack: _bool(json['PlayDefaultAudioTrack']),
      rememberAudioSelections: _bool(json['RememberAudioSelections']),
      rememberSubtitleSelections: _bool(json['RememberSubtitleSelections']),
      enableNextEpisodeAutoPlay: _bool(json['EnableNextEpisodeAutoPlay']),
      hidePlayedInLatest: _bool(json['HidePlayedInLatest']),
      displayMissingEpisodes: _bool(json['DisplayMissingEpisodes']),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  JellyfinUserConfiguration copyWith({
    String? audioLanguagePreference,
    String? subtitleLanguagePreference,
    JellyfinSubtitleMode? subtitleMode,
    bool? playDefaultAudioTrack,
    bool? rememberAudioSelections,
    bool? rememberSubtitleSelections,
    bool? enableNextEpisodeAutoPlay,
    bool? hidePlayedInLatest,
    bool? displayMissingEpisodes,
  }) =>
      JellyfinUserConfiguration(
        audioLanguagePreference: audioLanguagePreference,
        subtitleLanguagePreference: subtitleLanguagePreference,
        subtitleMode: subtitleMode,
        playDefaultAudioTrack: playDefaultAudioTrack,
        rememberAudioSelections: rememberAudioSelections,
        rememberSubtitleSelections: rememberSubtitleSelections,
        enableNextEpisodeAutoPlay: enableNextEpisodeAutoPlay,
        hidePlayedInLatest: hidePlayedInLatest,
        displayMissingEpisodes: displayMissingEpisodes,
        raw: raw,
      );

  Map<String, dynamic> toUpdateJson() => <String, dynamic>{
        ...raw,
        'AudioLanguagePreference': audioLanguagePreference ?? '',
        'SubtitleLanguagePreference': subtitleLanguagePreference ?? '',
        if (subtitleMode != null) 'SubtitleMode': subtitleMode!.serverValue,
        if (playDefaultAudioTrack != null) 'PlayDefaultAudioTrack': playDefaultAudioTrack,
        if (rememberAudioSelections != null) 'RememberAudioSelections': rememberAudioSelections,
        if (rememberSubtitleSelections != null) 'RememberSubtitleSelections': rememberSubtitleSelections,
        if (enableNextEpisodeAutoPlay != null) 'EnableNextEpisodeAutoPlay': enableNextEpisodeAutoPlay,
        if (hidePlayedInLatest != null) 'HidePlayedInLatest': hidePlayedInLatest,
        if (displayMissingEpisodes != null) 'DisplayMissingEpisodes': displayMissingEpisodes,
      };
}

class JellyfinUserProfile {
  const JellyfinUserProfile({
    required this.id,
    required this.name,
    this.serverId,
    this.serverName,
    this.primaryImageTag,
    this.primaryImageAspectRatio,
    this.hasPassword,
    this.hasConfiguredPassword,
    this.hasConfiguredEasyPassword,
    this.enableAutoLogin,
    this.lastLoginDate,
    this.lastActivityDate,
    this.configuration = const JellyfinUserConfiguration(),
    this.policy = const JellyfinUserPolicy(),
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final String? serverId;
  final String? serverName;
  final String? primaryImageTag;
  final double? primaryImageAspectRatio;
  final bool? hasPassword;
  final bool? hasConfiguredPassword;
  final bool? hasConfiguredEasyPassword;
  final bool? enableAutoLogin;
  final DateTime? lastLoginDate;
  final DateTime? lastActivityDate;
  final JellyfinUserConfiguration configuration;
  final JellyfinUserPolicy policy;
  final Map<String, dynamic> raw;

  String get initials {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  factory JellyfinUserProfile.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] is Map ? Map<String, dynamic>.from(json['ImageTags'] as Map) : const <String, dynamic>{};
    return JellyfinUserProfile(
      id: _string(json['Id']) ?? '',
      name: _string(json['Name']) ?? '',
      serverId: _string(json['ServerId']),
      serverName: _string(json['ServerName']),
      primaryImageTag: _string(json['PrimaryImageTag'] ?? imageTags['Primary']),
      primaryImageAspectRatio: _double(json['PrimaryImageAspectRatio']),
      hasPassword: _bool(json['HasPassword']),
      hasConfiguredPassword: _bool(json['HasConfiguredPassword']),
      hasConfiguredEasyPassword: _bool(json['HasConfiguredEasyPassword']),
      enableAutoLogin: _bool(json['EnableAutoLogin']),
      lastLoginDate: _date(json['LastLoginDate']),
      lastActivityDate: _date(json['LastActivityDate']),
      configuration: JellyfinUserConfiguration.fromJson(json['Configuration']),
      policy: JellyfinUserPolicy.fromJson(json['Policy']),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }
}

bool? _bool(Object? value) {
  if (value is bool) return value;
  if (value is! String) return null;
  final normalized = value.trim().toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return null;
}

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value');
double? _double(Object? value) => value is num ? value.toDouble() : double.tryParse('$value');
String? _string(Object? value) => value == null ? null : '$value';
String? _nonEmpty(Object? value) {
  final text = _string(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}
