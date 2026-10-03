import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/events/jellyfin_server_events.dart';
import 'package:rodplayer/core/events/jellyfin_websocket_event_connector.dart';

typedef ServerEventSessionBuilder = JellyfinServerEventSessionController
    Function({
  required JellyfinApiClient client,
  required bool Function() isCurrent,
  required ServerEventInvalidationHandler onLibraryInvalidated,
  required ServerEventInvalidationHandler onUserDataInvalidated,
  required ServerItemInvalidationHandler onItemsInvalidated,
});

/// Composes one Jellyfin event connection from the authenticated client that
/// owns the matching HTTP service transport. The transport remains the only
/// authority that resolves direct/private service routing.
JellyfinServerEventSessionController createJellyfinServerEventSession({
  required JellyfinApiClient client,
  required bool Function() isCurrent,
  required ServerEventInvalidationHandler onLibraryInvalidated,
  required ServerEventInvalidationHandler onUserDataInvalidated,
  required ServerItemInvalidationHandler onItemsInvalidated,
}) {
  final token = client.accessToken;
  final userId = client.userId;
  ServerEventSource source;
  if (token == null || userId == null || token.isEmpty || userId.isEmpty) {
    source = const UnsupportedServerEventSource();
  } else {
    try {
      source = ReconnectingJellyfinServerEventSource(
        connector: JellyfinWebSocketEventConnector(
          baseUrl: client.baseUrl,
          accessToken: token,
          userId: userId,
          deviceId: client.identity.deviceId,
          transport: client.serviceTransport,
        ),
      );
    } on Object {
      // Optional event support cannot make an otherwise valid session fail.
      source = const UnsupportedServerEventSource();
    }
  }
  return JellyfinServerEventSessionController(
    source: source,
    isCurrent: isCurrent,
    onLibraryInvalidated: onLibraryInvalidated,
    onUserDataInvalidated: onUserDataInvalidated,
    onItemsInvalidated: onItemsInvalidated,
  );
}
