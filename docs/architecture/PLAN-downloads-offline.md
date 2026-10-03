# Downloads and offline implementation plan

**Status:** Metadata and outbox foundation implemented; media download execution is not implemented.

**Current foundation:** Server/account-scoped job metadata and watch-action outbox have bounded versioned preference stores. They contain no credentials or media bytes. There is no managed file store, downloader, background scheduler, or transactional database; the plan below remains required before offline downloads are enabled.

## Persistence prerequisite

Before implementation, migrate configuration to a versioned relational store
with transactional migrations. Keep server/account IDs and download-job rows
relational; keep access tokens in OS secure storage; keep media bytes in a
managed filesystem. SharedPreferences remain appropriate only for small device
preferences. No credential or stream URL is an exportable preference.

## Ownership and models

- `DownloadJob`: stable job ID, scoped `(ServerId, ServerAccountId, ItemId)`,
  selected server-provided source/version, state, byte counts, retry state,
  timestamps, and schema revision. No token.
- `DownloadedMedia`: scoped owner, managed relative asset ID/path, verified
  length/checksum where supported, source metadata, completion time, and pinned
  or eviction state.
- Managed storage owns opaque app paths and atomic temporary-file-to-final
  rename. Never accept arbitrary filesystem paths from a server or UI.
- Quota policy reports storage pressure before eviction. Evict only completed,
  unpinned assets using explicit least-recently-used policy; never evict a
  partial job as if it were playable.

## Job lifecycle

Model queued, resolving, downloading, paused, retry-wait, verifying, complete,
cancelled, and failed distinctly. Pause/resume/cancel are idempotent. Refresh
credentials through the selected account's secure reference at request time;
never copy tokens into job rows, logs, or worker arguments. Every job captures
active server/account generation and server-provided source identity. A server
switch pauses or detaches jobs by policy; it must not silently retarget them.
Resume retries validate the same owning server/account and selected source.

Offline playback uses a local source adapter under existing playback plan and
runtime authority, not a second player/session stack. Keep downloaded and
streamed reporting semantics explicit; do not issue server progress while
offline without an outbox policy.

## Watch-progress outbox

Persist versioned outbox operations keyed by server/account/item and stable
operation ID. Include desired watched/progress state, source revision, and
creation sequence; never include bearer credentials. On reconnect, refresh
current server state and resolve conflict deterministically: explicit manual
watched/unwatched intent outranks periodic timeupdate; newer monotonic user
intent outranks older local operation; server response remains authoritative
when revisions cannot be compared. Make each replay idempotent and retain
conflicts for user-visible resolution rather than silently overwriting.

## Platform execution and delivery

Background execution differs by Windows, macOS, iOS/iPadOS, Android/TV, and
future tvOS. Implement a platform scheduler abstraction with truthful
capabilities, foreground continuation, OS cancellation, bounded concurrency,
and no promise of uninterrupted iOS work. Start desktop/mobile foreground jobs
first; only then add platform background scheduling individually.

## Implementation phases and tests

1. Relational schema/migrations, recovery after interrupted migration, and
   secure credential-reference validation.
2. Managed storage/quota/temp-file recovery and checksum tests.
3. One server/account download queue with pause/resume/cancel, retry, auth
   refresh, source change rejection, and server/account isolation.
4. Offline source adapter and playback/reporting tests.
5. Versioned progress outbox, idempotent replay, conflict precedence, and
   reconnect tests.
6. Platform scheduling capability matrix, cleanup/eviction, and UI.

Test crash/restart at each state transition, duplicate callbacks, partial file
cleanup, quota exhaustion, permission denial, revoked/missing credentials,
account switching, deleted server, source changes, outbox replay duplication,
conflicting watched state, and secret redaction. No downloads should be built on
the Phase 3 preference snapshot.
