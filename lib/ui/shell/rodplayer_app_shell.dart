import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/home_library_views.dart';

class RodPlayerAppShell extends StatefulWidget {
  const RodPlayerAppShell({
    required this.client,
    required this.onLogout,
    required this.onSwitchProfile,
    this.appearanceController,
    this.serverEventRevision,
    super.key,
  });
  final JellyfinApiClient client;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSwitchProfile;
  final AppearanceController? appearanceController;
  final ValueListenable<int>? serverEventRevision;

  @override
  State<RodPlayerAppShell> createState() => _RodPlayerAppShellState();
}

class _RodPlayerAppShellState extends State<RodPlayerAppShell> {
  RodPlayerDestination _destination = RodPlayerDestination.home;
  bool? _expandedOverride;
  bool _librariesExpanded = false;
  int _primaryLibraryScopeRevision = 0;
  HomeShelfPreferences _homeShelfPreferences = HomeShelfPreferences.defaults;
  late final Map<RodPlayerDestination, FocusNode> _destinationFocusNodes = {
    for (final destination in RodPlayerDestination.values)
      destination: FocusNode(debugLabel: destination.title),
  };
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'RodPlayer search');
  JellyfinUserDataChange? _latestUserDataChange;
  int _userDataRevision = 0;
  List<JellyfinLibraryItem> _libraries = const <JellyfinLibraryItem>[];
  String? _selectedLibraryId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLibraries());
    unawaited(_loadLibrariesExpanded());
    unawaited(_loadHomeShelfPreferences());
  }

  @override
  void didUpdateWidget(covariant RodPlayerAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _selectedLibraryId = null;
      unawaited(_loadLibraries());
    }
  }

  Future<void> _loadLibraries() async {
    final client = widget.client;
    try {
      final libraries = await client.getUserViews();
      if (mounted && identical(client, widget.client))
        setState(() => _libraries = supportedLibraryViews(libraries));
    } on Object {
      if (mounted && identical(client, widget.client))
        setState(() => _libraries = const <JellyfinLibraryItem>[]);
    }
  }

  Future<void> _loadLibrariesExpanded() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final expanded = preferences.getBool(
        'nautilus.sidebar.librariesExpanded',
      );
      if (mounted && expanded != null) {
        setState(() => _librariesExpanded = expanded);
      }
    } on Object {
      // A missing preference keeps the default expanded section.
    }
  }

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

  Future<void> _toggleLibraries() async {
    final expanded = !_librariesExpanded;
    setState(() => _librariesExpanded = expanded);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('nautilus.sidebar.librariesExpanded', expanded);
    } on Object {
      // The current session still honors the user's toggle.
    }
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
    setState(() {
      _selectedLibraryId = null;
      _destination = destination;
      if (destination == RodPlayerDestination.movies ||
          destination == RodPlayerDestination.tvShows) {
        _primaryLibraryScopeRevision++;
      }
    });
    if (focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _openLibrary(JellyfinLibraryItem library) {
    if (library.id.isEmpty) return;
    setState(() => _selectedLibraryId = library.id);
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

  Future<void> _playItem(BuildContext routeContext, String itemId) =>
      _playItemAndRefresh(routeContext, itemId);

  Future<void> _resumeItem(
    BuildContext routeContext,
    String itemId,
    Duration startPosition,
  ) => _playItemAndRefresh(routeContext, itemId, startPosition: startPosition);

  Future<void> _playItemAndRefresh(
    BuildContext routeContext,
    String itemId, {
    Duration startPosition = Duration.zero,
  }) async {
    await Navigator.of(routeContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlayerRoute(
          client: widget.client,
          itemId: itemId,
          startPosition: startPosition,
          onUserDataChanged: _onUserDataChanged,
        ),
      ),
    );
    if (!mounted) return;
    _onUserDataChanged(
      JellyfinUserDataChange(
        itemId: itemId,
        playbackProgressMayHaveChanged: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final media = MediaQuery.of(context);
    final directional = media.navigationMode == NavigationMode.directional;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _select(RodPlayerDestination.search, focusSearch: true),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _select(RodPlayerDestination.search, focusSearch: true),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleDirectionalKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720 && !directional;
            final expanded =
                directional ||
                (_expandedOverride ?? constraints.maxWidth >= 1100);
            final matchingLibraries = _libraries.where(
              (view) => view.id == _selectedLibraryId,
            );
            final selectedLibrary = matchingLibraries.isEmpty
                ? null
                : matchingLibraries.first;
            final body = IndexedStack(
              index: selectedLibrary == null
                  ? RodPlayerDestination.values.indexOf(_destination)
                  : RodPlayerDestination.values.length,
              children: [
                HomeScreen(
                  client: widget.client,
                  onPlayItem: _playItem,
                  onResumeItem: _resumeItem,
                  serverDataRevision: widget.serverEventRevision,
                  userDataRevision: _userDataRevision,
                  latestUserDataChange: _latestUserDataChange,
                  homeShelfPreferences: _homeShelfPreferences,
                  libraries: _libraries,
                  onOpenLibrary: _openLibrary,
                  onUserDataChanged: _onUserDataChanged,
                ),
                MediaLibraryScreen(
                  client: widget.client,
                  kind: JellyfinLibraryKind.movies,
                  scopeResetRevision: _primaryLibraryScopeRevision,
                  libraries: _libraries,
                  onPlayItem: _playItem,
                  onResumeItem: _resumeItem,
                  serverDataRevision: widget.serverEventRevision,
                  userDataRevision: _userDataRevision,
                  latestUserDataChange: _latestUserDataChange,
                  onUserDataChanged: _onUserDataChanged,
                ),
                MediaLibraryScreen(
                  client: widget.client,
                  kind: JellyfinLibraryKind.tvShows,
                  scopeResetRevision: _primaryLibraryScopeRevision,
                  libraries: _libraries,
                  onPlayItem: _playItem,
                  onResumeItem: _resumeItem,
                  serverDataRevision: widget.serverEventRevision,
                  userDataRevision: _userDataRevision,
                  latestUserDataChange: _latestUserDataChange,
                  onUserDataChanged: _onUserDataChanged,
                ),
                DiscoverScreen(
                  client: widget.client,
                  active: _destination == RodPlayerDestination.discover,
                  onPlayItem: _playItem,
                  onResumeItem: _resumeItem,
                  serverDataRevision: widget.serverEventRevision,
                  userDataRevision: _userDataRevision,
                  latestUserDataChange: _latestUserDataChange,
                  onUserDataChanged: _onUserDataChanged,
                ),
                SearchScreen(
                  client: widget.client,
                  embedded: true,
                  focusNode: _searchFocusNode,
                  autofocus: false,
                  onEscape: () =>
                      _destinationFocusNodes[RodPlayerDestination.search]
                          ?.requestFocus(),
                  onPlayItem: _playItem,
                  onResumeItem: _resumeItem,
                  serverDataRevision: widget.serverEventRevision,
                  userDataRevision: _userDataRevision,
                  latestUserDataChange: _latestUserDataChange,
                  onUserDataChanged: _onUserDataChanged,
                ),
                if (selectedLibrary != null)
                  MediaLibraryScreen(
                    key: ValueKey<String>('library:${selectedLibrary.id}'),
                    client: widget.client,
                    kind: null,
                    libraryId: selectedLibrary.id,
                    libraryName: selectedLibrary.title,
                    onPlayItem: _playItem,
                    onResumeItem: _resumeItem,
                    serverDataRevision: widget.serverEventRevision,
                    userDataRevision: _userDataRevision,
                    latestUserDataChange: _latestUserDataChange,
                    onUserDataChanged: _onUserDataChanged,
                  )
                else
                  const SizedBox.shrink(),
              ],
            );
            if (compact) {
              return Scaffold(
                backgroundColor: theme.obsidian,
                appBar: AppBar(
                  title: Text(_destination.title),
                  actions: [
                    IconButton(
                      tooltip: 'Discover',
                      onPressed: () => _select(RodPlayerDestination.discover),
                      icon: Icon(
                        _destination == RodPlayerDestination.discover
                            ? Icons.explore
                            : Icons.explore_outlined,
                      ),
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
                        libraries: _libraries,
                        librariesExpanded: _librariesExpanded,
                        onToggleLibraries: () => unawaited(_toggleLibraries()),
                        selectedLibraryId: _selectedLibraryId,
                        onSelectLibrary: _openLibrary,
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
          },
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onLogout});
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Log out',
    onPressed: onLogout,
    icon: const Icon(Icons.logout),
  );
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Profile',
    onPressed: onPressed,
    icon: const Icon(Icons.account_circle_outlined),
  );
}
