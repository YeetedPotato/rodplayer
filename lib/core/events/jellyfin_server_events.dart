import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

enum ServerEventsSupport { supported, unsupported, unknown }

enum JellyfinServerEventKind {
  libraryInvalidated,
  userDataInvalidated,
  itemInvalidated,
}

/// Normalized invalidation signal. Raw socket JSON and auth headers never
/// escape the transport adapter.
final class JellyfinServerEvent {
  const JellyfinServerEvent({
    required this.kind,
    this.itemIds = const <String>{},
  });

  final JellyfinServerEventKind kind;
  final Set<String> itemIds;
}

/// Converts the small set of known Jellyfin notification envelopes into
/// invalidation signals. It never returns server payloads or exception text.
/// Unknown protocol messages (including keepalive frames) are ignored so a
/// connector can handle transport control independently.
JellyfinServerEvent? normalizeJellyfinEventFrame(
  Object? frame, {
  required String authenticatedUserId,
}) {
  if (authenticatedUserId.trim().isEmpty) return null;
  Object? decoded;
  try {
    if (frame is String) {
      decoded = jsonDecode(frame);
    } else if (frame is List<int>) {
      decoded = jsonDecode(utf8.decode(frame));
    } else {
      return null;
    }
  } on Object {
    return null;
  }
  if (decoded is! Map || decoded['MessageType'] is! String) return null;
  final data = decoded['Data'];
  switch (decoded['MessageType']) {
    case 'LibraryChanged':
      if (data is! Map) return null;
      return const JellyfinServerEvent(
        kind: JellyfinServerEventKind.libraryInvalidated,
      );
    case 'UserDataChanged':
      if (data is! Map) return null;
      final userId = data['UserId'];
      if (userId != null && userId is! String) return null;
      if (userId is String && userId != authenticatedUserId) return null;
      return const JellyfinServerEvent(
        kind: JellyfinServerEventKind.userDataInvalidated,
      );
    default:
      return null;
  }
}

abstract interface class ServerEventSource {
  ServerEventsSupport get support;
  Stream<JellyfinServerEvent> get events;
  Future<void> close();
}

enum ServerEventConnectionState {
  connecting,
  connected,
  reconnecting,
  unsupported,
  failed,
  closed,
}

abstract interface class ServerEventWireConnection {
  Stream<JellyfinServerEvent> get events;
  Future<void> close();
}

/// Connector implementations must use the account's authenticated service
/// transport/resolver and must fail closed if that transport cannot provide a
/// websocket. This lifecycle never constructs a socket URL or public fallback.
abstract interface class ServerEventConnector {
  Future<ServerEventWireConnection> connect({
    ServerEventConnectionCancellation? cancellation,
  });
}

/// Cancellation for an in-flight handshake. Session teardown completes this
/// before dropping its credentials, allowing connectors to stop pending work.
final class ServerEventConnectionCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class ServerEventConnectionCancelled implements Exception {
  const ServerEventConnectionCancelled();
}

final class ServerEventTransportUnsupported implements Exception {
  const ServerEventTransportUnsupported();
}

/// Authentication rejection is terminal for this source instance; retrying the
/// same credentials would only create a reconnect loop.
final class ServerEventAuthenticationFailure implements Exception {
  const ServerEventAuthenticationFailure();
}

/// Bounded reconnect lifecycle around an injected, policy-aware connector.
/// Protocol framing/keepalive remains the connector's responsibility.
final class ReconnectingJellyfinServerEventSource implements ServerEventSource {
  ReconnectingJellyfinServerEventSource({
    required this.connector,
    this.maxAttempts = 5,
    this.retryDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(seconds: 60),
    this.stableConnectionDuration = const Duration(seconds: 30),
    Future<void> Function(Duration)? wait,
    Duration Function()? monotonicNow,
    double Function()? jitter,
  })  : _wait = wait ?? ((duration) => Future<void>.delayed(duration)),
        _monotonicNow = monotonicNow,
        _jitter = jitter ?? math.Random().nextDouble {
    if (maxAttempts < 1 ||
        retryDelay.isNegative ||
        maxRetryDelay < retryDelay ||
        stableConnectionDuration.isNegative)
      throw ArgumentError('Invalid event reconnect bounds');
    start();
  }

