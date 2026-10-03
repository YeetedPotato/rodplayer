# ADR-002: Active server context

**Status:** Accepted for Architecture Foundation Phase 2

## Decision

The registry may contain multiple server records and accounts, but the app publishes exactly one `ActiveServerContext` at a time. A context is immutable and contains the stable app `ServerId`, server-scoped `ServerAccountId`, monotonically increasing generation, and one `ServerSession`. Home, Search, Details, and playback continue to receive the current client through the existing single-client shell; no cross-server fan-out or UI was added.

A `ServerRecord` contains nonsecret display metadata, validated HTTP(S) endpoint candidates, account references, and an optional server-reported Jellyfin system ID. The app UUID is the identity. `System/Info/Public.Id` is fetched through an authenticated client and compared after a server is reached, but it is not a cryptographic identity proof and is not substituted for `ServerId`. A URL is only a location. Media provenance composes server, user, and item IDs.

Each `ServerSession` owns one authenticated `JellyfinApiClient` and a cancellation signal. Closing it cancels the signal and closes the client transport. The client and session must agree on both server and account identity. The OS-backed `CredentialStore` is referenced by a nonsecret key; no token is placed in the registry.

## Switch transaction

`ActiveServerController` serializes requests. It rejects server/account mismatches and refuses a switch while the injected active-playback policy reports a running playback session. It opens the candidate from the selected record's first endpoint only, reads the authenticated server system ID and current user, and validates both against the requested account and any previously observed server ID. It atomically persists verified server identity plus active server/account before publishing the new context. Any setup, verification, or persistence failure closes the candidate and leaves the previous context active. Only after publish does it cancel and retire the previous session.

Endpoint candidates are not an implicit retry/fallback list. A required private route must continue to fail closed through the existing `ServiceTransport` adapter; the session factory does not try a public candidate after a private failure. Endpoint selection policy must become explicit before adding automatic candidate switching.

Every long-running operation captures its context and generation. `ActiveServerController.run` returns an explicit stale result instead of publishing a late value after a switch. Callers remain responsible for guarding their own state updates. The controller has no `PrivateNetworkRuntime` dependency: that runtime remains app-global and is not restarted by media-server changes.

## Playback and compatibility

Production still uses the legacy single-server restore/login bridge, with one
active context and guarded authentication. `ActiveServerController` and the
multi-server registry are foundations, not an enabled server-management or
app-wide switching UX. Controller/factory switch tests do not claim otherwise.
The bridge resolves unique verified system identities across URL aliases and
rejects conflicts before credential reuse. Private-profile replacement waits
for previous native shutdown; failure blocks replacement rather than falling
back publicly. No automatic multi-profile selector is enabled.

An active playback blocks server switching until the existing playback owner reports it inactive. This phase does not transfer playback sessions between servers or accounts. The root shell now wraps its existing single authenticated client in one active context; screens still receive the same client. This is the compatibility adapter, not a multi-server selector.

## Rejected alternatives

- Using URL, Jellyfin item ID, or a private-network peer ID as server identity.
- Merging any content across servers.
- Publishing a candidate before authentication/account verification or discarding the previous session first.
- Treating a failed private candidate as permission to fall back to public transport.
- Restarting global private-network runtime when the selected media server changes.
- Silently switching servers while playback owns a session.

## Migration

The current server slot's persisted UUID is reused. Existing URL and user preferences remain valid; the Phase 3 migration adds a registry record and account reference while keeping the legacy credential until the new secure-store reference and registry document have been verified.
