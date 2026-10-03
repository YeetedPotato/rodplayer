# Watch Together implementation plan

**Status:** Local room-state and drift-control foundation implemented; no authenticated room transport or participant playback service.

**Current foundation:** Typed server-scoped media identity, host/guest authority, bounded monotonic packet state, clock-offset/drift policy, and reorder/reconnect tests exist. No room signaling, participant transport, media relay, or network protocol is enabled.

## Trust and room ownership

Each participant streams from their own one active Jellyfin/Remux-compatible
server and account. Coordination carries only room/control state. It must never
carry media bytes, stream URLs, Jellyfin tokens, Headscale credentials, or
private gateway secrets. A room ID is opaque and distinct from server/item IDs.
Participant identity is an ephemeral/pairing identity, not a Jellyfin account.

Initially the room host is authoritative for play/pause/seek and room-item
selection. Guests may request controls; the host accepts/rejects requests.
Host transfer is deferred. Every room message is versioned, authenticated,
sequenced, timestamped monotonically per participant, bounded in size/rate, and
associated with room generation and current item epoch. Reject late/replayed
messages after room, item, or playback generation changes.

## Synchronization model

Exchange playback intent and item identity only when each participant can map
the item to their own active server under an explicit product mapping; never
search/merge servers implicitly. If no local equivalent exists, participant is
out of sync and may leave or choose a local item with host approval.

Estimate clock offset and uncertainty with repeated round trips; use monotonic
clocks, not wall time, for drift calculations. Include host event time,
sequence, desired play state, logical position, rate, and item epoch. Smooth
small drift with a bounded seek/rate correction supported by the active backend.
Use thresholded seek for large drift; do not repeatedly seek while buffering,
paused, or capability unknown. Local engine position remains authoritative for
local rendering and reports to that participant's server through current
reporting ownership.

Source and episode transitions are explicit room item-epoch changes. Use the
existing PlaybackInfo and runtime transaction; never invent cross-item session
ownership or issue direct stream URLs. Until a robust authoritative transition
exists, disable shared next/episode advancement and let each user continue
locally.

## Connectivity and versioning

Use an authenticated coordination channel over reviewed secure primitives. The
service is control-only and must not become a media proxy. Define protocol
capability/version negotiation, reconnect snapshot, participant leave/expiry,
room close, stale-host detection, bounded retry/jitter, and explicit unsupported
operation outcomes. Reconnect invalidates old sequence/item epochs before any
command can apply. Do not use private-network membership as room authentication.

## Implementation sequence and tests

1. Protocol threat model, service boundary, room/participant lifecycle.
2. Authenticated room creation/join/leave, generation and sequence validation.
3. Clock-offset estimator and deterministic simulation tests under latency,
   jitter, packet loss, pause, buffering, and wall-clock jumps.
4. Local item mapping and host-authorized item transition contract.
5. PlaybackCommandController adapter with explicit host/guest role authority.
6. UI presence, invite/revoke, reconnect, and accessibility/focus states.

Tests cover replay/stale messages, room generation, unauthorized guest command,
host closure/leave, clock uncertainty, drift thresholds, buffering/seek
capability, source replacement, item mapping failure, reconnect snapshot,
protocol mismatch, and proof that media URLs/credentials never enter room
messages. Keep all cross-server aggregation prohibited.
