import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

typedef SubtitleRenegotiator = Future<void> Function(RodPlayerTrack track);

/// Backend-neutral subtitle controls for the active runtime.
class TrackSelectorSheet extends StatefulWidget {
  const TrackSelectorSheet({super.key, required this.controls, this.onRenegotiateSubtitle});

  final ValueListenable<PlaybackRuntimeControlsSnapshot> controls;
  final SubtitleRenegotiator? onRenegotiateSubtitle;

  static Future<void> show(
    BuildContext context, {
    required ValueListenable<PlaybackRuntimeControlsSnapshot> controls,
    SubtitleRenegotiator? onRenegotiateSubtitle,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (_) => TrackSelectorSheet(controls: controls, onRenegotiateSubtitle: onRenegotiateSubtitle),
      );

  @override
  State<TrackSelectorSheet> createState() => _TrackSelectorSheetState();
}

class _TrackSelectorSheetState extends State<TrackSelectorSheet> {
  static const _delayStep = Duration(milliseconds: 50);
  var _busy = false;

  Future<void> _selectSubtitle(RodPlayerTrack? track) async {
    if (_busy) return;
    final controls = widget.controls.value;
    final tracks = controls.tracks;
    if (tracks == null) return;
    setState(() => _busy = true);
    try {
      final result = await tracks.selectSubtitle(track);
      if (result.mode == TrackSwitchMode.serverRenegotiation) {
        if (track == null || track.serverStreamIndex == null) {
          throw StateError('This subtitle choice requires server renegotiation and cannot be represented.');
        }
        final callback = widget.onRenegotiateSubtitle;
        if (callback == null) throw StateError('Subtitle renegotiation is unavailable.');
        await callback(track);
      }
      if (mounted) setState(() {});
    } on Object {
      _showError('Unable to change subtitles');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjustDelay(Duration delta) async {
    if (_busy) return;
    final advanced = widget.controls.value.advanced;
    if (advanced == null) return;
    setState(() => _busy = true);
    try {
      await advanced.adjustSubtitleDelay(advanced.subtitleDelay.value + delta);
      if (mounted) setState(() {});
    } on Object {
      _showError('Unable to adjust subtitle delay');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return ValueListenableBuilder<PlaybackRuntimeControlsSnapshot>(
      valueListenable: widget.controls,
      builder: (_, controls, __) {
        final tracks = controls.tracks;
        final capabilities = controls.capabilities;
        final canSelect = tracks != null && capabilities.subtitleTrackSwitching != CapabilitySupport.unsupported;
        final canDelay = controls.advanced != null && capabilities.subtitleDelay != CapabilitySupport.unsupported;
        return SafeArea(
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(theme.radiusLarge)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Material(
                color: theme.obsidianGlassStrong.withValues(alpha: 0.96),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 640),
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(children: <Widget>[
                              Text('Subtitles', style: Theme.of(context).textTheme.titleLarge),
                              const Spacer(),
                              IconButton(autofocus: true, tooltip: 'Close subtitle settings', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                            ]),
                            if (canSelect) ...<Widget>[
                              _SectionLabel('Tracks'),
                              _SubtitleChoice(label: 'Off', selected: tracks.selectedSubtitle == null, enabled: !_busy, onTap: () => unawaited(_selectSubtitle(null))),
                              for (final track in tracks.subtitleTracks)
                                _SubtitleChoice(
                                  label: _trackLabel(track),
                                  selected: track == tracks.selectedSubtitle,
                                  enabled: !_busy,
                                  onTap: () => unawaited(_selectSubtitle(track)),
                                ),
                            ] else
                              const Padding(padding: EdgeInsets.only(top: 12), child: Text('Subtitle tracks are unavailable for this runtime.')),
                            if (canDelay) ...<Widget>[
                              const SizedBox(height: 20),
                              _SectionLabel(capabilities.subtitleDelay == CapabilitySupport.unknown ? 'Subtitle delay (unverified)' : 'Subtitle delay'),
                              ValueListenableBuilder<Duration>(
                                valueListenable: controls.advanced!.subtitleDelay,
                                builder: (_, delay, __) => Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[
                                    Text(_delayLabel(delay)),
                                    OutlinedButton(onPressed: _busy ? null : () => unawaited(_adjustDelay(-_delayStep)), child: const Text('-50 ms')),
                                    OutlinedButton(onPressed: _busy ? null : () => unawaited(_adjustDelay(_delayStep)), child: const Text('+50 ms')),
                                    TextButton(onPressed: _busy || delay == Duration.zero ? null : () => unawaited(_adjustDelay(-delay)), child: const Text('Reset')),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _trackLabel(RodPlayerTrack track) {
    final details = <String>[
      if (track.language?.isNotEmpty ?? false) track.language!,
      if (track.title?.isNotEmpty ?? false) track.title!,
      if (track.codec?.isNotEmpty ?? false) track.codec!,
      if (track.isDefault == true) 'Default',
      if (track.isForced == true) 'Forced',
      if (track.isExternal == true) 'External',
      if (track.isTextSubtitle == true) 'Text',
    ];
    return details.isEmpty ? track.label : details.join(' • ');
  }

  String _delayLabel(Duration value) => '${value.inMilliseconds >= 0 ? '+' : ''}${value.inMilliseconds} ms';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label.toUpperCase(), style: TextStyle(color: Theme.of(context).extension<RodPlayerTheme>()?.goldBright, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      );
}

class _SubtitleChoice extends StatelessWidget {
  const _SubtitleChoice({required this.label, required this.selected, required this.enabled, required this.onTap});
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        focusColor: theme.goldBright.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(theme.radiusSmall),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: selected ? theme.goldBright.withValues(alpha: 0.10) : Colors.transparent, borderRadius: BorderRadius.circular(theme.radiusSmall)),
          child: Row(children: <Widget>[
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? theme.goldBright : theme.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary))),
          ]),
        ),
      ),
    );
  }
}
