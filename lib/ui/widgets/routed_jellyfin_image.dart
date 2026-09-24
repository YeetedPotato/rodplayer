import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';

/// Keeps public image behavior unchanged and private image bytes on the routed
/// HTTP transport. A gateway rotation creates a fresh request, never a stale URL.
class RoutedJellyfinImage extends StatefulWidget {
  const RoutedJellyfinImage({
    required this.client,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.publicHeaders,
    this.filterQuality = FilterQuality.low,
    this.showFallbackWhileLoading = false,
    super.key,
  });

  final JellyfinApiClient client;
  final String url;
  final Widget fallback;
  final BoxFit fit;
  final Map<String, String>? publicHeaders;
  final FilterQuality filterQuality;
  final bool showFallbackWhileLoading;

  @override
  State<RoutedJellyfinImage> createState() => _RoutedJellyfinImageState();
}

class _RoutedJellyfinImageState extends State<RoutedJellyfinImage> {
  String? _requestKey;
  Future<Uint8List>? _bytes;
  ValueListenable<PrivateNetworkStatus?>? _observedStatus;

  @override
  void initState() {
    super.initState();
    _observeStatus();
  }

  @override
  void didUpdateWidget(RoutedJellyfinImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client || oldWidget.url != widget.url) {
      _requestKey = null;
      _bytes = null;
    }
    _observeStatus();
  }

  @override
  void dispose() {
    _observedStatus?.removeListener(_onStatusChanged);
    super.dispose();
  }

  void _observeStatus() {
    final next = widget.client.privateNetworkStatus;
    if (identical(next, _observedStatus)) return;
    _observedStatus?.removeListener(_onStatusChanged);
    _observedStatus = next;
    next?.addListener(_onStatusChanged);
    _requestKey = null;
    _bytes = null;
  }

  void _onStatusChanged() {
    if (_observedStatus?.value?.canProxy != true) {
      _requestKey = null;
      _bytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.client.privateNetworkStatus;
    if (status == null) {
      return Image.network(
        widget.url,
        fit: widget.fit,
        headers: widget.publicHeaders,
        filterQuality: widget.filterQuality,
        errorBuilder: (_, __, ___) => widget.fallback,
        loadingBuilder: widget.showFallbackWhileLoading
            ? (_, child, progress) => progress == null ? child : widget.fallback
            : null,
      );
    }
    return ValueListenableBuilder<PrivateNetworkStatus?>(
      valueListenable: status,
      builder: (context, current, _) {
        if (current?.canProxy != true) return widget.fallback;
        final key = '${current!.gatewayBaseUrl}|${widget.url}';
        if (_requestKey != key) {
          _requestKey = key;
          _bytes = widget.client.readServiceImage(Uri.parse(widget.url));
        }
        return FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) => snapshot.hasData
              ? Image.memory(snapshot.data!,
                  fit: widget.fit,
                  filterQuality: widget.filterQuality,
                  errorBuilder: (_, __, ___) => widget.fallback)
              : widget.fallback,
        );
      },
    );
  }
}
