import 'package:flutter/material.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/home_library_views.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

enum RodPlayerDestination {
  home('Home', 'Home', Icons.home_outlined, Icons.home),
  movies('Movies', 'Movies', Icons.movie_outlined, Icons.movie),
  tvShows('Shows', 'Shows', Icons.tv_outlined, Icons.tv),
  discover('Discover', 'Discover', Icons.explore_outlined, Icons.explore),
  search('Search', 'Search', Icons.search, Icons.search);

  const RodPlayerDestination(
      this.title, this.compactLabel, this.icon, this.selectedIcon);
  final String title;
  final String compactLabel;
  final IconData icon;
  final IconData selectedIcon;
}

const compactRodPlayerDestinations = <RodPlayerDestination>[
  RodPlayerDestination.home,
  RodPlayerDestination.movies,
  RodPlayerDestination.tvShows,
  RodPlayerDestination.search,
];

const desktopRodPlayerDestinations = <RodPlayerDestination>[
  RodPlayerDestination.home,
  RodPlayerDestination.search,
  RodPlayerDestination.discover,
  RodPlayerDestination.movies,
  RodPlayerDestination.tvShows,
];

class NautilusSideNavigation extends StatelessWidget {
  const NautilusSideNavigation({
    required this.destination,
    required this.focusNodes,
    required this.expanded,
    required this.canCollapse,
    required this.onToggleExpanded,
    required this.onSelect,
    required this.onProfile,
    required this.onLogout,
    this.libraries = const <JellyfinLibraryItem>[],
    this.librariesExpanded = true,
    this.onToggleLibraries,
    this.selectedLibraryId,
    this.onSelectLibrary,
    super.key,
  });

