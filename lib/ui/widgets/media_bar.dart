import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';

class MediaBar extends StatefulWidget {
  const MediaBar({super.key, this.initialVolume = 0.8});
  final double initialVolume;

  @override
  State<MediaBar> createState() => _MediaBarState();
}

class _MediaBarState extends State<MediaBar> {
  late double _volume;
  late double _savedVolume;
  bool _isPlaying = true;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    _volume = widget.initialVolume.clamp(0.0, 1.0);
    _savedVolume = _volume == 0 ? 0.8 : _volume;
  }

  void _toggleMute() {
    setState(() {
      if (_volume == 0) {
        _volume = _savedVolume == 0 ? 0.8 : _savedVolume;
      } else {
        _savedVolume = _volume;
        _volume = 0;
      }
    });
  }

  void _toggleSettings() => setState(() => _settingsOpen = !_settingsOpen);
  void _togglePlayback() => setState(() => _isPlaying = !_isPlaying);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return Semantics(
      label: 'Media controls',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(6),
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
          const SizedBox(width: 6),
          _ControlButton(
            tooltip: _isPlaying ? 'Pause slideshow' : 'Play slideshow',
            icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onPressed: _togglePlayback,
          ),
          const SizedBox(width: 6),
          _ControlButton(
            tooltip: 'Settings',
            icon: Icons.tune_rounded,
            onPressed: _toggleSettings,
          ),
        ]),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _settingsOpen) _showSettingsDialog();
      });
    }
  }

  void _showSettingsDialog() {
    setState(() => _settingsOpen = false);
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Dialog(
          backgroundColor: theme.obsidianGlassStrong.withValues(alpha: 0.96),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(theme.radiusLarge), side: BorderSide(color: theme.gold.withValues(alpha: 0.4))),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text('Playback settings', style: Theme.of(context).textTheme.titleLarge), const Spacer(), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
              const SizedBox(height: 12),
              Text('Media source', style: TextStyle(color: theme.goldBright, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('media.example.com', style: TextStyle(color: theme.textSecondary)),
              const SizedBox(height: 16),
              Text('Volume ${(100 * _volume).round()}%', style: TextStyle(color: theme.textPrimary)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.tooltip, required this.icon, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36,
        height: 36,
        child: IconButton(padding: EdgeInsets.zero, tooltip: tooltip, onPressed: onPressed, icon: Icon(icon, size: 20)),
      );
}
