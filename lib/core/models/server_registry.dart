import 'dart:convert';

import 'server_identity.dart';

/// A Jellyfin endpoint is a network location, never the server's identity.
final class ServerEndpoint {
  ServerEndpoint(String value) : value = _validateEndpoint(value);

  final String value;

  Uri get uri => Uri.parse(value);

  Map<String, String> toJson() => <String, String>{'url': value};

  factory ServerEndpoint.fromJson(Object? value) {
    if (value is! Map || value['url'] is! String) {
      throw const FormatException('Invalid server endpoint');
    }
    return ServerEndpoint(value['url']! as String);
  }

  @override
  bool operator ==(Object other) =>
      other is ServerEndpoint && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Account metadata and a reference into OS-backed credential storage.
/// The reference is not a credential and the record never contains a token.
final class ServerUserAccount {
  ServerUserAccount({
    required this.identity,
    required String credentialReference,
    this.displayName,
  }) : credentialReference =
            _required(credentialReference, 'credentialReference') {
    if (displayName != null && displayName!.length > 128) {
      throw ArgumentError.value(displayName, 'displayName');
    }
  }

  final ServerAccountId identity;
  final String credentialReference;
  final String? displayName;

  Map<String, Object?> toJson() => <String, Object?>{
        'identity': identity.toJson(),
        'credentialReference': credentialReference,
        if (displayName != null) 'displayName': displayName,
      };

  factory ServerUserAccount.fromJson(Object? json) {
    if (json is! Map || json['identity'] is! Map) {
      throw const FormatException('Invalid server account');
    }
    if (json['displayName'] != null && json['displayName'] is! String) {
      throw const FormatException('Invalid server account display name');
    }
    if (json['displayName'] is String &&
        (json['displayName'] as String).length > 128) {
      throw const FormatException('Invalid server account display name');
    }
    return ServerUserAccount(
      identity: ServerAccountId.fromJson(
        Map<String, Object?>.from(json['identity'] as Map),
      ),
      credentialReference: json['credentialReference'] is String
          ? json['credentialReference']! as String
          : '',
      displayName:
          json['displayName'] is String ? json['displayName']! as String : null,
    );
  }
}

/// Nonsecret server configuration. A verified Jellyfin system ID is retained
/// as a consistency check, while [id] remains the app's stable identity.
final class ServerRecord {
  ServerRecord({
    required this.id,
    required String displayName,
    required Iterable<ServerEndpoint> endpoints,
    Iterable<ServerUserAccount> accounts = const <ServerUserAccount>[],
    this.verifiedSystemId,
  })  : displayName = _required(displayName, 'displayName'),
        endpoints = List<ServerEndpoint>.unmodifiable(endpoints),
        accounts = List<ServerUserAccount>.unmodifiable(accounts) {
    if (this.endpoints.isEmpty || this.endpoints.length > maximumEndpoints) {
      throw ArgumentError.value(
          endpoints, 'endpoints', 'outside supported bounds');
    }
    if (this.accounts.length > maximumAccounts) {
      throw ArgumentError.value(
          accounts, 'accounts', 'outside supported bounds');
    }
    if (this.accounts.any((account) => account.identity.serverId != id)) {
      throw ArgumentError('Every account must belong to this server');
    }
    if (this.accounts.map((account) => account.identity).toSet().length !=
        this.accounts.length) {
      throw ArgumentError('Duplicate server account identity');
    }
    if (verifiedSystemId != null &&
        (verifiedSystemId!.trim().isEmpty || verifiedSystemId!.length > 512)) {
      throw ArgumentError.value(verifiedSystemId, 'verifiedSystemId');
    }
  }

  static const maximumEndpoints = 64;
  static const maximumAccounts = 128;

  final ServerId id;
  final String displayName;
  final List<ServerEndpoint> endpoints;
  final List<ServerUserAccount> accounts;
  final String? verifiedSystemId;

  ServerRecord withAccount(ServerUserAccount account) => ServerRecord(
        id: id,
        displayName: displayName,
        endpoints: endpoints,
        accounts: <ServerUserAccount>[
          ...accounts.where((item) => item.identity != account.identity),
          account,
        ],
        verifiedSystemId: verifiedSystemId,
      );

  ServerRecord withVerifiedSystemId(String systemId) => ServerRecord(
        id: id,
        displayName: displayName,
        endpoints: endpoints,
        accounts: accounts,
        verifiedSystemId: _required(systemId, 'verifiedSystemId'),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.toJson(),
        'displayName': displayName,
        'endpoints': endpoints.map((endpoint) => endpoint.toJson()).toList(),
        'accounts': accounts.map((account) => account.toJson()).toList(),
        if (verifiedSystemId != null) 'verifiedSystemId': verifiedSystemId,
      };

