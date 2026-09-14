import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class MediaBar extends StatefulWidget {
  const MediaBar({required this.engine, super.key, this.initialVolume = 0.8});

  final PlaybackEngine engine;
  final double initialVolume;

  @override
  State<MediaBar> createState() => _MediaBarState();
}

class _MediaBarState extends State<MediaBar> {
  PlaybackEngine get _engine => widget.engine;
  late double _volume;
  late double _savedVolume;

  @override
  void initState() {
    super.initState();
    _volume = widget.initialVolume.clamp(0.0, 1.0);
    _savedVolume = _volume == 0 ? 0.8 : _volume;
    unawaited(_engine.setVolume(_volume * 100));
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value.clamp(0.0, 1.0);
      if (_volume > 0) _savedVolume = _volume;
    });
    unawaited(_engine.setVolume(_volume * 100));
  }

  void _toggleMute() => _setVolume(
        _volume == 0 ? (_savedVolume == 0 ? 0.8 : _savedVolume) : 0,
      );

  void _openSettings() {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => BackdropFilter(
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
                Row(
                  children: [
                    Text(
                      'Playback settings',
                      style: Theme.of(dialogContext).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Volume ${(_volume * 100).round()}%',
                  style: TextStyle(color: theme.textPrimary),
                ),
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
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return ValueListenableBuilder<bool>(
      valueListenable: _engine.playing,
      builder: (context, isPlaying, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _engine.buffering,
          builder: (context, isBuffering, _) {
            return ValueListenableBuilder<Duration>(
              valueListenable: _engine.durationListenable,
              builder: (context, duration, _) {
                return ValueListenableBuilder<Duration>(
                  valueListenable: _engine.positionListenable,
                  builder: (context, position, _) {
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
                          border: Border.all(
                            color: theme.textMuted.withValues(alpha: 0.28),
                          ),
                          boxShadow: theme.glassShadow,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                                onChanged: duration == Duration.zero
                                    ? null
                                    : (next) => _engine.seek(
                                          Duration(milliseconds: next.round()),
                                        ),
                              ),
                            ),
                            _ControlButton(
                              tooltip: isPlaying ? 'Pause' : 'Play',
                              icon: isBuffering
                                  ? Icons.hourglass_top_rounded
                                  : (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                              onPressed: _engine.playOrPause,
                            ),
                            const SizedBox(width: 6),
                            _ControlButton(
                              tooltip: 'Settings',
                              icon: Icons.tune_rounded,
                              onPressed: _openSettings,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
  const _ControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
        ),
      );
}