  final ServerEventConnector connector;
  final int maxAttempts;
  final Duration retryDelay;
  final Duration maxRetryDelay;
  final Duration stableConnectionDuration;
  final Future<void> Function(Duration) _wait;
  final Duration Function()? _monotonicNow;
  final double Function() _jitter;
  final Stopwatch _stopwatch = Stopwatch()..start();
  final StreamController<JellyfinServerEvent> _events =
      StreamController<JellyfinServerEvent>.broadcast();
  StreamSubscription<JellyfinServerEvent>? _subscription;
  ServerEventWireConnection? _connection;
  int _generation = 0;
  int? _endingGeneration;
  int _attempts = 0;
  bool _closed = false;
  ServerEventConnectionCancellation? _connectingCancellation;
  ServerEventConnectionState _state = ServerEventConnectionState.connecting;
  Duration? _connectedAt;

  Duration get _now => _monotonicNow?.call() ?? _stopwatch.elapsed;

  ServerEventConnectionState get state => _state;
  @override
  ServerEventsSupport get support => switch (_state) {
        ServerEventConnectionState.connected => ServerEventsSupport.supported,
        ServerEventConnectionState.unsupported =>
          ServerEventsSupport.unsupported,
        ServerEventConnectionState.failed ||
        ServerEventConnectionState.closed =>
          ServerEventsSupport.unknown,
        _ => ServerEventsSupport.unknown,
      };
  @override
  Stream<JellyfinServerEvent> get events => _events.stream;

  void start() {
    if (!_closed && _state != ServerEventConnectionState.connected) {
      _connectingCancellation?.cancel();
      final generation = ++_generation;
      _attempts = 0;
      unawaited(_connect(generation));
    }
  }

  Future<void> _connect(int generation) async {
    while (!_closed && generation == _generation && _attempts < maxAttempts) {
      _attempts++;
      final cancellation = ServerEventConnectionCancellation();
      _connectingCancellation = cancellation;
      try {
        final connection = await connector.connect(cancellation: cancellation);
        if (identical(_connectingCancellation, cancellation)) {
          _connectingCancellation = null;
        }
        if (_closed || generation != _generation) {
          await connection.close();
          return;
        }
        _connection = connection;
        _connectedAt = _now;
        _state = ServerEventConnectionState.connected;
        _subscription = connection.events.listen(
          (event) {
            if (!_closed && generation == _generation) _events.add(event);
          },
          onError: (Object _) => unawaited(_connectionEnded(generation)),
          onDone: () => unawaited(_connectionEnded(generation)),
          cancelOnError: true,
        );
        return;
      } on ServerEventConnectionCancelled {
        if (identical(_connectingCancellation, cancellation)) {
          _connectingCancellation = null;
        }
        if (_closed || generation != _generation) return;
      } on ServerEventTransportUnsupported {
        if (identical(_connectingCancellation, cancellation)) {
          _connectingCancellation = null;
        }
        if (_closed || generation != _generation) return;
        _state = ServerEventConnectionState.unsupported;
        return;
      } on ServerEventAuthenticationFailure {
        if (identical(_connectingCancellation, cancellation)) {
          _connectingCancellation = null;
        }
        if (_closed || generation != _generation) return;
        _state = ServerEventConnectionState.failed;
        return;
      } on Object {
        if (identical(_connectingCancellation, cancellation)) {
          _connectingCancellation = null;
        }
        if (_closed || generation != _generation) return;
        // No exception text is retained; reconnect is bounded and silent.
      }
      if (_attempts < maxAttempts && !_closed && generation == _generation) {
        _state = ServerEventConnectionState.reconnecting;
        await _wait(_delayForAttempt(_attempts));
      }
    }
    if (!_closed && generation == _generation)
      _state = ServerEventConnectionState.failed;
  }

  Future<void> _connectionEnded(int generation) async {
    if (_closed || generation != _generation || _endingGeneration == generation)
      return;
    _endingGeneration = generation;
    try {
      await _subscription?.cancel();
    } on Object {
      // Stream cancellation failure must not prevent state recovery.
    }
    _subscription = null;
    final connection = _connection;
    _connection = null;
    try {
      await connection?.close();
    } on Object {
      // A close failure must not prevent a bounded reconnect attempt.
    }
    if (_closed || generation != _generation) return;
    final connectedAt = _connectedAt;
    _connectedAt = null;
    if (connectedAt != null && _now - connectedAt >= stableConnectionDuration) {
      _attempts = 0;
    }
    if (_attempts >= maxAttempts) {
      _state = ServerEventConnectionState.failed;
      _endingGeneration = null;
      return;
    }
    _state = ServerEventConnectionState.reconnecting;
    final nextGeneration = ++_generation;
    _endingGeneration = null;
    unawaited(_reconnect(nextGeneration));
  }

  Future<void> _reconnect(int generation) async {
    await _wait(_delayForAttempt(_attempts));
    if (_closed || generation != _generation) return;
    await _connect(generation);
  }

