import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Stable application identity for one configured media server.
///
/// This value is assigned independently of any endpoint URL. A server record
/// may later contain LAN, private, and remote endpoint candidates without
/// changing its [ServerId].
final class ServerId {
  ServerId(String value) : value = _serverId(value);

  final String value;

  factory ServerId.fromJson(Object? json) {
    if (json is! String) throw const FormatException('Invalid server ID');
    return ServerId(json);
  }

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is ServerId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Account identity scoped to the owning configured server.
///
/// Authentication tokens are deliberately not part of this value.
final class ServerAccountId {
  ServerAccountId({required this.serverId, required String userId})
      : userId = _required(userId, 'userId');

  final ServerId serverId;
  final String userId;

  Map<String, String> toJson() => <String, String>{
        'serverId': serverId.toJson(),
        'userId': userId,
      };

  factory ServerAccountId.fromJson(Map<String, Object?> json) =>
      ServerAccountId(
        serverId: ServerId.fromJson(json['serverId']),
        userId: json['userId'] is String ? json['userId']! as String : '',
      );

  @override
  bool operator ==(Object other) =>
      other is ServerAccountId &&
      other.serverId == serverId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(serverId, userId);

  @override
  String toString() => 'ServerAccountId($serverId, $userId)';
}

/// Cache/media identity that prevents equal Jellyfin item IDs on different
/// servers or accounts from colliding.
final class ServerMediaItemId {
  ServerMediaItemId({required this.accountId, required String itemId})
      : itemId = _required(itemId, 'itemId');

  final ServerAccountId accountId;
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is ServerMediaItemId &&
      other.accountId == accountId &&
      other.itemId == itemId;

  @override
  int get hashCode => Object.hash(accountId, itemId);
}

/// Persistence for the current single configured-server slot.
///
/// The key is local nonsecret configuration. Credentials remain in
/// [CredentialStore] under OS secure storage.
class ConfiguredServerIdStore {
  ConfiguredServerIdStore(this.preferences, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  static const preferenceKey = 'nautilus_configured_server_id';

  final SharedPreferences preferences;
  final Uuid _uuid;

  ServerId createNew() => ServerId(_uuid.v4());

  Future<ServerId> loadOrCreate() async {
    final stored = preferences.getString(preferenceKey);
    if (stored != null && stored.trim().isNotEmpty && stored == stored.trim()) {
      try {
        return ServerId(stored);
      } on FormatException {
        // Replace only malformed, nonsecret identity metadata.
      }
    }
    final created = ServerId(_uuid.v4());
    await preferences.setString(preferenceKey, created.toJson());
    return created;
  }
}

String _required(String value, String name) {
  if (value.isEmpty || value.length > 512 || value.trim() != value) {
    throw FormatException('Invalid $name');
  }
  return value;
}

String _serverId(String value) {
  if (value.length > 128 ||
      value.contains('://') ||
      value.contains(RegExp(r'\s'))) {
    throw const FormatException('Invalid serverId');
  }
  return _required(value, 'serverId');
}
