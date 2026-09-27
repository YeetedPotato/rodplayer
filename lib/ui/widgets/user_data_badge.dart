import 'package:flutter/material.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class UserDataBadge extends StatelessWidget {
  const UserDataBadge({required this.userData, super.key});
  final JellyfinUserData userData;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[if (userData.isFavorite) 'Favorite', if (userData.played) 'Watched'];
    if (labels.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Semantics(
      label: labels.join(', '),
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.obsidianGlassStrong, borderRadius: BorderRadius.circular(theme.radiusPill), border: Border.all(color: theme.accentBright.withValues(alpha: .34))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (userData.isFavorite) Icon(Icons.favorite, size: 15, color: theme.accentBright),
            if (userData.isFavorite && userData.played) const SizedBox(width: 5),
            if (userData.played) Icon(Icons.check_circle, size: 15, color: theme.accentBright),
          ]),
        ),
      ),
    );
  }
}

Widget? userDataBadgeFor(JellyfinLibraryItem item) => item.userData.isFavorite || item.userData.played ? UserDataBadge(userData: item.userData) : null;
