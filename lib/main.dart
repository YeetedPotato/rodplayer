import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/session/server_session.dart';
import 'package:rodplayer/core/session/active_server_context.dart';
import 'package:rodplayer/core/models/server_registry_store.dart';
import 'package:rodplayer/core/models/server_registry.dart';
import 'package:rodplayer/core/security/server_registry_migration.dart';
import 'package:rodplayer/core/events/jellyfin_server_event_session_factory.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/models/server_identity.dart';
import 'package:rodplayer/core/network/private_service_endpoint_resolver.dart';
import 'package:rodplayer/core/network/service_transport.dart';
import 'package:rodplayer/core/network/private_network_session_controller.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/managed_private_transport_setup.dart';
import 'package:rodplayer/core/network/private_transport_profile_association.dart';
import 'package:rodplayer/core/network/private_transport_profile.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/platform/network/method_channel_private_network_runtime.dart';
import 'package:rodplayer/platform/playback/platform_playback_runtimes.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/core/theme/appearance_controller.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';
import 'package:rodplayer/ui/screens/login_screen.dart';
import 'package:rodplayer/ui/shell/rodplayer_app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (mediaKitPlaybackSupportedOn(platformFamilyForCurrentTarget())) {
    MediaKit.ensureInitialized();
  }
  final preferences = await SharedPreferences.getInstance();
  runApp(RodPlayerApp(
      preferences: preferences,
      credentialStore: const SecureCredentialStore(),
      serverEventSessionBuilder: createJellyfinServerEventSession));
}

class RodPlayerApp extends StatefulWidget {
  const RodPlayerApp({
    required this.preferences,
    required this.credentialStore,
    this.clientFactory = _defaultClientFactory,
    this.privateNetworkRuntimeFactory = _defaultPrivateNetworkRuntimeFactory,
    this.enrollmentClientFactory = _defaultEnrollmentClientFactory,
    this.serverEventSessionBuilder,
    super.key,
  });

  final SharedPreferences preferences;
  final CredentialStore credentialStore;
  final JellyfinClientFactory clientFactory;
  final PrivateNetworkRuntime Function() privateNetworkRuntimeFactory;
  final EnrollmentClientFactory enrollmentClientFactory;
  final ServerEventSessionBuilder? serverEventSessionBuilder;

  @override
  State<RodPlayerApp> createState() => _RodPlayerAppState();
}

class _RodPlayerAppState extends State<RodPlayerApp> {
  late final AppearanceController _appearance = AppearanceController(
    widget.preferences,
  );

  @override
  void dispose() {
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _appearance,
        builder: (context, _) => MaterialApp(
          title: 'Nautilus',
          theme: _appearance.themeData,
          home: RodPlayerShell(
            preferences: widget.preferences,
            credentialStore: widget.credentialStore,
            clientFactory: widget.clientFactory,
            privateNetworkRuntimeFactory: widget.privateNetworkRuntimeFactory,
            enrollmentClientFactory: widget.enrollmentClientFactory,
            serverEventSessionBuilder: widget.serverEventSessionBuilder,
            appearanceController: _appearance,
          ),
        ),
      );
}

class RodPlayerShell extends StatefulWidget {
  const RodPlayerShell({
    required this.preferences,
    required this.credentialStore,
    this.clientFactory = _defaultClientFactory,
    this.privateNetworkRuntimeFactory = _defaultPrivateNetworkRuntimeFactory,
    this.enrollmentClientFactory = _defaultEnrollmentClientFactory,
    this.serverEventSessionBuilder,
    this.appearanceController,
    super.key,
  });

  final SharedPreferences preferences;
  final CredentialStore credentialStore;
  final JellyfinClientFactory clientFactory;
  final PrivateNetworkRuntime Function() privateNetworkRuntimeFactory;
  final EnrollmentClientFactory enrollmentClientFactory;
  final ServerEventSessionBuilder? serverEventSessionBuilder;
  final AppearanceController? appearanceController;

