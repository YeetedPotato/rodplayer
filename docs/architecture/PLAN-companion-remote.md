# Companion Remote implementation plan

**Status:** Safe local protocol foundation implemented; authenticated transport and pairing remain disabled.

**Current foundation:** Typed control envelopes, a bounded session-scoped replay window, rate limiting, device metadata, and a command bridge exist. The default playback authority rejects Companion-origin commands. There is no listener, cryptographic session establishment, or authenticated pairing flow.

## Security and authority model

Companion Remote is a control plane. Nautilus never proxies media, exposes a
Jellyfin token, or shares Headscale/enrollment credentials. A phone sends
least-privilege typed commands to the currently active desktop/TV playback
session. It cannot choose a server/account, build a media URL, select an
arbitrary source, or bypass local capability checks.

Pair only after an explicit user-visible short-lived pairing action. Display a
high-entropy one-time code/QR over a supported local transport; bind it to a
device identity and short expiration. Use a maintained reviewed secure channel
and standard platform crypto/TLS primitives; do not invent cryptography or
trust LAN membership. Persist only revocable device public identity and
scoped credential material in OS secure storage. Never persist pairing codes.
Provide per-device revoke and global revoke, expiry, and key rotation.

## Protocol envelope

Every request carries protocol version, paired device ID, unique command ID,
monotonic sequence, issue/expiry bounds, active playback session ID and
generation, typed command, and authenticated integrity. Reject stale generation,
expired/replayed sequence, unknown command/version, oversized payload, and
unauthorized operation before dispatch. Bound message size, concurrent requests,
per-device request rate, and outstanding acknowledgements. Deduplicate command
IDs within a bounded persistence/memory window; acknowledge outcome without
returning credentials or stream URLs.

`PlaybackCommandController` remains the only command authority. Companion origin
stays denied until pairing, sequence/replay, permission, and revocation tests
pass. Remote role initially permits only basic current-session controls; local
user retains server selection, account, playback source, subtitle/audio policy,
and privacy settings. Explicitly surface the active receiving device and revoke
state.

## Connectivity and recovery

Prefer an authenticated control channel on a user-authorized LAN/private route.
Do not bind an unauthenticated all-interface listener. If private networking is
required, reuse the existing app-scoped direct-only policy; never permit DERP or
OCI media/control relay as an implicit fallback. Define mDNS/discovery as an
optional hint only, not trust. Reconnect reauthenticates the paired device and
resynchronizes a minimal current playback snapshot; queued old-generation
commands are discarded. Pairing revocation terminates live channel/session.

## Implementation sequence and tests

1. Threat model and selected maintained secure transport/library review.
2. Device registry in secure storage, one-time pairing, expiry, revoke, rotation.
3. Authenticated control session with bounded framing/rate limits and no
   credential leakage.
4. Strict envelope/replay validator and typed command adapter.
5. Minimal current playback state snapshot and reconnect generation handling.
6. Native Windows/macOS/Android TV listener lifecycle and permission UX only
   after platform-specific security review.

Tests: pairing expiry/replay, device revoke, wrong key, sequence rollback,
duplicate command dedupe, expired session generation, capability denial,
rate/size limits, malformed framing, reconnect, listener disposal, no secret
serialization/logging, unauthorized-origin denial, and LAN/private direct-only
failure. Add an integration test proving command authority cannot alter
PlaybackInfo/reporting ownership. Do not ship a listener before security review.
