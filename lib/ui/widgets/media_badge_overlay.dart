import 'package:flutter/material.dart';
import 'package:rodplayer/core/models/media_intelligence.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class MediaBadgeOverlay extends StatelessWidget {
  const MediaBadgeOverlay({required this.mediaInfo, super.key});

  final MediaIntelligence mediaInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final labels = <String>[
      mediaInfo.is4K ? '4K' : _resolutionLabel(mediaInfo),
      if (mediaInfo.video != null && mediaInfo.video!.displayHdr != 'SDR') mediaInfo.video!.displayHdr,
      if (mediaInfo.audio != null) mediaInfo.audio!.displayAudio,
      if (mediaInfo.video != null && _hasUsefulCodec(mediaInfo.video!.displayCodec)) mediaInfo.video!.displayCodec,
    ];

    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: labels.where((label) => label.isNotEmpty).map((label) => _Badge(label: label, theme: theme)).toList(),
    );
  }

  String _resolutionLabel(MediaIntelligence info) {
    final height = info.height;
    if (height == null) return '';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    return '${height}p';
  }

  bool _hasUsefulCodec(String codec) => codec.isNotEmpty && codec != 'Unknown' && codec != 'H.264';
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.theme});

  final String label;
  final RodPlayerTheme theme;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: theme.obsidianGlassStrong,
          borderRadius: BorderRadius.circular(theme.radiusPill),
          border: Border.all(color: theme.textSecondary.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: theme.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
          ),
        ),
      );
}
