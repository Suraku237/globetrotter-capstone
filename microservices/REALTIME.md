# Low-data live updates

## Wire protocol

Connect to the gateway's `/events/ws` (prepend the deployment's existing `/api`
prefix). Replace `http` with `ws`, or `https` with `wss`. The first **text** frame,
within 10 seconds, must be `{"token":"ACCESS_JWT"}`. Never put tokens in URLs,
query strings, cookies, logs, or socket subprotocols. Query strings are rejected.
The data service uses the same JWT signature, expiry, purpose, and existing-user
checks as HTTP authentication. A scoped approval token is not an access token.

Server frames contain only cache metadata:

```json
{"type":"ready","topics":["all"]}
{"type":"invalidate","topics":["friends"]}
{"type":"invalidate","topics":[]}
```

- `ready` always requires a fresh authoritative HTTP resync of active/subscribed
  resources, including on the first connection, **every reconnect**, and after
  journal retention overtakes a slow subscriber. Do not interpret it as "cache is
  current". A server-side watermark taken before ready avoids the initial-fetch
  race. No client event cursor or event replay payload is needed.
- `invalidate` marks only the named caches stale; coalesce bursts and refresh only
  visible/active resources. Persist existing HTTP values for offline display.
  An invalidation is not a new message, a call offer, or proof of access.
- Empty `topics` is the 25-second application heartbeat, not a cache flush. The
  server rechecks JWT/user validity at least every heartbeat; existing sockets
  lose access within this interval after expiry/deletion. Clients may send
  `{"type":"ping"}`; this does not renew a call's HTTP lease.
- Close `4401` means authentication failed/expired; authenticate again rather than
  endlessly retrying the same token. `4400` means malformed protocol, `1009`
  oversized frame, and `1013` temporary overload/unavailability/auth timeout.
  Reconnect with jittered exponential backoff after network/server failures, and
  on foreground/resume. Use a modest HTTP fallback while a socket is unavailable.

| Topic | Audience and mutations |
| --- | --- |
| `friends` | Both requester and recipient on send/accept/decline/cancel; both participants on private messages; all group members on group creation/message; profile owner and their friends/groups on profile changes |
| `calls` | Original call participants on creation, acceptance, departure, ringing expiry, lease expiry and membership-driven changes; not routine leases or provider retries |
| `chat` | All authenticated subscribers: public community text/sticker/audio/image sends, reactions and soft deletes |
| `posts` | All authenticated subscribers: post creation, likes, comments and deletion |
| `destinations`, `recommendations` | All authenticated subscribers: destination creation/edit/moderation |
| `itineraries` | Creating user only |
| `profile`, `recommendations` | Changed account only |
| `stats` | All authenticated subscribers: visitor/download counts and changed account membership |

No user IDs, JWTs, device tokens, room IDs, messages, or private call payloads are
sent on this stream. Server-side audience filtering is mandatory and cannot be
overridden with subscription frames. Existing private messages use audience-limited
`friends` invalidations; `chat` means the existing **one public community room**,
not a new DM system.
Existing FCM, APNs PushKit/CallKit, native call lifecycle and LiveKit are unchanged.
Call invalidations are persisted before slow provider delivery; a socket is never
required to receive a push, accept a call, fetch signalling, or carry media.

## Bounded message history

`GET /chat/room/messages?limit=50&before=MESSAGE_ID` returns the same message-array
shape, oldest-to-newest within that page. `limit` is optional, 1–200. With a limit
and no cursor, return the latest messages. `before` is an exclusive existing
message ID; use the first message of the current page to load older messages.
Unknown IDs return 404; invalid limits return 422; reaching the start returns `[]`.
Soft-deleted messages remain valid cursors. Omitting both parameters preserves the
legacy full-history response. Audio/images still travel only through their media
URLs. Pagination bounds transferred data, not the legacy JSON store's disk reads.

The existing private lists `GET /social/friends/{friend_id}/messages` and
`GET /social/groups/{group_id}/messages` accept the identical optional `limit`
and `before` parameters, with the same chronological array, latest-page selection,
message-ID cursor, validation and full-history default. Friendship/group membership
is checked before any cursor lookup. Clients can safely request `limit=50` on all
three message-list routes and load older pages using the oldest displayed ID.

## Persistence and deployment

`events.sqlite3` lives in the already-shared `/app/data` local volume used by auth
and data services. SQLite WAL and transactions provide **cross-process** delivery,
including auth-service profile changes, without introducing a broker. Each
subscriber checks the journal every 500 ms; it reads at most 128 matching records
at a time and coalesces topic names. Only the latest 2,048 small metadata rows are
retained. There is no unbounded in-memory subscriber queue. Writes prune in the
same transaction; old pages are reused by SQLite. Keep the database and its WAL/
SHM files private; never expose the entire data directory over HTTP.

Both gateway and data-service Docker commands limit WebSocket frames to 8 KiB and
receive queues to four frames, with 20-second transport ping/pong deadlines.
Application sends time out after five seconds. The gateway forwards text/close
codes, uses a bounded upstream queue and cancels both forwarding tasks on exit.
Rebuild the gateway, data and auth images together. Gateway and data now explicitly
pin the tested `websockets==12.0` dependency. Outside Compose, both services must point to the same physical
data directory, and use the same WebSocket limits.

The edge reverse proxy/load balancer **must** forward HTTP/1.1 `Upgrade` and
`Connection: upgrade` on `/api/events/ws` to the gateway, with an idle timeout
longer than 25 seconds (60+ recommended). HTTPS deployments require WSS. No gateway
port, JWT secret, push credentials, or additional environment settings change.

Limitations:

- SQLite supports multiple journal writers/readers on a **single local disk**;
  do not place WAL databases on NFS or split instances across unrelated volumes.
  Distributed deployment needs a real shared broker/transactional datastore.
- This does **not** make existing JSON business stores or call-provider job
  dispatch multi-worker safe. Retain the documented **one data-service worker /
  replica** until those stores and jobs are migrated. The invalidation mechanism
  itself is not an in-memory, single-worker broadcaster; subprocess regression
  coverage verifies other-worker delivery.
- JSON saves and journal appends are separate commits. A process/disk failure
  between them can miss an invalidation; HTTP remains authoritative, ready resync
  repairs reconnects, and clients should keep a low-frequency safety refresh.
  SQLite/storage failures can fail mutations after their JSON write. A fully
  atomic transactional outbox requires moving business data into the database.
- The service still stores full community history as JSON. Concurrent writes,
  history retention, media authorization, and multi-node storage are not changed
  by response pagination or this metadata-only protocol.

## Validation

Use the existing pytest runner from `data-service`, with a test JWT secret and
project-local `--basetemp`, selecting `tests/test_events.py`,
`tests/test_event_gateway.py`, `tests/test_calls.py`, `tests/test_social.py` and
`tests/test_stats.py`. Auth profile-save coverage is in
`auth-service/tests/test_profile_events.py`. Tests use isolated journals and mock
provider delivery; no real Firebase, APNs or LiveKit credentials are needed.