  final RodPlayerDestination destination;
  final Map<RodPlayerDestination, FocusNode> focusNodes;
  final bool expanded;
  final bool canCollapse;
  final VoidCallback onToggleExpanded;
  final ValueChanged<RodPlayerDestination> onSelect;
  final VoidCallback onProfile;
  final VoidCallback onLogout;
  final List<JellyfinLibraryItem> libraries;
  final bool librariesExpanded;
  final VoidCallback? onToggleLibraries;
  final String? selectedLibraryId;
  final ValueChanged<JellyfinLibraryItem>? onSelectLibrary;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      width: expanded ? 216 : 80,
      child: RodPlayerGlass(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showExpanded = expanded && constraints.maxWidth >= 180;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisAlignment: showExpanded
                        ? MainAxisAlignment.spaceBetween
                        : MainAxisAlignment.center,
                    children: [
                      if (showExpanded)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'Nautilus',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .2,
                              ),
                            ),
                          ),
                        ),
                      if (canCollapse)
                        IconButton(
                          tooltip: expanded
                              ? 'Collapse navigation'
                              : 'Expand navigation',
                          onPressed: onToggleExpanded,
                          icon: Icon(
                            expanded
                                ? Icons.keyboard_double_arrow_left
                                : Icons.keyboard_double_arrow_right,
                          ),
                          color: theme.textSecondary,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: FocusTraversalGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in desktopRodPlayerDestinations)
                            _SideNavigationItem(
                              label: item.title,
                              icon: item.icon,
                              selectedIcon: item.selectedIcon,
                              selected: selectedLibraryId == null &&
                                  destination == item,
                              expanded: showExpanded,
                              focusNode: focusNodes[item],
                              onPressed: () => onSelect(item),
                            ),
                          if (libraries.isNotEmpty && showExpanded) ...[
                            const SizedBox(height: 18),
                            Semantics(
                              button: false,
                              expanded: librariesExpanded,
                              label: 'Libraries',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(10, 8, 8, 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text('LIBRARIES',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: theme.textMuted,
                                                    letterSpacing: 1.1)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (showExpanded)
                            for (final library in orderedLibraryViews(
                              libraries,
                              showAll: librariesExpanded,
                            ).where(_isDistinctLibrary))
                              _SideNavigationItem(
                                label: library.title,
                                icon: _libraryIcon(library),
                                selectedIcon: _libraryIcon(library),
                                selected: selectedLibraryId == library.id,
                                expanded: true,
                                onPressed: () => onSelectLibrary?.call(library),
                              ),
                          if (showExpanded &&
                              additionalLibraryViews(libraries).isNotEmpty)
                            TextButton(
                              onPressed: onToggleLibraries,
                              child: Text(librariesExpanded
                                  ? 'Show less'
                                  : 'Show more'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Divider(color: theme.borderColor(.12), height: 24),
                FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SideNavigationItem(
                        label: 'Profile',
                        icon: Icons.person_outline,
                        selectedIcon: Icons.person,
                        expanded: showExpanded,
                        onPressed: onProfile,
                      ),
                      _SideNavigationItem(
                        label: 'Log out',
                        icon: Icons.logout,
                        selectedIcon: Icons.logout,
                        expanded: showExpanded,
                        onPressed: onLogout,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

bool _isDistinctLibrary(JellyfinLibraryItem item) {
  return item.id.isNotEmpty;
}

String _libraryType(JellyfinLibraryItem item) =>
    '${item.raw['CollectionType'] ?? ''}'.trim().toLowerCase();

IconData _libraryIcon(JellyfinLibraryItem item) => switch (_libraryType(item)) {
      'movies' => Icons.movie_outlined,
      'tvshows' => Icons.tv_outlined,
      'music' => Icons.music_note_outlined,
      'homevideos' => Icons.video_library_outlined,
      'books' => Icons.menu_book_outlined,
      _ => Icons.video_library_outlined,
    };

class _SideNavigationItem extends StatelessWidget {
  const _SideNavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.expanded,
    required this.onPressed,
    this.focusNode,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool expanded;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: _NavigationItem(
          label: label,
          icon: selected ? selectedIcon : icon,
          selected: selected,
          expanded: expanded,
          focusNode: focusNode,
          onPressed: onPressed,
        ),
      );
}

class NautilusBottomNavigation extends StatelessWidget {
  const NautilusBottomNavigation(
      {required this.destination, required this.onSelect, super.key});

  final RodPlayerDestination destination;
  final ValueChanged<RodPlayerDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
        child: RodPlayerGlass(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            children: [
              for (final item in compactRodPlayerDestinations)
                Expanded(
                  child: _NavigationItem(
                    label: item.compactLabel,
                    icon: destination == item ? item.selectedIcon : item.icon,
                    selected: destination == item,
                    expanded: true,
                    compact: true,
                    onPressed: () => onSelect(item),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatefulWidget {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.expanded,
    required this.onPressed,
    this.focusNode,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool expanded;
  final bool compact;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  State<_NavigationItem> createState() => _NavigationItemState();
}

class _NavigationItemState extends State<_NavigationItem> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final active = widget.selected;
    final color = active || _focused ? theme.accentBright : theme.textSecondary;
    final child = AnimatedContainer(
      width: double.infinity,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      constraints: BoxConstraints(minHeight: widget.compact ? 50 : 48),
      padding: EdgeInsets.symmetric(
        horizontal: widget.expanded && !widget.compact ? 12 : 4,
        vertical: widget.compact ? 3 : 8,
      ),
      decoration: BoxDecoration(
        color: active
            ? theme.accent.withValues(alpha: .13)
            : _hovered
                ? theme.textPrimary.withValues(alpha: .07)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(theme.radiusMedium),
        border: Border.all(
          color: _focused
              ? theme.accentBright.withValues(alpha: .8)
              : active
                  ? theme.accent.withValues(alpha: .22)
                  : Colors.transparent,
          width: _focused ? 2 : 1,
        ),
        boxShadow: _focused ? theme.accentGlow : const [],
      ),
      child: widget.compact
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: color, size: 21),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: widget.expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(widget.icon,
                    color: color, size: widget.expanded ? 22 : 20),
                if (widget.expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                ],
              ],
            ),
    );

    final item = Semantics(
      button: true,
      selected: active,
      label: widget.label,
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.onPressed,
        onFocusChange: (value) => setState(() => _focused = value),
        onHover: (value) => setState(() => _hovered = value),
        borderRadius: BorderRadius.circular(theme.radiusMedium),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: theme.accent.withValues(alpha: .12),
        child: child,
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.compact ? 0 : 3),
      child:
          widget.expanded ? item : Tooltip(message: widget.label, child: item),
    );
  }
}