  @override
  State<RodPlayerShell> createState() => _RodPlayerShellState();
}

class _RodPlayerShellState extends State<RodPlayerShell> {
  // Compatibility bridge owns exactly one active session. Registry/controller
  // switching remains a foundation until a deliberate server-management flow.
  ActiveServerContext? _activeServer;
  int _contextGeneration = 0;
  JellyfinApiClient? get _client => _activeServer?.session.client;
  late final PreferencesServerRegistryStore _serverRegistry =
      PreferencesServerRegistryStore(widget.preferences);
  bool _serverRegistryCorrupt = false;
  bool _authenticationPending = false;
  InstallationIdentity? _identity;
  ServerId? _serverId;
  bool _loading = true;
  final ValueNotifier<int> _serverEventRevision = ValueNotifier<int>(0);
  PrivateNetworkSessionController? _privateNetwork;
  final _privateNetworkOwner = PrivateNetworkSessionOwner();
  PrivateTransportProfile? _privateNetworkProfile;
  final ValueNotifier<PrivateNetworkStatus?> _unavailablePrivateStatus =
      ValueNotifier(null);
  late final PrivateTransportProfileAssociation _privateTransport;
  late final PrivateTransportProfileStore _profiles;

  @override
  void initState() {
    super.initState();
    _privateTransport = PrivateTransportProfileAssociation(widget.preferences);
    _profiles = PrivateTransportProfileStore(widget.preferences);
    _restore();
  }

  @override
  void dispose() {
    unawaited(_privateNetworkOwner.close().catchError((_) {}));
    final active = _activeServer;
    if (active != null) unawaited(active.session.close());
    _unavailablePrivateStatus.dispose();
    _serverEventRevision.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final migration = CredentialMigration(
      preferences: widget.preferences,
      credentialStore: widget.credentialStore,
    );
    await migration.migrate();
    if (!mounted) return;
    try {
      await ServerRegistryMigration(
        preferences: widget.preferences,
        credentials: widget.credentialStore,
        registry: _serverRegistry,
      ).migrateLegacyInstallation();
    } on ServerRegistryCorruptException {
      // Keep the legacy single-server session usable without overwriting the
      // corrupt registry document. Registry-based switching stays unavailable.
      _serverRegistryCorrupt = true;
    } on Object {
      // Registry migration is additive. Preserve the current single-server
      // legacy restore path and leave the registry bytes untouched.
      _serverRegistryCorrupt = true;
    }
    if (!mounted) return;
    final identity = await SharedPreferencesInstallationIdentityStore(
      widget.preferences,
    ).load();
    final url = widget.preferences.getString(CredentialMigration.serverUrlKey);
    final token = await widget.credentialStore.readToken(
      CredentialMigration.tokenKey,
    );
    final user = widget.preferences.getString(CredentialMigration.userIdKey);
    var serverId =
        await ConfiguredServerIdStore(widget.preferences).loadOrCreate();
    if (!mounted) return;
    if (!_serverRegistryCorrupt && url != null && user != null) {
      try {
        final snapshot = await _serverRegistry.load();
        final activeId = snapshot.activeServerId;
        final activeAccount = snapshot.activeAccountId;
        final activeRecord =
            activeId == null ? null : snapshot.server(activeId);
        if (activeRecord != null &&
            activeAccount?.userId == user &&
            activeRecord.endpoints.contains(ServerEndpoint(url)) &&
            activeRecord.accounts.any(
              (account) => account.identity == activeAccount,
            )) {
          serverId = activeRecord.id;
        }
      } on Object {
        _serverRegistryCorrupt = true;
      }
    }
    JellyfinApiClient? client;
    if (!mounted) return;
    if (url != null &&
        token != null &&
        user != null &&
        url.isNotEmpty &&
        token.isNotEmpty &&
        user.isNotEmpty) {
      client = _makeClient(
        url,
        identity,
        serverId: serverId,
        userId: user,
        accessToken: token,
      );
    }
    if (!mounted) {
      client?.close();
      final network = _privateNetwork;
      _privateNetwork = null;
      _privateNetworkProfile = null;
      if (network != null) unawaited(network.close());
      return;
    }
    final account = client?.accountIdentity;
    final active = client == null || account == null
        ? null
        : _createActiveContext(client, account);
    setState(() {
      _identity = identity;
      _serverId = serverId;
      _activeServer = active;
      _loading = false;
    });
  }

