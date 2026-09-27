import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/discovery/surprise_picker.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';
import 'package:rodplayer/ui/widgets/routed_jellyfin_image.dart';

Future<void> showSurpriseMePicker({
  required BuildContext context,
  required JellyfinApiClient client,
  DetailPlayItemCallback? onPlayItem,
  JellyfinUserDataChangedCallback? onUserDataChanged,
  Random? random,
}) {
  final compact = MediaQuery.sizeOf(context).width < 600;
  final picker = SurpriseMeDialog(
    client: client,
    bottomSheet: compact,
    onPlayItem: onPlayItem,
    onUserDataChanged: onUserDataChanged,
    random: random,
  );
  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => picker,
    );
  }
  return showDialog<void>(context: context, builder: (_) => picker);
}

class SurpriseMeDialog extends StatefulWidget {
  const SurpriseMeDialog({
    required this.client,
    this.bottomSheet = false,
    this.onPlayItem,
    this.onUserDataChanged,
    this.random,
    super.key,
  });

  final JellyfinApiClient client;
  final bool bottomSheet;
  final DetailPlayItemCallback? onPlayItem;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final Random? random;

  @override
  State<SurpriseMeDialog> createState() => _SurpriseMeDialogState();
}

class _SurpriseMeDialogState extends State<SurpriseMeDialog> {
  late final SurprisePicker _picker = SurprisePicker(
    client: widget.client,
    random: widget.random,
  );
  final Map<SurpriseMode, Set<String>> _seen = {};
  SurpriseMode _mode = SurpriseMode.unwatchedMovies;
  JellyfinLibraryItem? _item;
  bool _loading = false;
  bool _exhausted = false;
  bool _failed = false;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_pick());
  }

  Future<void> _pick() async {
    if (_loading) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _failed = false;
      _exhausted = false;
    });
    try {
      final item = await _picker.pick(
        mode: _mode,
        excludedItemIds: _seen.putIfAbsent(_mode, () => <String>{}),
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _item = item;
        _loading = false;
        _exhausted = item == null;
        if (item != null) _seen[_mode]!.add(item.id);
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _item = null;
        _loading = false;
        _failed = true;
      });
    }
  }

  void _selectMode(SurpriseMode? value) {
    if (value == null || value == _mode) return;
    setState(() {
      _mode = value;
      _item = null;
      _loading = false;
    });
    unawaited(_pick());
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final isLight = Theme.of(context).brightness == Brightness.light;
    final outlineForeground = isLight ? theme.accentDeep : theme.accentBright;
    final item = _item;
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Text('Surprise Me',
                      style: Theme.of(context).textTheme.headlineSmall)),
              IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<SurpriseMode>(
              initialValue: _mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pick from'),
              items: <DropdownMenuItem<SurpriseMode>>[
                for (final mode in SurpriseMode.values)
                  DropdownMenuItem<SurpriseMode>(
                      value: mode,
                      child: Text(
                        mode.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
              ],
              onChanged: _selectMode,
            ),
            const SizedBox(height: 20),
            if (_loading)
              const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()))
            else if (_failed)
              SizedBox(
                  height: 150,
                  child: Center(
                      child: Text('Could not choose an item right now.',
                          style: TextStyle(color: theme.textSecondary))))
            else if (_exhausted)
              SizedBox(
                  height: 150,
                  child: Center(
                      child: Text('No more items are available in this group.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.textSecondary))))
            else if (item != null)
              _SurpriseItemPreview(client: widget.client, item: item),
            const SizedBox(height: 20),
            Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: outlineForeground,
                      side: BorderSide(
                          color: outlineForeground.withValues(alpha: .65)),
                    ),
                    onPressed: _loading ? null : () => unawaited(_pick()),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Another'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: outlineForeground,
                      side: BorderSide(
                          color: outlineForeground.withValues(alpha: .65)),
                    ),
                    onPressed: item == null ? null : _openDetails,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Details'),
                  ),
                  if (item != null && isDirectlyPlayable(item) && widget.onPlayItem != null)
                    FilledButton.icon(
                      onPressed: () => widget.onPlayItem!(context, item.id),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                ]),
          ]),
    );
    if (widget.bottomSheet) {
      return Material(
        color: theme.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            return SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 680),
                child: content,
              ),
            );
          }),
        ),
      );
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: content,
      ),
    );
  }

  void _openDetails() {
    final item = _item;
    if (item == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ItemDetailsScreen(
        client: widget.client,
        itemId: item.id,
        onPlayItem: widget.onPlayItem,
        onUserDataChanged: widget.onUserDataChanged,
      ),
    ));
  }
}

class _SurpriseItemPreview extends StatelessWidget {
  const _SurpriseItemPreview({required this.client, required this.item});

  final JellyfinApiClient client;
  final JellyfinLibraryItem item;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final imageUrl = item.imageUrl(client.baseUrl);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 88,
        height: 132,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(theme.radiusMedium),
          child: imageUrl == null
              ? ColoredBox(
                  color: theme.surface3,
                  child: Icon(Icons.movie_outlined, color: theme.textMuted))
              : RoutedJellyfinImage(
                  client: client,
                  url: imageUrl,
                  fit: BoxFit.cover,
                  fallback: ColoredBox(color: theme.surface3)),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mediaItemTitle(item),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(item.subtitle(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textSecondary)),
          if (item.overview?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(item.overview!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textSecondary)),
          ],
        ]),
      ),
    ]);
  }
}
