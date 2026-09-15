import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/home_screen.dart';
import 'package:rodplayer/ui/screens/search_screen.dart';

class RodPlayerAppShell extends StatefulWidget {
  const RodPlayerAppShell({required this.client, required this.onLogout, super.key});
  final JellyfinApiClient client;
  final Future<void> Function() onLogout;

  @override
  State<RodPlayerAppShell> createState() => _RodPlayerAppShellState();
}

class _RodPlayerAppShellState extends State<RodPlayerAppShell> {
  int _index = 0;
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'RodPlayer search');

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _select(int index, {bool focusSearch = false}) {
    setState(() => _index = index);
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
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _select(1, focusSearch: true),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _select(1, focusSearch: true),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 720 && !directional;
          final body = IndexedStack(index: _index, children: [
            HomeScreen(client: widget.client),
            SearchScreen(client: widget.client, embedded: true, focusNode: _searchFocusNode, autofocus: false),
          ]);
          if (compact) {
            return Scaffold(
              backgroundColor: theme.obsidian,
              appBar: AppBar(title: Text(_title), actions: [_LogoutButton(onLogout: widget.onLogout)]),
              body: SafeArea(bottom: false, child: body),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (index) => _select(index),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
                ],
              ),
            );
          }
          return Scaffold(
            backgroundColor: theme.obsidian,
            body: SafeArea(
              child: Row(children: [
                _SideNav(selectedIndex: _index, directional: directional, onSelect: (index) => _select(index), onLogout: widget.onLogout),
                Expanded(child: body),
              ]),
            ),
          );
        }),
      ),
    );
  }

  String get _title => _index == 0 ? 'Home' : 'Search';
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.selectedIndex, required this.directional, required this.onSelect, required this.onLogout});
  final int selectedIndex;
  final bool directional;
  final ValueChanged<int> onSelect;
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
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelect,
              extended: directional,
              labelType: directional ? null : NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: Text('Home')),
                NavigationRailDestination(icon: Icon(Icons.search), label: Text('Search')),
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