  factory ServerRecord.fromJson(Object? json) {
    if (json is! Map ||
        json['endpoints'] is! List ||
        json['accounts'] is! List) {
      throw const FormatException('Invalid server record');
    }
    if (json['verifiedSystemId'] != null &&
        json['verifiedSystemId'] is! String) {
      throw const FormatException('Invalid verified server system ID');
    }
    return ServerRecord(
      id: ServerId.fromJson(json['id']),
      displayName:
          json['displayName'] is String ? json['displayName']! as String : '',
      endpoints: (json['endpoints'] as List).map(ServerEndpoint.fromJson),
      accounts: (json['accounts'] as List).map(ServerUserAccount.fromJson),
      verifiedSystemId: json['verifiedSystemId'] is String
          ? json['verifiedSystemId']! as String
          : null,
    );
  }
}

/// Snapshot stored as one versioned preference value so each write replaces a
/// complete, referentially-validated registry document.
final class ServerRegistrySnapshot {
  ServerRegistrySnapshot({
    Iterable<ServerRecord> servers = const <ServerRecord>[],
    this.activeServerId,
    this.activeAccountId,
  }) : servers = List<ServerRecord>.unmodifiable(servers) {
    if (this.servers.length > maximumServers) {
      throw ArgumentError.value(servers, 'servers', 'outside supported bounds');
    }
    if (this.servers.map((server) => server.id).toSet().length !=
        this.servers.length) {
      throw ArgumentError('Duplicate server identity');
    }
    ServerRecord? activeServer;
    for (final server in this.servers) {
      if (server.id == activeServerId) {
        activeServer = server;
        break;
      }
    }
    if (activeServerId != null && activeServer == null) {
      throw ArgumentError('Active server must exist in the registry');
    }
    if (activeAccountId != null &&
        (activeServerId != activeAccountId!.serverId ||
            activeServer?.accounts.any(
                  (account) => account.identity == activeAccountId,
                ) !=
                true)) {
      throw ArgumentError('Active account must belong to the active server');
    }
  }

  static const schemaVersion = 1;
  static const maximumServers = 128;
  static const preferenceKey = 'nautilus_server_registry';

  final List<ServerRecord> servers;
  final ServerId? activeServerId;
  final ServerAccountId? activeAccountId;

  ServerRecord? server(ServerId id) {
    for (final record in servers) {
      if (record.id == id) return record;
    }
    return null;
  }

  ServerRegistrySnapshot copyWith({
    Iterable<ServerRecord>? servers,
    ServerId? activeServerId,
    bool clearActiveServer = false,
    ServerAccountId? activeAccountId,
    bool clearActiveAccount = false,
  }) =>
      ServerRegistrySnapshot(
        servers: servers ?? this.servers,
        activeServerId:
            clearActiveServer ? null : activeServerId ?? this.activeServerId,
        activeAccountId: clearActiveServer || clearActiveAccount
            ? null
            : activeAccountId ?? this.activeAccountId,
      );

  String encode() => jsonEncode(<String, Object?>{
        'schemaVersion': schemaVersion,
        'servers': servers.map((server) => server.toJson()).toList(),
        if (activeServerId != null) 'activeServerId': activeServerId!.toJson(),
        if (activeAccountId != null)
          'activeAccountId': activeAccountId!.toJson(),
      });

  factory ServerRegistrySnapshot.decode(String value) {
    if (value.length > 2 * 1024 * 1024) {
      throw const FormatException('Server registry is too large');
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map ||
        decoded['schemaVersion'] != schemaVersion ||
        decoded['servers'] is! List) {
      throw const FormatException('Unsupported server registry document');
    }
    if (decoded['activeServerId'] != null &&
        decoded['activeServerId'] is! String) {
      throw const FormatException('Invalid active server ID');
    }
    if (decoded['activeAccountId'] != null &&
        decoded['activeAccountId'] is! Map) {
      throw const FormatException('Invalid active account ID');
    }
    return ServerRegistrySnapshot(
      servers: (decoded['servers'] as List).map(ServerRecord.fromJson),
      activeServerId: decoded['activeServerId'] == null
          ? null
          : ServerId.fromJson(decoded['activeServerId']),
      activeAccountId: decoded['activeAccountId'] is Map
          ? ServerAccountId.fromJson(
              Map<String, Object?>.from(decoded['activeAccountId'] as Map),
            )
          : null,
    );
  }
}

String _required(String value, String name) {
  if (value.isEmpty || value.length > 512 || value.trim() != value) {
    throw FormatException('Invalid $name');
  }
  return value;
}

String _validateEndpoint(String value) {
  if (value.length > 2048) throw const FormatException('Invalid endpoint');
  _required(value, 'endpoint');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.isAbsolute ||
      !const <String>{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw FormatException('Invalid server endpoint');
  }
  return uri
      .replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''), query: null)
      .toString();
}
