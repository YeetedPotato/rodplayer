import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

/// Context actions for a media item. Only actions supplied by the caller are
/// shown, so this sheet cannot imply a capability the screen cannot perform.
Future<void> showQuickActionsSheet(
  BuildContext context, {
  required JellyfinLibraryItem item,
  VoidCallback? onPlay,
  required VoidCallback onDetails,
  VoidCallback? onFavorite,
  VoidCallback? onPlayed,
}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext).extension<RodPlayerTheme>() ??
            const RodPlayerTheme();
        void closeThen(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          scheduleMicrotask(() {
            if (context.mounted) action();
          });
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              color: theme.obsidianGlassStrong,
              borderRadius: BorderRadius.circular(theme.radiusLarge),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(children: <Widget>[
                      Expanded(
                          child: Text(
                              item.title.isEmpty ? 'Media actions' : item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleMedium)),
                      IconButton(
                          tooltip: 'Close actions',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close)),
                    ]),
                  ),
                  if (onPlay != null)
                    _QuickActionTile(
                        icon: Icons.play_arrow,
                        label: 'Play',
                        onTap: () => closeThen(onPlay)),
                  _QuickActionTile(
                      icon: Icons.info_outline,
                      label: 'Details',
                      onTap: () => closeThen(onDetails)),
                  if (onFavorite != null)
                    _QuickActionTile(
                        icon: item.userData.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        label: item.userData.isFavorite
                            ? 'Remove favorite'
                            : 'Add to favorites',
                        onTap: () => closeThen(onFavorite)),
                  if (onPlayed != null)
                    _QuickActionTile(
                        icon: item.userData.played
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        label: item.userData.played
                            ? 'Mark unwatched'
                            : 'Mark watched',
                        onTap: () => closeThen(onPlayed)),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ),
        );
      },
    );

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: onTap,
      );
}