  Future<void> _authenticated(String url, JellyfinApiClient client) async {
    if (_activeServer != null || _authenticationPending) {
      throw StateError('Sign out of the active session before signing in.');
    }
    _authenticationPending = true;
    try {
      await _commitAuthenticated(url, client);
    } finally {
      _authenticationPending = false;
    }
  }

  Future<void> _commitAuthenticated(
    String url,
    JellyfinApiClient client,
  ) async {
    final verifiedSystemId = await client.getVerifiedServerSystemId();
    var serverId = client.serverId;
    if (!_serverRegistryCorrupt) {
      try {
        serverId = ServerIdentityResolver().resolveLogin(
          registry: await _serverRegistry.load(),
          endpoint: ServerEndpoint(url),
          verifiedSystemId: verifiedSystemId,
          provisionalServerId: client.serverId,
        );
      } on ServerIdentityConflictException {
        rethrow;
      } on Object {
        _serverRegistryCorrupt = true;
      }
    }
    await _activeServer?.session.events?.close();
    final previousUrl = widget.preferences.getString(
      CredentialMigration.serverUrlKey,
    );
    await widget.preferences.setString(CredentialMigration.serverUrlKey, url);
    if (previousUrl != url) {
      await _privateTransport.clear();
    }
    await widget.credentialStore.writeToken(
      CredentialMigration.tokenKey,
      client.accessToken!,
    );
    await widget.preferences.setString(
      CredentialMigration.userIdKey,
      client.userId!,
    );
    if (!_serverRegistryCorrupt) {
      try {
        await _persistServerAccount(
          url,
          client,
          serverId: serverId,
          verifiedSystemId: verifiedSystemId,
        );
      } on ServerRegistryCorruptException {
        _serverRegistryCorrupt = true;
      } on FormatException {
        _serverRegistryCorrupt = true;
      } on Object {
        // Keep the successful legacy single-server login usable; the next
        // startup retries the nonsecret registry migration from verified
        // secure-store state.
        _serverRegistryCorrupt = true;
      }
    }
    if (_serverRegistryCorrupt) serverId = client.serverId;
    final activeClient =
        serverId == client.serverId ? client : client.withServerId(serverId);
    final account = activeClient.accountIdentity;
    if (account == null)
      throw StateError('Authenticated client has no account identity');
    final previous = _activeServer;
    final next = _createActiveContext(
      activeClient,
      account,
      verifiedSystemId: verifiedSystemId,
    );
    if (mounted) {
      setState(() {
        _activeServer = next;
        _serverId = activeClient.serverId;
      });
      if (previous != null) await previous.session.close();
    } else {
      await next.session.close();
    }
  }

  ActiveServerContext _createActiveContext(
    JellyfinApiClient client,
    ServerAccountId account, {
    String? verifiedSystemId,
  }) {
    final generation = ++_contextGeneration;
    final eventSession = widget.serverEventSessionBuilder?.call(
      client: client,
      isCurrent: () =>
          mounted &&
          _contextGeneration == generation &&
          _activeServer?.generation == generation &&
          !(_activeServer?.session.isClosed ?? true),
      onLibraryInvalidated: _onServerDataInvalidated,
      onUserDataInvalidated: _onServerDataInvalidated,
      onItemsInvalidated: (_) => _onServerDataInvalidated(),
    );
    return ActiveServerContext(
      generation: generation,
      session: ServerSession(
        serverId: client.serverId,
        accountId: account,
        verifiedSystemId: verifiedSystemId,
        events: eventSession,
        client: client,
      ),
    );
  }

