import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/home_screen.dart';
import 'package:rodplayer/ui/screens/media_library_screen.dart';
import 'package:rodplayer/ui/screens/search_screen.dart';

enum RodPlayerDestination {
  home('Home', 'Home', Icons.home_outlined, Icons.home),
  movies('Movies', 'Movies', Icons.movie_outlined, Icons.movie),
  tvShows('TV Shows', 'TV', Icons.tv_outlined, Icons.tv),
  search('Search', 'Search', Icons.search, Icons.search);

  const RodPlayerDestination(this.title, this.compactLabel, this.icon, this.selectedIcon);
  final String title;
  final String compactLabel;
  final IconData icon;
  final IconData selectedIcon;
}

class RodPlayerAppShell extends StatefulWidget {
  const RodPlayerAppShell({required this.client, required this.onLogout, super.key});
  final JellyfinApiClient client;
  final Future<void> Function() onLogout;

  @override
  State<RodPlayerAppShell> createState() => _RodPlayerAppShellState();
}

class _RodPlayerAppShellState extends State<RodPlayerAppShell> {
  RodPlayerDestination _destination = RodPlayerDestination.home;
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'RodPlayer search');

  @override
  void dispose() {
    _searchFocusNode.dispose();
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
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 720 && !directional;
          final body = IndexedStack(index: RodPlayerDestination.values.indexOf(_destination), children: [
            HomeScreen(client: widget.client),
            MediaLibraryScreen(client: widget.client, kind: JellyfinLibraryKind.movies),
            MediaLibraryScreen(client: widget.client, kind: JellyfinLibraryKind.tvShows),
            SearchScreen(client: widget.client, embedded: true, focusNode: _searchFocusNode, autofocus: false),
          ]);
          if (compact) {
            return Scaffold(
              backgroundColor: theme.obsidian,
              appBar: AppBar(title: Text(_destination.title), actions: [_LogoutButton(onLogout: widget.onLogout)]),
              body: SafeArea(bottom: false, child: body),
              bottomNavigationBar: NavigationBar(
                selectedIndex: RodPlayerDestination.values.indexOf(_destination),
                onDestinationSelected: (index) => _select(RodPlayerDestination.values[index]),
                destinations: [
                  for (final destination in RodPlayerDestination.values) NavigationDestination(icon: Icon(destination.icon), selectedIcon: Icon(destination.selectedIcon), label: destination.compactLabel),
                ],
              ),
            );
          }
          return Scaffold(
            backgroundColor: theme.obsidian,
            body: SafeArea(
              child: Row(children: [
                _SideNav(destination: _destination, directional: directional, onSelect: _select, onLogout: widget.onLogout),
                Expanded(child: body),
              ]),
            ),
          );
        }),
      ),
    );
  }

}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.destination, required this.directional, required this.onSelect, required this.onLogout});
  final RodPlayerDestination destination;
  final bool directional;
  final ValueChanged<RodPlayerDestination> onSelect;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.surface1, border: Border(right: BorderSide(color: theme.borderColor(0.1)))),
      child: SizedBox(
        width: directional ? 188 : 118,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 22, 16, 18), child: Text('RodPlayer', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.goldBright, fontWeight: FontWeight.w800))),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: RodPlayerDestination.values.indexOf(destination),
              onDestinationSelected: (index) => onSelect(RodPlayerDestination.values[index]),
              extended: directional,
              labelType: directional ? null : NavigationRailLabelType.all,
              destinations: [
                for (final destination in RodPlayerDestination.values) NavigationRailDestination(icon: Icon(destination.icon), selectedIcon: Icon(destination.selectedIcon), label: Text(destination.title)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: _LogoutButton(onLogout: onLogout)),
        ]),
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
