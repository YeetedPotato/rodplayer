import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';

class MediaBar extends StatefulWidget {
  const MediaBar({
    super.key,
    required this.engine,
    this.initialVolume = 0.8,
  });

  final RodPlayerEngine engine;
  final double initialVolume;

  @override
  State<MediaBar> createState() => _MediaBarState();
}

class _MediaBarState extends State<MediaBar> {
  late double _volume;
  late double _savedVolume;

  @override
  void initState() {
    super.initState();
    _volume = widget.initialVolume.clamp(0.0, 1.0);
    _savedVolume = _volume == 0 ? 0.8 : _volume;
    unawaited(widget.engine.player.setVolume(_volume * 100));
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value.clamp(0.0, 1.0);
      if (_volume > 0) _savedVolume = _volume;
    });
    unawaited(widget.engine.player.setVolume(_volume * 100));
  }

  void _toggleMute() {
    _setVolume(_volume == 0 ? (_savedVolume == 0 ? 0.8 : _savedVolume) : 0);
  }

  void _openSettings() {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Dialog(
          backgroundColor: theme.obsidianGlassStrong.withValues(alpha: 0.96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radiusLarge),
            side: BorderSide(color: theme.gold.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Playback settings', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 12),
                Text('Volume ${(_volume * 100).round()}%', style: TextStyle(color: theme.textPrimary)),
                Slider(value: _volume, onChanged: _setVolume),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return StreamBuilder<bool>(
      stream: widget.engine.player.stream.playing,
      initialData: widget.engine.player.state.playing,
      builder: (context, playingSnapshot) {
        final isPlaying = playingSnapshot.data ?? false;
        return StreamBuilder<bool>(
          stream: widget.engine.player.stream.buffering,
          initialData: widget.engine.player.state.buffering,
          builder: (context, bufferingSnapshot) {
            final isBuffering = bufferingSnapshot.data ?? false;
            return StreamBuilder<Duration>(
              stream: widget.engine.player.stream.position,
              initialData: widget.engine.player.state.position,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                final duration = widget.engine.player.state.duration;
                final maximum = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
                final value = position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();
                return Semantics(
                  label: 'Media controls',
                  container: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.obsidianGlass,
                      borderRadius: BorderRadius.circular(theme.radiusPill),
                      border: Border.all(color: theme.textMuted.withValues(alpha: 0.28)),
                      boxShadow: theme.glassShadow,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _ControlButton(
                        tooltip: _volume == 0 ? 'Unmute' : 'Mute',
                        icon: _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        onPressed: _toggleMute,
                      ),
                      SizedBox(
                        width: 150,
                        child: Slider(
                          min: 0,
                          max: maximum,
                          value: value,
                          onChanged: duration == Duration.zero ? null : (next) => widget.engine.seek(Duration(milliseconds: next.round())),
                        ),
                      ),
                      _ControlButton(
                        tooltip: isPlaying ? 'Pause' : 'Play',
                        icon: isBuffering ? Icons.hourglass_top_rounded : (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        onPressed: widget.engine.player.playOrPause,
                      ),
                      const SizedBox(width: 6),
                      _ControlButton(tooltip: 'Settings', icon: Icons.tune_rounded, onPressed: _openSettings),
                    ]),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(width: 36, height: 36, child: IconButton(padding: EdgeInsets.zero, tooltip: tooltip, onPressed: onPressed, icon: Icon(icon, size: 20)));
}
