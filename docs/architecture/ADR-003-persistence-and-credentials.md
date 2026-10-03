# ADR-003: Server registry persistence and credential migration

**Status:** Accepted for Architecture Foundation Phase 3

## Decision

Use the existing `SharedPreferences` dependency for the current bounded registry document. The whole registry is a versioned JSON snapshot stored under one key. It can hold multiple `ServerRecord`s, multiple server-scoped accounts, verified server IDs, and the active server/account preference. The decoder validates referential integrity before exposing a snapshot. Writes serialize, replace the complete value, read it back for verification, and attempt to restore the previous value on failure. Corrupt or unknown-version data is preserved and reported as unavailable; it is never silently reset.

No relational workload exists yet: there are no download jobs, offline assets, outbox rows, cross-record queries, or transaction groups beyond replacing one registry snapshot. Adding a database now would add platform/runtime/codegen surface without improving the present schema. Before downloads, offline progress/outbox, or other independently updated relational records are implemented, migrate this registry to a versioned relational store with transactional migrations. This is a scoped choice, not a claim that preferences are suitable for future jobs.

The persistence schema version is explicit. Version 1 represents the first registry. Unsupported/corrupt documents fail closed and remain intact. Future schema changes must add explicit version-to-version migration functions before changing the current version.

## Credential boundary

Preferences contain only IDs, server display metadata, validated endpoint strings, Jellyfin user IDs, credential-reference keys, schema version, and active selection. Access tokens and passwords remain exclusively in `CredentialStore`, backed by OS secure storage in production. Registry serialization never accepts a token field. Account credential keys are derived from `(ServerId, UserId)` and are not bearer values.

## Legacy migration

After the existing credential migration, `ServerRegistryMigration` reads the legacy URL, user ID, and secure token. It reuses the existing configured `ServerId`, writes the token to the new account-scoped secure-store reference, reads it back, then writes and re-reads the registry record and active account. Only after all representations verify does migration report success. It does not delete the old secure token or legacy preferences, which makes the operation safe to retry and leaves rollback state available. If registry persistence is corrupt or unavailable, the app retains its legacy single-server restore path and leaves registry bytes untouched.

Login mirrors the authenticated account to its scoped secure reference and registry record while retaining legacy keys for compatibility. Logout removes both the legacy and scoped secure-store entries. Removing a server returns its credential references to the caller; secure-store cleanup is explicit and is not performed by preference serialization.

## Rollback and recovery

- Missing secure token: do not activate that account or choose a different one implicitly.
- Invalid server endpoint/account reference: reject record decoding/update.
- Corrupt or newer registry schema: retain original bytes, expose `ServerRegistryCorruptException`, and use only the known legacy single-server path when available.
- Interrupted migration: retain the legacy token and retry; orphaned new secure references are safe to overwrite on retry.
- Failed active-server switch: active preference is committed only with successful server verification; an error leaves the current session active.

Theme, appearance, and small device-local settings remain in preferences. Credentials remain in secure storage. Media files, download jobs, watch-progress outbox, and transactional retry metadata are explicitly outside this registry and require a future relational/filesystem design.