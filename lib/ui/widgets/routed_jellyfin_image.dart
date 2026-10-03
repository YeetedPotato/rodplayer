import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';

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
  Listenable? _observedEndpointChanges;

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
    _observedEndpointChanges?.removeListener(_onEndpointChanged);
    super.dispose();
  }

  void _observeStatus() {
    final next = widget.client.serviceTransport.endpointChanges;
    if (identical(next, _observedEndpointChanges)) return;
    _observedEndpointChanges?.removeListener(_onEndpointChanged);
    _observedEndpointChanges = next;
    next?.addListener(_onEndpointChanged);
    _requestKey = null;
    _bytes = null;
  }

  void _onEndpointChanged() {
    // Keep a completed/in-flight request when the endpoint did not change.
    // This signal can also fire for status-only transitions such as repeated
    // ready notifications.
    if (_currentRequestKey() != _requestKey) {
      _requestKey = null;
      _bytes = null;
    }
  }

  String? _currentRequestKey() {
    final canonical = Uri.tryParse(widget.url);
    if (canonical == null) return null;
    try {
      return '${widget.client.resolveServiceUri(canonical)}|${widget.url}';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.client.serviceTransport.endpointChanges == null) {
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
    return _buildPrivateImage();
  }

  Widget _buildPrivateImage() {
    final endpointChanges = _observedEndpointChanges;
    if (endpointChanges != null) {
      return ListenableBuilder(
        listenable: endpointChanges,
        builder: (context, _) => _privateImageContent(),
      );
    }
    return _privateImageContent();
  }

  Widget _privateImageContent() {
    final canonical = Uri.tryParse(widget.url);
    if (canonical == null) return widget.fallback;
    final Uri routed;
    try {
      routed = widget.client.resolveServiceUri(canonical);
    } catch (_) {
      return widget.fallback;
    }
    final key = '$routed|${widget.url}';
    if (_requestKey != key) {
      _requestKey = key;
      _bytes = widget.client.readServiceImage(canonical);
    }
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) => snapshot.hasData
          ? Image.memory(
              snapshot.data!,
              fit: widget.fit,
              filterQuality: widget.filterQuality,
              errorBuilder: (_, __, ___) => widget.fallback,
            )
          : widget.fallback,
    );
  }
}
