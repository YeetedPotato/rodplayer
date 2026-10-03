import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/core/theme/appearance_controller.dart';
import 'package:rodplayer/ui/screens/home_screen.dart';
import 'package:rodplayer/ui/screens/discover_screen.dart';
import 'package:rodplayer/ui/screens/media_library_screen.dart';
import 'package:rodplayer/ui/screens/profile_screen.dart';
import 'package:rodplayer/ui/screens/search_screen.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/shell/nautilus_navigation.dart';

class RodPlayerAppShell extends StatefulWidget {
  const RodPlayerAppShell({required this.client, required this.onLogout, required this.onSwitchProfile, this.appearanceController, super.key});
  final JellyfinApiClient client;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSwitchProfile;
  final AppearanceController? appearanceController;

  @override
  State<RodPlayerAppShell> createState() => _RodPlayerAppShellState();
}

class _RodPlayerAppShellState extends State<RodPlayerAppShell> {
  RodPlayerDestination _destination = RodPlayerDestination.home;
  HomeShelfPreferences _homeShelfPreferences = HomeShelfPreferences.defaults;
  bool? _expandedOverride;
  late final Map<RodPlayerDestination, FocusNode> _destinationFocusNodes = {
    for (final destination in RodPlayerDestination.values)
      destination: FocusNode(debugLabel: destination.title),
  };
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'RodPlayer search');
  JellyfinUserDataChange? _latestUserDataChange;
  int _userDataRevision = 0;

  Future<void> _loadHomeShelfPreferences() async {
    try {
      final preferences = await HomeShelfPreferences.load();
      if (mounted) setState(() => _homeShelfPreferences = preferences);
    } on Object {
      // Default Home order remains usable if local preferences are unavailable.
    }
  }

  void _onHomeShelfPreferencesChanged(HomeShelfPreferences preferences) {
    if (mounted) setState(() => _homeShelfPreferences = preferences);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    for (final focusNode in _destinationFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _select(RodPlayerDestination destination, {bool focusSearch = false}) {
    setState(() => _destination = destination);
    if (focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  KeyEventResult _handleDirectionalKey(FocusNode node, KeyEvent event) {
    final context = node.context;
    if (context == null ||
        MediaQuery.of(context).navigationMode != NavigationMode.directional ||
        event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;

    final focused = FocusManager.instance.primaryFocus;
    if (Navigator.of(context).canPop() ||
        identical(focused, _searchFocusNode)) {
      return KeyEventResult.ignored;
    }
    final focusContext = focused?.context;
    final inSidebar =
        focusContext?.findAncestorWidgetOfExactType<NautilusSideNavigation>() !=
            null;
    if (focused != null && direction == TraversalDirection.right && inSidebar) {
      focused.focusInDirection(direction);
      return KeyEventResult.handled;
    }
    if (direction == TraversalDirection.left && !inSidebar) {
      _destinationFocusNodes[_destination]?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          client: widget.client,
          onSwitchProfile: widget.onSwitchProfile,
          onLogout: widget.onLogout,
          appearanceController: widget.appearanceController,
          onHomeShelfPreferencesChanged: _onHomeShelfPreferencesChanged,
        ),
      ),
    );
  }

  void _onUserDataChanged(JellyfinUserDataChange change) {
    setState(() {
      _latestUserDataChange = change;
      _userDataRevision++;
    });
  }

  void _playItem(BuildContext routeContext, String itemId) {
    unawaited(_playItemAndRefresh(routeContext, itemId));
  }

  Future<void> _playItemAndRefresh(
      BuildContext routeContext, String itemId) async {
    await Navigator.of(routeContext).push<void>(MaterialPageRoute<void>(
      builder: (_) => PlayerRoute(client: widget.client, itemId: itemId),
    ));
    if (!mounted) return;
    _onUserDataChanged(JellyfinUserDataChange(
      itemId: itemId,
      playbackProgressMayHaveChanged: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final media = MediaQuery.of(context);
    final directional = media.navigationMode == NavigationMode.directional;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _select(RodPlayerDestination.search, focusSearch: true),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _select(RodPlayerDestination.search, focusSearch: true),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleDirectionalKey,
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 720 && !directional;
          final expanded = directional ||
              (_expandedOverride ?? constraints.maxWidth >= 1100);
          final body = IndexedStack(index: RodPlayerDestination.values.indexOf(_destination), children: [
            HomeScreen(client: widget.client, userDataRevision: _userDataRevision, latestUserDataChange: _latestUserDataChange, onUserDataChanged: _onUserDataChanged),
            MediaLibraryScreen(client: widget.client, kind: JellyfinLibraryKind.movies, userDataRevision: _userDataRevision, latestUserDataChange: _latestUserDataChange, onUserDataChanged: _onUserDataChanged),
            MediaLibraryScreen(client: widget.client, kind: JellyfinLibraryKind.tvShows, userDataRevision: _userDataRevision, latestUserDataChange: _latestUserDataChange, onUserDataChanged: _onUserDataChanged),
            DiscoverScreen(client: widget.client, active: _destination == RodPlayerDestination.discover, onPlayItem: _playItem, userDataRevision: _userDataRevision, latestUserDataChange: _latestUserDataChange, onUserDataChanged: _onUserDataChanged),
            SearchScreen(client: widget.client, embedded: true, focusNode: _searchFocusNode, autofocus: false, userDataRevision: _userDataRevision, latestUserDataChange: _latestUserDataChange, onUserDataChanged: _onUserDataChanged),
          ]);
          if (compact) {
            return Scaffold(
              backgroundColor: theme.obsidian,
              appBar: AppBar(
                title: Text(_destination.title),
                actions: [
                  IconButton(
                    tooltip: 'Discover',
                    onPressed: () => _select(RodPlayerDestination.discover),
                    icon: Icon(_destination == RodPlayerDestination.discover
                        ? Icons.explore
                        : Icons.explore_outlined),
                  ),
                  _ProfileButton(onPressed: _openProfile),
                  _LogoutButton(onLogout: widget.onLogout),
                ],
              ),
              body: SafeArea(bottom: false, child: body),
              bottomNavigationBar: NautilusBottomNavigation(
                destination: _destination,
                onSelect: _select,
              ),
            );
          }
          return Scaffold(
            backgroundColor: theme.obsidian,
            body: SafeArea(
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: NautilusSideNavigation(
                      destination: _destination,
                      focusNodes: _destinationFocusNodes,
                      expanded: expanded,
                      canCollapse: !directional,
                      onToggleExpanded: () => setState(() {
                        _expandedOverride = !expanded;
                      }),
                      onSelect: _select,
                      onProfile: _openProfile,
                      onLogout: () => unawaited(widget.onLogout()),
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          );
          }),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onLogout});
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => IconButton(tooltip: 'Log out', onPressed: onLogout, icon: const Icon(Icons.logout));
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(tooltip: 'Profile', onPressed: onPressed, icon: const Icon(Icons.account_circle_outlined));
}
