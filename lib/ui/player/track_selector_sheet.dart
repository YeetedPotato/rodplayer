import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class TrackSelectorSheet extends StatefulWidget {
  const TrackSelectorSheet({super.key, required this.controller});
  final TrackSelectionController controller;

  static Future<void> show(BuildContext context, {required TrackSelectionController controller}) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.62), builder: (_) => TrackSelectorSheet(controller: controller),
  );

  @override
  State<TrackSelectorSheet> createState() => _TrackSelectorSheetState();
}

class _TrackSelectorSheetState extends State<TrackSelectorSheet> {
  Future<void> _selectAudio(RodPlayerTrack track) async { await widget.controller.selectAudio(track); setState(() {}); }
  Future<void> _selectSubtitle(RodPlayerTrack? track) async { await widget.controller.selectSubtitle(track); setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final controller = widget.controller;
    final selectedAudio = controller.selectedAudio;
    final selectedSubtitle = controller.selectedSubtitle;
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
              _TrackGroup<RodPlayerTrack>(title: 'Audio', tracks: controller.audioTracks, selected: selectedAudio, label: (track) => track.label, onSelected: _selectAudio),
              const SizedBox(height: 20),
              _TrackGroup<RodPlayerTrack>(title: 'Subtitles', tracks: controller.subtitleTracks, selected: selectedSubtitle, label: (track) => track.label, onSelected: _selectSubtitle, onOff: () => _selectSubtitle(null)),
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
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
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
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
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
