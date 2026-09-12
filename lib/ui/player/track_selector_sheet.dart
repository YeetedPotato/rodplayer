import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';

class TrackSelectorSheet extends StatefulWidget {
  const TrackSelectorSheet({super.key, required this.player});
  final Player player;

  static Future<void> show(BuildContext context, {required Player player}) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.62), builder: (_) => TrackSelectorSheet(player: player),
  );

  @override
  State<TrackSelectorSheet> createState() => _TrackSelectorSheetState();
}

class _TrackSelectorSheetState extends State<TrackSelectorSheet> {
  void _selectAudio(AudioTrack track) { widget.player.setAudioTrack(track); setState(() {}); }
  void _selectSubtitle(SubtitleTrack track) { widget.player.setSubtitleTrack(track); setState(() {}); }

  String _trackLabel(String? title, String? language) {
    final parts = <String?>[title, language].whereType<String>().where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? 'Unknown track' : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    final state = widget.player.state;
    final selectedAudio = state.track.audio;
    final selectedSubtitle = state.track.subtitle;
    return SafeArea(child: ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(theme.radiusLarge)),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: Material(
        color: theme.obsidianGlassStrong.withValues(alpha: 0.96),
        child: Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 24), child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[Text('Tracks', style: Theme.of(context).textTheme.titleLarge), const Spacer(), IconButton(autofocus: true, tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
              _TrackGroup<AudioTrack>(title: 'Audio', tracks: state.tracks.audio, selected: selectedAudio, label: (track) => _trackLabel(track.title, track.language), onSelected: _selectAudio),
              const SizedBox(height: 20),
              _TrackGroup<SubtitleTrack>(title: 'Subtitles', tracks: state.tracks.subtitle, selected: selectedSubtitle, label: (track) => _trackLabel(track.title, track.language), onSelected: _selectSubtitle, onOff: () => _selectSubtitle(SubtitleTrack.no())),
            ],
          ))),
        )),
      )),
    ));
  }
}

class _TrackGroup<T> extends StatelessWidget {
  const _TrackGroup({required this.title, required this.tracks, required this.selected, required this.label, required this.onSelected, this.onOff});
  final String title;
  final List<T> tracks;
  final T? selected;
  final String Function(T track) label;
  final ValueChanged<T> onSelected;
  final VoidCallback? onOff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title.toUpperCase(), style: TextStyle(color: theme.goldBright, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      if (tracks.isEmpty) Text('No tracks available', style: TextStyle(color: theme.textMuted)) else ...tracks.map((track) => _TrackTile(label: label(track), selected: track == selected, onTap: () => onSelected(track))),
      if (onOff != null) _TrackTile(label: 'Off', selected: selected == null, onTap: onOff!),
    ]);
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return Focus(autofocus: selected, child: Builder(builder: (context) {
      final focused = Focus.of(context).hasFocus;
      return Semantics(button: true, selected: selected, label: label, child: InkWell(
        onTap: onTap, focusColor: theme.goldBright.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(theme.radiusSmall),
        child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), decoration: BoxDecoration(
          color: selected ? theme.goldBright.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(theme.radiusSmall), border: Border.all(color: focused ? theme.goldBright : Colors.transparent, width: 2),
        ), child: Row(children: <Widget>[
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? theme.goldBright : theme.textMuted),
          const SizedBox(width: 10), Expanded(child: Text(label, style: TextStyle(color: theme.textPrimary))),
        ])),
      ));
    }));
  }
}
