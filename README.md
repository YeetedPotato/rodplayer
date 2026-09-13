# Remux

Remux is the next chapter of RodPlayer: a high-performance Jellyfin client designed to deliver an Infuse- and Plex-class media experience with a distinctive Obsidian Glass interface, internal playback intelligence, and deep platform optimizations.

Formerly known as RodPlayer, Remux is focused on making playback feel effortless while exposing the right amount of useful context when something needs attention.

## Mission

Remux combines:

- A polished Jellyfin client experience comparable to Infuse and Plex.
- Obsidian Glass UI: a layered, cinematic design language built for clarity and focus.
- Internal playback intelligence that selects the right playback strategy for each device, stream, and network condition.
- Deep platform optimizations across desktop, mobile, and living-room experiences.
- Reliable playback recovery so transient stalls do not become failed viewing sessions.

## Phase 7: Complete

Phase 7 completes the core playback-intelligence transition from RodPlayer to Remux:

- Migrated playback call sites to `RemuxEngine`.
- Added native session handoff for smoother transitions between playback surfaces and platform sessions.
- Added real-time HUD telemetry through an Obsidian Glass badge.
  - Displays the current decision reason.
  - Exposes `PlayMethod` indicators such as direct play, direct stream, or transcoding.
- Added stall detection with automated playback recovery.
- Consolidated playback decisions and recovery behavior behind a coherent coordinator architecture.

The result is a playback path that is observable without being distracting, adaptive without being opaque, and resilient when real-world network or device conditions change.

## Architecture

### PlaybackCoordinator

`PlaybackCoordinator` is the orchestration layer for playback. It coordinates stream selection, playback state, native session handoff, telemetry, and recovery actions while keeping UI components independent from playback policy.

### StallDetector

`StallDetector` monitors playback progress and timing signals to distinguish a normal buffering event from a genuine playback stall. When recovery is appropriate, it initiates the automated recovery path and reports the outcome back through the coordinator.

### RemuxClient

`RemuxClient` is the client-facing playback intelligence layer. It evaluates the available media, device capabilities, network conditions, and Jellyfin playback options to select an appropriate playback method and provide a reason that can be surfaced in the HUD.

### Obsidian Glass

Obsidian Glass is Remux's visual language for a focused, cinematic interface:

- `surface0` through `surface4` provide progressively elevated dark surfaces.
- Gold `#EBCF52` is used for emphasis, active decisions, and playback intelligence signals.
- Green `#1C3421` anchors the deeper system palette and recovery-oriented states.
- Layered translucency, restrained contrast, and clear hierarchy keep telemetry useful without overwhelming playback.

## Roadmap

### Phase 8

- Benchmark stall recovery across representative devices, codecs, and network conditions.
- Tune multiplatform playback profiles for consistent behavior across supported targets.
- Perfect the tvOS and 10-foot UI experience for large-screen navigation and playback control.

## Project Naming

Remux is the current project name. RodPlayer is the former name and may still appear in historical code, commits, or migration references.