  void _onServerDataInvalidated() {
    if (!mounted) return;
    _serverEventRevision.value++;
  }

  Future<void> _persistServerAccount(
    String url,
    JellyfinApiClient client, {
    required ServerId serverId,
    required String verifiedSystemId,
  }) async {
    final userId = client.userId;
    final accountId = userId == null
        ? null
        : ServerAccountId(serverId: serverId, userId: userId);
    final token = client.accessToken;
    if (accountId == null || token == null) {
      throw StateError('Authenticated session identity is incomplete');
    }
    final credentialReference = ServerRegistryMigration.credentialReferenceFor(
      accountId,
    );
    final snapshot = await _serverRegistry.load();
    final existing = snapshot.server(serverId);
    if (existing?.verifiedSystemId != null &&
        existing!.verifiedSystemId != verifiedSystemId) {
      throw const ServerIdentityConflictException(
          ServerIdentityConflict.endpointMismatch);
    }
    await widget.credentialStore.writeToken(credentialReference, token);
    if (await widget.credentialStore.readToken(credentialReference) != token) {
      throw StateError('Could not verify server account credential');
    }
    final endpoint = ServerEndpoint(url);
    final account = ServerUserAccount(
      identity: accountId,
      credentialReference: credentialReference,
    );
    final record = existing == null
        ? ServerRecord(
            id: accountId.serverId,
            displayName: endpoint.uri.host,
            endpoints: <ServerEndpoint>[endpoint],
            accounts: <ServerUserAccount>[account],
            verifiedSystemId: verifiedSystemId,
          )
        : ServerRecord(
            id: existing.id,
            displayName: existing.displayName,
            endpoints: <ServerEndpoint>{
              endpoint,
              ...existing.endpoints,
            }.toList(),
            accounts: <ServerUserAccount>[
              ...existing.accounts.where((item) => item.identity != accountId),
              account,
            ],
            verifiedSystemId: existing.verifiedSystemId ?? verifiedSystemId,
          );
    if (existing == null) {
      await _serverRegistry.addServer(record);
    } else {
      await _serverRegistry.updateServer(record);
    }
    await _serverRegistry.setActiveServer(
      accountId.serverId,
      accountId: accountId,
    );
  }

  Future<void> _configurePrivateAccess(
    String canonicalUrl,
    String invitationText,
    String setupCode,
  ) async {
    await ManagedPrivateTransportSetup(
      preferences: widget.preferences,
      runtimeFactory: widget.privateNetworkRuntimeFactory,
      enrollmentClientFactory: widget.enrollmentClientFactory,
    ).configure(
      canonicalServerUrl: canonicalUrl,
      invitationText: invitationText,
      setupCode: setupCode,
    );
    _privateNetwork = null;
    _privateNetworkProfile = null;
    await _privateNetworkOwner.detach();
  }

  JellyfinApiClient _makeClient(
    String url,
    InstallationIdentity identity, {
    required ServerId serverId,
    String? userId,
    String? accessToken,
  }) {
    final client = widget.clientFactory(
      url,
      identity,
      serverId: serverId,
      userId: userId,
      accessToken: accessToken,
    );
    final association = _privateTransport.lookupFor(url);
    PrivateTransportProfile? profile;
    try {
      if (association.kind == PrivateTransportAssociationKind.associated) {
        profile = _profiles.find(association.profileId!);
      }
    } on FormatException {
      // A malformed profile store must never turn private traffic public.
    }
    if (profile != null) {
      final claim = PrivateNetworkIdentityClaim(
        profileId: profile.id,
        controlUrl: profile.controlUrl,
        homeIpv4: profile.serviceIpv4,
        homePort: profile.servicePort,
        allowLegacyClaim: _profiles.uniquelyMatches(profile),
      );
      if (_privateNetworkProfile?.id != profile.id ||
          _privateNetworkProfile?.controlUrl != profile.controlUrl ||
          _privateNetworkProfile?.serviceIpv4 != profile.serviceIpv4 ||
          _privateNetworkProfile?.servicePort != profile.servicePort) {
        _privateNetwork = _privateNetworkOwner.replace(
          widget.privateNetworkRuntimeFactory(),
          claim,
        );
        _privateNetworkProfile = profile;
      }
      final network = _privateNetwork!;
      unawaited(network.start());
      _bindPrivateTransport(
        client,
        network.status,
        waitUntilReady: network.waitUntilReady,
      );
    } else if (association.kind != PrivateTransportAssociationKind.none) {
      _bindPrivateTransport(client, _unavailablePrivateStatus);
    }
    return client;
  }

