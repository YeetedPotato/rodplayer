import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';

class TrackSelectorOverlay extends StatelessWidget {
  const TrackSelectorOverlay({super.key, required this.engine});
  final RemuxEngine engine;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return BackdropFilter(filter: ImageFilter.blur(sigmaX: theme.glassBlur, sigmaY: theme.glassBlur), child: Dialog(
      backgroundColor: theme.obsidianGlassStrong.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(theme.radiusLarge), side: BorderSide(color: theme.gold.withValues(alpha: 0.42))),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620), child: Padding(padding: const EdgeInsets.all(24), child: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text('Tracks', style: Theme.of(context).textTheme.titleLarge), const Spacer(), IconButton(autofocus: true, tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
        _TrackSection<AudioTrack>(title: 'Audio', tracks: engine.audioTracks, selected: engine.selectedAudioTrack, label: (t) => _label(t.title, t.language, t.codec), onSelected: (t) async { await engine.selectAudioTrack(t); if (context.mounted) Navigator.pop(context); }),
        const SizedBox(height: 18),
        _TrackSection<SubtitleTrack>(title: 'Subtitles', tracks: engine.subtitleTracks, selected: engine.selectedSubtitleTrack, label: (t) => _label(t.title, t.language, t.codec), onSelected: (t) async { await engine.selectSubtitleTrack(t); if (context.mounted) Navigator.pop(context); }, allowOff: true, onOff: () async { await engine.disableSubtitles(); if (context.mounted) Navigator.pop(context); }),
      ]))))));
  }
  static String _label(String? title, String? language, String? codec) => [title, language, codec].where((x) => x != null && x.isNotEmpty).join(' • ').isEmpty ? 'Unknown track' : [title, language, codec].where((x) => x != null && x.isNotEmpty).join(' • ');
}

class _TrackSection<T> extends StatelessWidget {
  const _TrackSection({required this.title, required this.tracks, required this.selected, required this.label, required this.onSelected, this.allowOff = false, this.onOff});
  final String title; final List<T> tracks; final T? selected; final String Function(T) label; final Future<void> Function(T) onSelected; final bool allowOff; final Future<void> Function()? onOff;
  @override Widget build(BuildContext context) { final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme(); return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title.toUpperCase(), style: TextStyle(color: theme.goldBright, fontWeight: FontWeight.w700, letterSpacing: 1.2)), const SizedBox(height: 8), if (tracks.isEmpty) Text('No tracks available', style: TextStyle(color: theme.textMuted)) else ...tracks.map((track) => _TrackTile<T>(track: track, selected: identical(track, selected), label: label(track), onTap: () => onSelected(track))), if (allowOff) _TrackTile<T>(track: null, selected: selected == null, label: 'Off', onTap: onOff == null ? null : onOff!) ]); }
}
class _TrackTile<T> extends StatelessWidget { const _TrackTile({required this.track, required this.selected, required this.label, this.onTap}); final T? track; final bool selected; final String label; final Future<void> Function()? onTap; @override Widget build(BuildContext context) { final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme(); return FocusableActionDetector(child: Builder(builder: (context) { final focused = Focus.of(context).hasFocus; return ListTile(autofocus: selected, focusColor: theme.goldBright.withValues(alpha: 0.18), selected: selected, selectedTileColor: theme.goldBright.withValues(alpha: 0.10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(theme.radiusSmall), side: BorderSide(color: focused ? theme.goldBright : Colors.transparent, width: 2)), leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? theme.goldBright : theme.textMuted), title: Text(label, style: TextStyle(color: theme.textPrimary)), onTap: onTap == null ? null : () => onTap!();); }), actions: <TypeActivator, Action<Intent>>{ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) { if (onTap != null) onTap!(); return null; })}); } }
