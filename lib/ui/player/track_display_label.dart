import 'package:rodplayer/core/player/track_controller.dart';

String audioTrackPrimaryLabel(RodPlayerTrack track, {int? ordinal}) =>
    _languageLabel(track) ??
    _cleanTitle(track.displayTitle) ??
    _cleanTitle(track.title) ??
    'Audio track ${ordinal ?? (track.serverStreamIndex ?? 0) + 1}';

String audioTrackSecondaryLabel(RodPlayerTrack track) => _join(<String>[
      if (_meaningful(track.channelLayout) != null)
        track.channelLayout!.trim()
      else if (track.channels != null && track.channels! > 0)
        '${track.channels} channels',
      if (_codecLabel(track.codec) != null) _codecLabel(track.codec)!,
    ]);

String subtitleTrackPrimaryLabel(RodPlayerTrack track, {int? ordinal}) {
  final title = _cleanTitle(track.displayTitle) ?? _cleanTitle(track.title);
  if (title != null) {
    final language = _meaningful(track.language);
    return language == null
        ? _humanizeLanguage(title)
        : _humanizeSubtitleTitle(title, language);
  }
  return _languageLabel(track) ?? 'Unknown';
}

String _humanizeSubtitleTitle(String title, String language) {
  final matchesLanguage =
      title.toLowerCase().startsWith(language.toLowerCase());
  if (!matchesLanguage) return title;
  if (title.length == language.length) return _humanizeLanguage(language);
  final boundary = title.substring(language.length, language.length + 1);
  if (!RegExp(r'^[\s\-–—(]').hasMatch(boundary)) return title;
  return '${_humanizeLanguage(language)}${title.substring(language.length)}';
}

String subtitleTrackSecondaryLabel(RodPlayerTrack track) => _join(<String>[
      if (_codecLabel(track.codec) != null) _codecLabel(track.codec)!,
      if (track.isExternal == true) 'External',
      if (track.isExternal == false) 'Embedded',
      if (track.isForced == true) 'Forced',
      if (track.isDefault == true) 'Default',
    ], separator: ' · ');

String audioTrackDisplayLabel(RodPlayerTrack track, {int? ordinal}) =>
    _withSecondary(audioTrackPrimaryLabel(track, ordinal: ordinal),
        audioTrackSecondaryLabel(track));

String subtitleTrackDisplayLabel(RodPlayerTrack track, {int? ordinal}) =>
    _withSecondary(subtitleTrackPrimaryLabel(track, ordinal: ordinal),
        subtitleTrackSecondaryLabel(track));

String? _languageLabel(RodPlayerTrack track) {
  final raw = _meaningful(track.language);
  if (raw == null) return null;
  return _humanizeLanguage(raw);
}

String _humanizeLanguage(String raw) {
  final key = raw.toLowerCase().replaceAll('_', '-');
  const common = <String, String>{
    'eng': 'English',
    'en': 'English',
    'spa': 'Spanish',
    'es': 'Spanish',
    'fra': 'French',
    'fre': 'French',
    'fr': 'French',
    'deu': 'German',
    'ger': 'German',
    'de': 'German',
    'ita': 'Italian',
    'it': 'Italian',
    'jpn': 'Japanese',
    'ja': 'Japanese',
  };
  return common[key] ?? raw;
}

String? _cleanTitle(String? value) {
  final clean = _meaningful(value);
  if (clean == null) return null;
  final simplified = clean
      .split(RegExp(r'\s*[·•]\s*'))
      .where((part) => !RegExp(r'^(default|forced|external|embedded|text)$',
              caseSensitive: false)
          .hasMatch(part.trim()))
      .join(' ')
      .trim();
  return simplified.isEmpty ? null : simplified;
}

String? _codecLabel(String? codec) {
  final value = _meaningful(codec);
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case 'subrip':
    case 'subrip/srt':
      return 'SRT';
    case 'webvtt':
    case 'vtt':
      return 'WebVTT';
    case 'ass':
    case 'ssa':
      return value.toUpperCase();
    case 'eac3':
      return 'E-AC-3';
    case 'ac3':
      return 'AC-3';
    case 'aac':
      return 'AAC';
    case 'dts':
      return 'DTS';
    default:
      return value.toUpperCase();
  }
}

String? _meaningful(String? value) {
  final clean = value?.trim();
  if (clean == null ||
      clean.isEmpty ||
      clean.toLowerCase() == 'unknown track') {
    return null;
  }
  return clean;
}

String _join(Iterable<String> values, {String separator = ' · '}) =>
    values.where((value) => value.trim().isNotEmpty).join(separator);

String _withSecondary(String primary, String secondary) =>
    secondary.isEmpty ? primary : '$primary · $secondary';