  void _bindPrivateTransport(
    JellyfinApiClient client,
    ValueListenable<PrivateNetworkStatus?> status, {
    Future<void> Function()? waitUntilReady,
  }) {
    final transport = client.serviceTransport;
    if (transport is! HttpServiceTransport) {
      throw StateError(
        'Private service requires the configured HTTP transport adapter',
      );
    }
    transport.bindPrivateResolver(
      PrivateServiceEndpointResolver(
        canonicalBaseUrl: client.baseUrl,
        status: status,
      ),
      waitUntilReady: waitUntilReady,
    );
  }

  Future<void> _logout() async {
    await _clearSession(keepServerUrl: false);
  }

  Future<void> _switchProfile() async {
    await _clearSession(keepServerUrl: true);
  }

  Future<void> _clearSession({required bool keepServerUrl}) async {
    final client = _client;
    final account = _activeServer?.accountId;
    if (client != null) {
      try {
        await client.reportSessionEnded();
      } catch (_) {}
    }
    if (!keepServerUrl) {
      await widget.preferences.remove(CredentialMigration.serverUrlKey);
      await _privateTransport.clear();
    }
    await _activeServer?.session.events?.close();
    await widget.credentialStore.deleteToken(CredentialMigration.tokenKey);
    if (account != null) {
      await widget.credentialStore.deleteToken(
        ServerRegistryMigration.credentialReferenceFor(account),
      );
    }

    await widget.preferences.remove(CredentialMigration.userIdKey);
    if (mounted) {
      final previous = _activeServer;
      _contextGeneration++;
      setState(() => _activeServer = null);
      if (previous != null) await previous.session.close();
    } else {
      client?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_activeServer == null) {
      return LoginScreen(
        identity: _identity!,
        serverId: _serverId!,
        initialServerUrl: widget.preferences.getString(
          CredentialMigration.serverUrlKey,
        ),
        clientFactory: _makeClient,
        onConfigurePrivateAccess: _configurePrivateAccess,
        onAuthenticated: _authenticated,
      );
    }
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: RodPlayerAppShell(
        client: _activeServer!.session.client,
        onLogout: _logout,
        onSwitchProfile: _switchProfile,
        appearanceController: widget.appearanceController,
        serverEventRevision: _serverEventRevision,
      ),
    );
  }
}

Widget playerRoute(MediaKitPlaybackEngine engine, JellyfinApiClient client,
        String itemId) =>
    VideoPlayerView(
        engine: engine,
        surface: MediaKitPlaybackVideoSurface(engine),
        client: client,
        itemId: itemId);

JellyfinApiClient _defaultClientFactory(
  String baseUrl,
  InstallationIdentity identity, {
  required ServerId serverId,
  String? userId,
  String? accessToken,
}) =>
    JellyfinApiClient(
      baseUrl: baseUrl,
      identity: identity,
      serverId: serverId,
      userId: userId,
      accessToken: accessToken,
    );

PrivateNetworkRuntime _defaultPrivateNetworkRuntimeFactory() =>
    MethodChannelPrivateNetworkRuntime();

FamilyEnrollmentClient _defaultEnrollmentClientFactory(Uri endpoint) =>
    FamilyEnrollmentClient(endpoint: endpoint);
