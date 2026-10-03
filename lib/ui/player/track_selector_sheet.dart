import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/track_display_label.dart';

typedef SubtitleRenegotiator = Future<void> Function(RodPlayerTrack track);

/// Backend-neutral subtitle controls for the active runtime.
class TrackSelectorSheet extends StatefulWidget {
  const TrackSelectorSheet({
    super.key,
    required this.controls,
    this.onRenegotiateSubtitle,
    this.commandController,
    this.desktop = false,
  });

  final ValueListenable<PlaybackRuntimeViewBinding> controls;
  final SubtitleRenegotiator? onRenegotiateSubtitle;
  final PlaybackCommandController? commandController;
  final bool desktop;

  static Future<void> show(
    BuildContext context, {
    required ValueListenable<PlaybackRuntimeViewBinding> controls,
    SubtitleRenegotiator? onRenegotiateSubtitle,
    PlaybackCommandController? commandController,
  }) {
    if (MediaQuery.sizeOf(context).width >= 760) {
      final size = MediaQuery.sizeOf(context);
      final width = size.width.clamp(360.0, 420.0).toDouble();
      final height = (size.height * .66).clamp(320.0, 620.0).toDouble();
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          alignment: Alignment.bottomRight,
          insetPadding: const EdgeInsets.fromLTRB(24, 24, 24, 92),
          child: SizedBox(
            width: width,
            height: height,
            child: TrackSelectorSheet(
              controls: controls,
              onRenegotiateSubtitle: onRenegotiateSubtitle,
              commandController: commandController,
              desktop: true,
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (_) => TrackSelectorSheet(
        controls: controls,
        onRenegotiateSubtitle: onRenegotiateSubtitle,
        commandController: commandController,
      ),
    );
  }

  @override
  State<TrackSelectorSheet> createState() => _TrackSelectorSheetState();
}

class _TrackSelectorSheetState extends State<TrackSelectorSheet> {
  static const _delayStep = Duration(milliseconds: 50);
  var _busy = false;

  Future<void> _selectAudio(RodPlayerTrack track) async {
    if (_busy) return;
    final tracks = widget.controls.value.tracks;
    if (tracks == null) return;
    setState(() => _busy = true);
    try {
      final commands = widget.commandController;
      if (commands != null) {
        final result = await commands.dispatchCurrent(
          command: SelectAudioCommand(track),
          origin: PlaybackCommandOrigin.localUi,
        );
        if (result.status == PlaybackCommandStatus.needsServerRenegotiation ||
            result.status == PlaybackCommandStatus.externalAttachRequired) {
          _showError(
            'This audio track requires a source change that is not available here.',
          );
          return;
        }
        if (!result.wasApplied) {
          throw StateError('Audio selection was not executed.');
        }
      } else {
        final result = await tracks.selectAudio(track);
        if (result.mode != TrackSwitchMode.local) {
          throw StateError(
            'This audio track cannot be selected by the active runtime.',
          );
        }
      }
      if (mounted) setState(() {});
    } on Object {
      _showError('Unable to change audio track');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectSubtitle(RodPlayerTrack? track) async {
    if (_busy) return;
    final controls = widget.controls.value;
    final tracks = controls.tracks;
    if (tracks == null) return;
    setState(() => _busy = true);
    try {
      final commands = widget.commandController;
      if (commands != null) {
        final result = await commands.dispatchCurrent(
          command: SelectSubtitleCommand(track),
          origin: PlaybackCommandOrigin.localUi,
        );
        if (!result.wasApplied) {
          throw StateError('Subtitle selection was not executed.');
        }
      } else {
        final result = await tracks.selectSubtitle(track);
        if (result.mode == TrackSwitchMode.serverRenegotiation) {
          if (track == null || track.serverStreamIndex == null) {
            throw StateError(
              'This subtitle choice requires server renegotiation and cannot be represented.',
            );
          }
          final callback = widget.onRenegotiateSubtitle;
          if (callback == null) {
            throw StateError('Subtitle renegotiation is unavailable.');
          }
          await callback(track);
        }
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
      final commands = widget.commandController;
      if (commands != null) {
        final result = await commands.dispatchCurrent(
          command: AdjustSubtitleDelayCommand(
            advanced.subtitleDelay.value + delta,
          ),
          origin: PlaybackCommandOrigin.localUi,
        );
        if (result.status != PlaybackCommandStatus.executed) {
          throw StateError('Subtitle delay command was not executed.');
        }
      } else {
        await advanced.adjustSubtitleDelay(
          advanced.subtitleDelay.value + delta,
        );
      }
      if (mounted) setState(() {});
    } on Object {
      _showError('Unable to adjust subtitle delay');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return ValueListenableBuilder<PlaybackRuntimeViewBinding>(
      valueListenable: widget.controls,
      builder: (_, controls, __) {
        final tracks = controls.tracks;
        final capabilities = controls.capabilities;
        final canSelectAudio = tracks != null &&
            capabilities.audioTrackSwitching == CapabilitySupport.supported;
        final canSelectSubtitle = tracks != null &&
            capabilities.subtitleTrackSwitching == CapabilitySupport.supported;
        final audioTracks = canSelectAudio && tracks.audioTracks.length > 1
            ? tracks.audioTracks
            : const <RodPlayerTrack>[];
        final subtitleTracks = canSelectSubtitle
            ? tracks.subtitleTracks
            : const <RodPlayerTrack>[];
        final canDelay = controls.advanced != null &&
            capabilities.subtitleDelay == CapabilitySupport.supported;
        final onlySubtitles = audioTracks.isEmpty && subtitleTracks.isNotEmpty;
        return SafeArea(
          child: ClipRRect(
            borderRadius: widget.desktop
                ? BorderRadius.circular(theme.radiusLarge)
                : BorderRadius.vertical(
                    top: Radius.circular(theme.radiusLarge),
                  ),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.desktop ? 10 : 18,
                sigmaY: widget.desktop ? 10 : 18,
              ),
              child: Material(
                color: theme.obsidianGlassStrong.withValues(alpha: 0.96),
                child: SizedBox(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.desktop ? 18 : 24,
                      widget.desktop ? 12 : 20,
                      widget.desktop ? 18 : 24,
                      widget.desktop ? 16 : 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: widget.desktop
                            ? MediaQuery.sizeOf(context).height * .66
                            : 640,
                      ),
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      onlySubtitles
                                          ? 'Subtitles'
                                          : 'Audio & subtitles',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                  ),
                                  IconButton(
                                    autofocus: true,
                                    tooltip: 'Close subtitle settings',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              if (audioTracks.isEmpty && subtitleTracks.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text('No track choices available'),
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final both = audioTracks.isNotEmpty &&
                                        subtitleTracks.isNotEmpty;
                                    final sideBySide =
                                        both && constraints.maxWidth >= 560;
                                    final columnWidth = sideBySide
                                        ? (constraints.maxWidth - 20) / 2
                                        : constraints.maxWidth;
                                    return Wrap(
                                      spacing: 20,
                                      runSpacing: 12,
                                      children: <Widget>[
                                        if (audioTracks.isNotEmpty)
                                          SizedBox(
                                            width: columnWidth,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                const _SectionLabel('Audio'),
                                                for (final entry in audioTracks
                                                    .asMap()
                                                    .entries)
                                                  _SubtitleChoice(
                                                    title:
                                                        audioTrackPrimaryLabel(
                                                      entry.value,
                                                      ordinal: entry.key + 1,
                                                    ),
                                                    subtitle:
                                                        audioTrackSecondaryLabel(
                                                      entry.value,
                                                    ),
                                                    selected: entry.value ==
                                                        tracks?.selectedAudio,
                                                    enabled: !_busy,
                                                    onTap: () => unawaited(
                                                      _selectAudio(entry.value),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        if (subtitleTracks.isNotEmpty)
                                          SizedBox(
                                            width: columnWidth,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                if (audioTracks.isNotEmpty)
                                                  const _SectionLabel(
                                                    'Subtitles',
                                                  ),
                                                _SubtitleChoice(
                                                  title: 'Off',
                                                  subtitle: '',
                                                  selected: tracks
                                                          ?.selectedSubtitle ==
                                                      null,
                                                  enabled: !_busy,
                                                  onTap: () => unawaited(
                                                    _selectSubtitle(null),
                                                  ),
                                                ),
                                                for (final entry
                                                    in subtitleTracks
                                                        .asMap()
                                                        .entries)
                                                  _SubtitleChoice(
                                                    title:
                                                        subtitleTrackPrimaryLabel(
                                                      entry.value,
                                                      ordinal: entry.key + 1,
                                                    ),
                                                    subtitle:
                                                        subtitleTrackSecondaryLabel(
                                                      entry.value,
                                                    ),
                                                    selected: entry.value ==
                                                        tracks
                                                            ?.selectedSubtitle,
                                                    enabled: !_busy,
                                                    onTap: () => unawaited(
                                                      _selectSubtitle(
                                                        entry.value,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              if (canDelay) ...<Widget>[
                                const SizedBox(height: 20),
                                const _SectionLabel('Subtitle delay'),
                                ValueListenableBuilder<Duration>(
                                  valueListenable:
                                      controls.advanced!.subtitleDelay,
                                  builder: (_, delay, __) => Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: <Widget>[
                                      Text(_delayLabel(delay)),
                                      OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : () => unawaited(
                                                  _adjustDelay(-_delayStep),
                                                ),
                                        child: const Text('-50 ms'),
                                      ),
                                      OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : () => unawaited(
                                                  _adjustDelay(_delayStep),
                                                ),
                                        child: const Text('+50 ms'),
                                      ),
                                      TextButton(
                                        onPressed:
                                            _busy || delay == Duration.zero
                                                ? null
                                                : () => unawaited(
                                                      _adjustDelay(-delay),
                                                    ),
                                        child: const Text('Reset'),
                                      ),
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
          ),
        );
      },
    );
  }

  String _delayLabel(Duration value) =>
      '${value.inMilliseconds >= 0 ? '+' : ''}${value.inMilliseconds} ms';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).extension<RodPlayerTheme>()?.accentBright,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _SubtitleChoice extends StatelessWidget {
  const _SubtitleChoice({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Semantics(
      button: true,
      selected: selected,
      label: subtitle.isEmpty ? title : '$title, $subtitle',
      child: InkWell(
        onTap: enabled ? onTap : null,
        focusColor: theme.accentBright.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(theme.radiusSmall),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.surface2.withValues(alpha: 0.45)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(theme.radiusSmall),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check, size: 18, color: theme.accentBright),
            ],
          ),
        ),
      ),
    );
  }
}
