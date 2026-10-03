# Live TV implementation plan

**Status:** Typed API/repository and local tune-session foundation implemented; no Live TV UI or production runtime integration.

**Current foundation:** Channel/program DTOs, bounded guide queries, unknown-by-default capability reporting, PlaybackInfo tune negotiation, and retune/disposal state tests exist. There is no channel/guide UI, production live-session reporting/runtime binding, DVR, or live-server validation.

## Boundaries and prerequisites

Live TV stays inside exactly one `ActiveServerContext`; channel and program
keys must include server/account provenance. Gate all entry points on verified
server capability and explicit API availability. Do not assume a server exposes
Live TV because a route exists. Confirm `/LiveTv/Info`, channel, program, tune,
recording, and media-source behavior against each supported Jellyfin/Remux
server before implementation. Keep `PlaybackInfo` and its returned plan
authoritative. Media continues through the existing direct-only transport; no
proxy/relay fallback.

## Proposed ownership and data

- `LiveTvCapability`: unknown/supported/unsupported plus server-specific
  details, scoped to the active `ServerSession` and cached only for that
  session generation.
- `LiveTvRepository`: maps typed channel/program/guide/recording DTOs and owns
  route/paging details. It calls the active session's `JellyfinApiClient`; it
  never selects a server or endpoint.
- `LiveTvChannel`: server/account-scoped ID, display name, channel number,
  source metadata, and only server-provided image identifiers.
- `LiveTvProgram`: scoped ID, channel provenance, UTC start/end, title,
  description, and server-provided episode/artwork metadata.
- `GuidePage`: time range, channel filters, opaque paging state, and explicit
  partial/empty/error state. Bound query windows and page sizes.
- `LivePlaybackSession`: a typed wrapper around the existing logical playback
  session/coordinator and authenticated server session. It does not own an
  independent player, reporting loop, or URL builder.
- `LiveTimeline`: distinguishes current wall-clock/live edge, seekable capture
  window, and unseekable live source. Clamp seeks to the server/runtime's
  actual seekable range; represent lack of range as unsupported.

## Tuning and playback transaction

1. Resolve channel and verify it belongs to the active server/account/generation.
2. Request server-generated playback information using the actual tuner/channel
   contract verified for that server.
3. Validate the returned plan and active direct-only route through existing
   playback negotiation/runtime authority.
4. Preserve the current session until the existing coordinator accepts the
   replacement; on failure keep the old session if its transaction boundary
   allows it, otherwise surface its established safe error path.
5. Start reporting only through existing logical-session ownership. Stop the
   prior server session exactly once according to the existing reporting
   lifecycle.

Channel changes use the same transaction. Do not create an arbitrary stream
URL from a channel ID. Retry only through current playback recovery policy.
For unseekable streams, hide/disable seeking rather than pretending a DVR
window exists. DVR is a later capability-gated extension; recording requests
need idempotency and server confirmation.

## UI, commands, and platform input

Reuse player chrome and typed playback commands where supported. Add a Live TV
OSD mode for live edge/time-shift state, channel/program details, and truthful
seek capability. TV/D-pad traversal must keep channel list, guide, tune action,
and player controls reachable without a focus trap. Provide a clear Back path
to the prior channel/guide; do not silently auto-tune another channel on
failure. Capability-specific sections are absent when unsupported.

## Delivery phases and tests

1. Capability and API contract discovery; tests for unsupported/malformed
   capability responses and no cross-server calls.
2. Typed DTOs/repository; test paging, UTC boundaries, empty guide, malformed
   items, cancellation, and active-generation rejection.
3. Playback negotiation integration; fake server/runtime tests for tune success,
   denied private route, relay denial, no public fallback, failed tune retaining
   the old active runtime, reporting start/terminal exactly once.
4. Timeline capability model; test live edge, finite capture window, expired
   window, and unseekable source clamping/disabled seeking.
5. Capability-gated guide/channel UI and keyboard/D-pad focus tests.
6. DVR only after product/API confirmation; test schedule conflict, cancellation,
   idempotent retry, and server-confirmed lifecycle.

Likely files: `lib/core/api/models/live_tv_*`,
`lib/core/live_tv/live_tv_repository.dart`,
`lib/core/playback/live_playback_session.dart`, capability additions in the
server session, then focused screens/widgets and tests. Keep each phase
separately reviewable.
