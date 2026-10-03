# ADR: Server identity and service transport

**Status:** Accepted for Architecture Foundation Phase 1
**Scope:** Identity and HTTP endpoint transport under the existing single-server Nautilus UI

**Historical scope:** This records Phase 1, not the current combined candidate.
Later identity/session/event foundations and ADR-002/ADR-003 supersede the
statements below that verified Jellyfin system identity is not persisted and
that no WebSocket implementation exists. Private WebSocket upgrade and
multi-server management UX remain gated; consult the later architecture docs.
Current private HTTP routing remains supported, but private WebSocket resolution
and handshakes return typed unsupported before readiness waits or channel creation.
Ordinary unassociated authenticated server sockets are unaffected.

## Context

Nautilus currently persists one server URL, a Jellyfin user ID, and a secure
access token. A URL is an endpoint and can change when the same server is
reached over LAN, private, or remote addresses. Jellyfin item IDs are only
meaningful within their owning server/account. Existing private networking
already provides the validated direct-only service route and redirect policy;
that policy must remain authoritative.

The app will eventually support multiple configured servers, while keeping
exactly one active server and never merging Home, Search, Continue Watching,
or libraries across servers.

## Decision

### Server and item identity

- `ServerId` is an opaque, stable app identity independent of URL and Jellyfin
  system IDs. The existing single configured-server slot loads or creates one
  UUID in the nonsecret SharedPreferences key
  `nautilus_configured_server_id`.
- `ServerAccountId` combines `ServerId` with Jellyfin `UserId`; it never
  contains an access token.
- `ServerMediaItemId` combines `ServerAccountId` with an item ID, so equal
  Jellyfin IDs on different servers or accounts are distinct.
- The repository does not currently persist or derive identity from a
  Jellyfin system/server ID. URLs remain endpoint data, not identity.

This phase has one configured-server slot, so changing its URL does not by
itself create a different `ServerId`. The future server registry must make a
new server record (and new ID) explicit while retaining the ID when an
existing server's endpoint candidates change. There is no cross-server UI or
cache in this phase.

### Immutable Jellyfin client identity

Each `JellyfinApiClient` is constructed for one `ServerId` and optional
`ServerAccountId`; the user ID and token are final construction-time values.
Authentication leaves the unauthenticated client unchanged and returns a new
authenticated client for the same server, sharing the service transport. HTTP
transport ownership transfers to that authenticated client so closing the
unauthenticated instance cannot disrupt it. Login/root composition remains
responsible for persisting tokens only through the existing secure credential
store.

### Service transport boundary

`JellyfinApiClient` owns Jellyfin routes, request/response mapping,
authentication headers, and status/error decoding. It uses a `ServiceTransport`
for HTTP requests, canonical service URI resolution, image bytes, and a
future-compatible WebSocket URI resolution seam. The protocol client does not
import private-network runtime/status types or own endpoint selection.

`HttpServiceTransport` reuses one injected `http.Client`. In ordinary mode it
sends canonical requests. When composed with private access, it delegates to
the existing `PrivateServiceHttpClient` and
`PrivateServiceEndpointResolver`; those existing components retain readiness,
origin validation, gateway selection, and redirect enforcement.

### Private networking and redirects

Private service access remains app-scoped and direct-only. The existing
resolver authorizes only its configured service origin and a verified usable
direct gateway. Unavailable, relay, malformed, or foreign targets fail
closed. Private HTTP redirects are validated against the same origin before
another send; they cannot fall through to the canonical public URL. LAN-first
behavior, embedded client ownership, Headscale compatibility, and the current
native private networking implementation are unchanged.

### Security

Tokens remain in the existing OS secure storage and in-memory authenticated
client only. Server/account identity values and the server ID preference are
nonsecret metadata. No credentials, setup codes, or gateway secrets are
written to preferences, identity serialization, logs, or this ADR.

### Future active-server and WebSocket work

The next registry/context phase can select one account/server context, assign
an activation generation, cancel stale requests, and tear down that server's
client/session without global identity state in Jellyfin protocol code.
Transport and HTTP cancellation continue to use the existing `http.Client`
request/abort semantics.

No WebSocket implementation is included. Future sockets must resolve through
the same server identity and endpoint policy, validate direct-only private
destinations, bind to the active-server generation/account, cancel stale
connect attempts during a switch, and dispose with that session. The current
WebSocket URI method is only a seam, not evidence of an implemented socket
transport.

## Rejected alternatives

- Deriving `ServerId` from a URL, which would make endpoint changes look like
  a new server and would not distinguish alternate endpoints consistently.
- Using a Jellyfin system ID as the app identity; the current app does not
  obtain and persist it as a stable configuration record.
- Mutating an existing client from one user/token to another.
- Putting Headscale, mesh-node, LAN-vs-private, or direct-path policy in
  Jellyfin protocol code.
- Replacing the validated resolver, allowing relay/media proxying, following
  external redirects, or falling back to public URLs after private failure.
- Adding a database, multiple-server UI, cross-server aggregation, or
  WebSocket implementation in this phase.

## Migration considerations

Existing server URL, user ID, and secure-token keys are preserved. A new
nonsecret UUID key is generated once for the current single-server slot; no
credential migration or mesh identity reset is required. New persisted media
records should use `ServerMediaItemId` (or the same composite tuple). The
future registry must explicitly migrate the current slot into a configured
server record before multiple-server data or cache is introduced.
