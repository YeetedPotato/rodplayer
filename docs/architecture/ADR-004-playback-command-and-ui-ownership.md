# ADR-004: Playback commands and player UI ownership

**Status:** Command authority and chrome controller implemented; integrated player surfaces route supported inputs through them.

## Context

Playback currently has a backend-neutral `PlaybackRuntimeCoordinator`, a
logical playback session, backend-specific `PlaybackEngine`, optional advanced
controls, and track-selection controllers. Player widgets can still reach
these operations directly. Future keyboard/D-pad, system media, Companion
Remote, and Watch Together inputs need one authority and a way to reject
commands captured for a replaced runtime.

## Decision

`PlaybackCommandController` is the first typed control surface. Commands are
small immutable values; a request carries origin and a
`PlaybackCommandTargetId` consisting of logical-session ID and runtime
generation. `forCoordinator` adapts the current active runtime without
creating another playback owner. A request is rejected when there is no
runtime, its target no longer matches, the origin is not authorized, or the
active runtime does not advertise the requested optional capability. Runtime
errors produce a safe typed failure result.

Play, pause, toggle, stop, absolute/relative seek, volume, playback rate, and
audio/subtitle selection are represented. Core engine operations use the
existing `PlaybackEngine`; rate and track operations use runtime-scoped
capabilities and existing advanced/track interfaces. Volume keeps the current
0–100 contract. Relative seeks clamp at zero. The controller does not negotiate
PlaybackInfo, select a backend, report progress, own recovery, or build URLs.

Origins include local UI, keyboard, D-pad, system media, Companion Remote, and
Watch Together. Only local UI, keyboard, D-pad, and system media are currently
authorized. Companion and Watch Together commands are denied until pairing,
host authority, replay protection, and remote session ownership are designed
and implemented.

`PlaybackTrackIntent` stores user preference (language, forced/SDH/CC,
commentary, channel count), not backend/native track IDs. A
`ScrubPreviewSource` accepts a time and returns optional frame bytes; it does
not expose Jellyfin trickplay URL construction to the timeline.

## Ownership boundary

Playback session state remains with the logical session/coordinator/runtime:
session identity, selected plan/source, position, playing state, tracks,
buffering, errors, and runtime identity. PlayerChromeController owns OSD
visibility, auto-hide timing, input mode, modal/scrub/interaction holds, and
bounded transient feedback. The architecture view and integrated OSD consume
this owner; the view translates pointer, focus, and key events into controller
updates while preserving existing presentation and gestures. Fullscreen remains
a window-presentation operation rather than a media-engine command.

## Replacement, idempotency, and future origins

The command target uses the published active generation. While negotiation,
opening, or preparation is pending, mutating commands return
`transitionInProgress`; harmless chrome/focus remains interactive. Source
switching holds this gate from position capture through activation completion.
After replacement, captured targets are stale. Non-local audio returns typed
`needsServerRenegotiation` or `externalAttachRequired`, never fake execution;
audio renegotiation remains unavailable here. Late retired track completions
cannot overwrite logical stream selections.
Commands already in flight are not cancelled by this controller, so a future
remote adapter must add cancellation/acknowledgement semantics.

Runtime plan and complete binding commit synchronously. Commit observers are
post-commit notifications; their failure is diagnostic, not rollback. Disposal
or supersession during an observer await cannot republish the old binding or
report a successful current activation. Reporting independently tracks an
acknowledged old stop and a pending new start, retrying only on a later explicit
report operation. Native actual-position and failed-switch rollback caveats
remain deferred.

The central command controller does not persist command IDs. The disabled
Companion bridge validates message IDs with a bounded, expiring replay window
scoped to device, logical session, and runtime generation before dispatch.

Source replacement uses the dedicated PlaybackSourceSwitchCoordinator and the
existing PlaybackInfo/runtime/reporting boundaries. Cross-item episode
next/previous remains deferred because it requires a robust logical-session
handoff; the player does not fabricate a local queue. Seek-preview remains an
optional source contract without Jellyfin trickplay URL construction. Fullscreen
remains with the window presenter. In particular, this ADR does not alter known
native resume, source-switch rollback, or actual-position issues.

## Rejected alternatives

- A dynamic string/map command bus.
- Widgets calling backend-specific player objects as a future remote API.
- Treating backend presence as proof that rate/track support exists.
- Putting OSD visibility/focus state in playback state.
- Replacing the existing coordinator, PlaybackInfo authority, reporting, or
  recovery ownership.