  Duration _delayForAttempt(int attempt) {
    final exponent = math.max(0, math.min(attempt - 1, 30));
    final baseMicros = retryDelay.inMicroseconds * (1 << exponent);
    final boundedMicros = math.min(baseMicros, maxRetryDelay.inMicroseconds);
    final suppliedJitter = _jitter();
    final random =
        suppliedJitter.isFinite ? suppliedJitter.clamp(0.0, 1.0) : 0.5;
    final jitteredMicros = boundedMicros * (0.8 + random * 0.4);
    return Duration(microseconds: jitteredMicros.round());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _connectingCancellation?.cancel();
    _connectingCancellation = null;
    _state = ServerEventConnectionState.closed;
    _connectedAt = null;
    try {
      await _subscription?.cancel();
    } finally {
      _subscription = null;
      final connection = _connection;
      _connection = null;
      try {
        await connection?.close();
      } finally {
        await _events.close();
      }
    }
  }
}

/// Safe default until a transport can provide a socket that honors the active
/// service endpoint policy. It does not fall back to a public URL.
final class UnsupportedServerEventSource implements ServerEventSource {
  const UnsupportedServerEventSource();

  @override
  ServerEventsSupport get support => ServerEventsSupport.unsupported;
  @override
  Stream<JellyfinServerEvent> get events =>
      const Stream<JellyfinServerEvent>.empty();
  @override
  Future<void> close() async {}
}

typedef ServerEventInvalidationHandler = void Function();
typedef ServerItemInvalidationHandler = void Function(Set<String> itemIds);

/// Owns one server/account-scoped event source and rejects late events after
/// that session is no longer current. Invalidation callbacks are debounced so
/// bursts do not cause repeated full-library refreshes.
final class JellyfinServerEventSessionController {
  JellyfinServerEventSessionController({
    required this.source,
    required this.isCurrent,
    required this.onLibraryInvalidated,
    required this.onUserDataInvalidated,
    required this.onItemsInvalidated,
    this.coalesceFor = const Duration(milliseconds: 150),
    this.maxCoalescedItemIds = 512,
  }) {
    if (coalesceFor.isNegative || maxCoalescedItemIds < 1) {
      throw ArgumentError('Invalid event coalescing bounds');
    }
    _subscription = source.events.listen(_onEvent);
  }

  final ServerEventSource source;
  final bool Function() isCurrent;
  final ServerEventInvalidationHandler onLibraryInvalidated;
  final ServerEventInvalidationHandler onUserDataInvalidated;
  final ServerItemInvalidationHandler onItemsInvalidated;
  final Duration coalesceFor;
  final int maxCoalescedItemIds;
  StreamSubscription<JellyfinServerEvent>? _subscription;
  Timer? _coalesceTimer;
  var _closed = false;
  var _libraryChanged = false;
  var _userDataChanged = false;
  var _itemOverflowed = false;
  final Set<String> _itemIds = <String>{};

  ServerEventsSupport get support => source.support;

  void _onEvent(JellyfinServerEvent event) {
    if (_closed || !isCurrent()) return;
    switch (event.kind) {
      case JellyfinServerEventKind.libraryInvalidated:
        _libraryChanged = true;
        break;
      case JellyfinServerEventKind.userDataInvalidated:
        _userDataChanged = true;
        break;
      case JellyfinServerEventKind.itemInvalidated:
        if (!_itemOverflowed) {
          for (final id in event.itemIds) {
            if (id.trim().isEmpty) continue;
            _itemIds.add(id);
            if (_itemIds.length > maxCoalescedItemIds) {
              // On overload, request an authoritative broad refresh instead
              // of retaining an unbounded set of attacker-controlled IDs.
              _itemIds.clear();
              _itemOverflowed = true;
              _libraryChanged = true;
              break;
            }
          }
        }
        break;
    }
    _coalesceTimer ??= Timer(coalesceFor, _flush);
  }

  void _flush() {
    _coalesceTimer = null;
    if (_closed || !isCurrent()) {
      _libraryChanged = false;
      _userDataChanged = false;
      _itemOverflowed = false;
      _itemIds.clear();
      return;
    }
    final libraryChanged = _libraryChanged;
    final userDataChanged = _userDataChanged;
    final itemIds = Set<String>.unmodifiable(_itemIds);
    _libraryChanged = false;
    _userDataChanged = false;
    _itemOverflowed = false;
    _itemIds.clear();
    if (libraryChanged) onLibraryInvalidated();
    if (userDataChanged) onUserDataInvalidated();
    if (itemIds.isNotEmpty) onItemsInvalidated(itemIds);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _coalesceTimer?.cancel();
    await _subscription?.cancel();
    await source.close();
    _itemIds.clear();
  }
}
