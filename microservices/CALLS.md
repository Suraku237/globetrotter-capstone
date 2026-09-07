# Private voice/video calls

The data service provides authenticated direct/friend and private-group signalling,
LiveKit Cloud room-scoped JWTs, Android/web FCM, and real iOS APNs PushKit delivery.
Media goes directly to LiveKit Cloud, **not** through the API gateway. No recordings,
public rooms, screen sharing, or server-side media are enabled.

## Deployment configuration

Keep these values in the existing **untracked** `microservices/.env` or your
deployment secret manager. The following are placeholders, not working credentials:

```dotenv
LIVEKIT_URL=wss://YOUR-PROJECT.livekit.cloud
LIVEKIT_API_KEY=YOUR_LIVEKIT_SERVER_API_KEY
LIVEKIT_API_SECRET=YOUR_LIVEKIT_SERVER_API_SECRET
CALLS_PUBLIC_APP_URL=https://YOUR-PUBLIC-FLUTTER-WEB-HOST
APNS_KEY_ID=YOUR_10_CHARACTER_APPLE_KEY_ID
APNS_TEAM_ID=YOUR_10_CHARACTER_APPLE_TEAM_ID
APNS_VOIP_TOPIC=YOUR_IOS_BUNDLE_ID.voip
APNS_ENVIRONMENT=production
```

1. Create a LiveKit **Cloud** project; obtain its server API key/secret and `wss`
   URL. Never place these secrets in Dart, JavaScript, an app asset, or a public
   Firebase configuration. Cloud token revocation is required; self-hosted
   LiveKit is not a supported substitute for the same security guarantees.
2. Enable Firebase Cloud Messaging HTTP v1 in the same Firebase project used by
   the applications. Use the existing deployment file
   `microservices/firebase-service-account.json`, with permission to send FCM
   messages. Compose mounts it **read-only** in the data service at
   `/run/secrets/fcm-service-account.json` and sets
   `GOOGLE_APPLICATION_CREDENTIALS` to that path. Do not add this file to source
   control. Android `google-services.json` and the web Firebase/VAPID configuration
   identify the client app; they are not substitutes for this server credential.
3. Generate an Apple APNs token-signing key with appropriate access to your iOS
   app. Store it as the ignored deployment file
   `microservices/secrets/apns/AuthKey.p8`. Compose mounts the containing directory
   read-only at `/run/secrets/apns` and sets
   `APNS_KEY_FILE=/run/secrets/apns/AuthKey.p8`. Create the directory even if iOS
   push is not being configured. Only this directory, not all backend secrets,
   is mounted. Set `APNS_VOIP_TOPIC` to the exact signed iOS bundle identifier plus
   `.voip`. Use `sandbox` for development-signed builds; TestFlight/App Store use
   `production`. Tokens are environment/topic-specific.
4. For **iOS cancellation via FCM**, additionally configure the APNs key in
   Firebase Console for the iOS application. The backend's direct PushKit key
   configuration does not configure Firebase's ordinary APNs transport.
5. Rebuild/recreate the data service using your normal Compose deployment.
   The manifest adds `firebase-admin==6.5.0` and HTTP/2 support to the existing
   `httpx==0.27.2`; production Docker continues to use Python 3.11. There is no
   additional local LiveKit container.

For deployment without Compose, set `GOOGLE_APPLICATION_CREDENTIALS` and
`APNS_KEY_FILE` to the corresponding readable, private absolute file paths.
`JWT_SECRET` remains required and must match the auth service. Keep HTTPS enabled
on the public API and web app; permit outbound HTTPS to Firebase, Apple and
LiveKit, and client WebRTC/WebSocket connectivity to LiveKit Cloud.

Do not publish `calls.json`, `call_devices.json`, their `.writing` files, or
the `/app/data` volume. Device tokens are stored privately, not returned by any
API, but still require restrictive filesystem permissions and protected backups.
Only images/audio are public mounts. Retain exactly **one data-service process /
Uvicorn worker / replica**, as with the existing JSON-backed social feature.
Multiple workers/replicas require a transactional database and shared job queue
before scaling. Writes use the existing social mutex and atomic replacement.

## API contract

Every endpoint below requires the current user's bearer token. Gateway paths are
unchanged; if your reverse proxy prefixes the API with `/api`, prepend it below.

| Method / path | Body | Response |
| --- | --- | --- |
| `POST /social/calls` | `{"kind":"voice" or "video","target_type":"direct" or "group","target_id":"USER_OR_GROUP_ID"}` | call |
| `GET /social/calls/incoming` | none | list of pending invitations for this user |
| `GET /social/calls/{id}` | none | call |
| `POST /social/calls/{id}/token` | none | `{"call":call,"url":"wss://…","token":"JWT"}` |
| `POST /social/calls/{id}/accept` | none | same join response |
| `POST /social/calls/{id}/decline` | none | call |
| `POST /social/calls/{id}/leave` | none | call |
| `POST /social/calls/{id}/heartbeat` | none | call |
| `POST /social/call-devices` | device below | `{"ok":true}` (200) |
| `DELETE /social/call-devices` | same device body | `{"ok":true}` (200) |

```json
{
  "id": "CALL_UUID",
  "kind": "voice",
  "target_type": "direct",
  "target_id": "RECIPIENT_USER_ID",
  "title": "Recipient name",
  "caller_id": "CALLER_USER_ID",
  "caller_name": "Caller name",
  "caller_avatar_url": null,
  "status": "ringing",
  "created_at": "2026-09-07T00:00:00+00:00",
  "expires_at": "2026-09-07T00:00:45+00:00",
  "participant_ids": ["CALLER_USER_ID", "RECIPIENT_USER_ID"],
  "accepted_ids": ["CALLER_USER_ID"],
  "ended_reason": null
}
```

- `title` is personalized on **every response**: the other participant's current
  full name for direct calls (callee sees caller; caller sees callee), or the
  group's name. Use `caller_name` when displaying an incoming call.
  `caller_avatar_url` always belongs to the caller, including outgoing responses;
  do not use it as the callee's avatar on an outgoing call screen.
- `participant_ids` is the original invitation membership snapshot.
  `accepted_ids` is the **current** joined/signalling participation set, initially
  containing the caller. An active call can have one remaining group participant.
- `expires_at` is the **invitation** deadline (45 seconds), not the active call's
  lifetime. It does not advance on heartbeat. A group invitation may remain
  pending while other members have already accepted.
- `/token` is available only to the caller or an already accepted member.
  `/accept` accepts the invite and issues credentials together. Repeated accepts
  are safe while participating; a failed token configuration does not accept.
  Invitations require accepted friendship or current group membership. Removed
  members are denied and queued for LiveKit removal, including during polling.
  Newly added group members do not gain access to an earlier invitation.
- Send `/heartbeat` **every 10 seconds** while joining or connected. Token issue,
  accept, and heartbeat renew a **55-second participant lease**. A separate
  five-second sweep handles unanswered/unjoined calls even with no client traffic.
  For token-holding participants in an **active** call, a missed HTTP heartbeat
  first triggers a server-side LiveKit `GetParticipant` check: connected native
  WebRTC participants retain their membership and renew the lease even if the
  mobile OS suspends Dart timers. Confirmed absent/disconnected participants
  expire; a direct disconnect ends the direct call, while an active group loses
  only that participant. A LiveKit control-plane error is logged and retried,
  **not** treated as absence; stale busy state can therefore persist during an
  outage. Presence checks run outside the signalling lock, and a concurrent fresh
  heartbeat or explicit leave takes precedence over an older query result.
  Keep the native call session/foreground service alive for background media.
- Direct decline ends the call; caller leave while ringing cancels it; either
  participant leaving an active direct call ends it. Group decline removes only
  that invitation; all invitees declining ends the ringing call. Group caller
  cancellation before acceptance ends the call; leaving an **active** group call
  preserves others. The last group participant leaving ends it.
- Declined, departed, lease-expired, and expired-invitation participants cannot
  rejoin the same call. Ended call `/token` and `/accept` return 409; terminal
  `/leave`, `/decline`, and `/heartbeat` return the persisted terminal state.
  A late `/decline` after acceptance returns 409: use `/leave`.
- A user may have only one live invitation/participation at a time. Busy direct
  recipients or an entirely busy group return 409. Busy group members are skipped
  for that call, while available members are invited.
- Repeated creation for the same caller/kind/target returns their live call.
  Optional `Idempotency-Key` (max 128 characters) also deduplicates retries after
  termination; reusing a key with a different payload returns 409. Generate a new
  key for an intentional new call. Every new call and every room gets a distinct
  UUID, never a stable friend/group room name.
- Caller JWTs contain only a single-room join grant, user identity, subscription,
  and microphone publishing (plus camera for video). Voice JWTs **cannot publish
  camera or screen tracks**. No client gets admin/create/data-publishing grants.
  Initial token TTL is 45 seconds; LiveKit handles reconnect-token refresh.
- Unauthorized outsiders see 404, changed membership sees 403, invalid payloads
  422, busy/stale transitions 409, missing LiveKit configuration 503.
  `ended_reason` can be `declined`, `cancelled`, `participant_left`,
  `last_participant_left`, `no_answer`, `connection_lost`, `membership_changed`,
  or `caller_left`.

Provider cleanup is persisted and retried, rather than rolling back successful
leave/decline. A five-second dispatcher calls LiveKit `RemoveParticipant` for
every departed token holder (Cloud also revokes tokens for an absent participant),
then `DeleteRoom` for terminal calls. Only explicit `not_found` is treated as
already clean. Provider failures are logged with call IDs, never tokens/keys.
During a provider outage, API access remains revoked immediately but media
removal is delayed until cleanup succeeds. Monitor “cleanup pending” and “push
delivery pending” warnings. Restarting the backend resumes persisted work.

## Device registration and push payloads

```json
{"token":"PLATFORM_REGISTRATION_TOKEN","platform":"android","kind":"fcm"}
```

Platforms are `android`, `web`, or `ios`; kinds are `fcm` or `voip`.
`voip` requires iOS and a 64-hex-character PushKit APNs token. iOS should register
**both** its PushKit token (`ios`/`voip`) and Firebase messaging token (`ios`/`fcm`):
the latter is used only to end ringing, not to originate a VoIP call.
Register after authenticated login and token refresh. There is a maximum of 20
registrations per user. Ownership moves atomically when a token is registered by
a different account; an old account cannot delete a new account's registration.
The same authenticated DELETE is idempotent and must complete **before** clearing
the session during logout. Queued delivery resolves current ownership again;
signalling stays responsive while device deletion waits for an in-flight send.

Incoming data (all strings):

```json
{"type":"incoming_call","call_id":"CALL_UUID","caller_name":"Alice","kind":"voice","expires_at":"2026-09-07T00:00:45+00:00"}
```

Cancellation, decline, expiry, or acceptance on another device:

```json
{"type":"call_ended","call_id":"CALL_UUID"}
```

`call_ended` means **dismiss this installation's incoming UI**, not necessarily
that the whole group call ended. Do not hang up an accepted local media session
just because its other installations were notified. Fetch the authenticated
call record for authoritative status and participant membership.

- **Android**: FCM high-priority **data-only**, invitation TTL bounded by the
  ring deadline. The client native messaging/CallKit integration must display
  visible ringing promptly (Android can deprioritize high-priority pushes that
  never cause visible notifications). Android 13 notification permission,
  Android 14 full-screen-intent permission/policy, audio foreground-service
  restrictions, battery optimizations and OEM task killers still apply.
  **Force-stop** blocks FCM until the user explicitly launches the app again.
- **Web**: FCM Web Push requires HTTPS, permission, a working service worker,
  Firebase config and the project's web VAPID key. Incoming and end messages are
  **data-only**: no notification or FCM link-options block may bypass the worker's
  expiry/logout checks. Web incoming data adds an optional `link` field pointing
  only to `CALLS_PUBLIC_APP_URL` with an encoded `call_id` query parameter; all
  standard incoming-call fields are preserved. After validating the session,
  expiry and same-origin link, the worker displays title/body with the call UUID
  as tag and opens the link with `call_expires_at` derived from `expires_at`.
  Keep `CALLS_PUBLIC_APP_URL` aligned with the actual worker/app origin. Browser/OS
  background delivery is best effort; a fully exited/disabled browser, denied
  permission, private browsing or unsupported web-push environment may not ring.
- **iOS**: incoming calls go directly to APNs over HTTP/2 with ES256 `.p8` token
  authentication, `apns-push-type: voip`, priority 10, topic `<bundle>.voip`,
  `apns-expiration: 0` and the exact data at the root beside `aps`. Enable Push
  Notifications and appropriate background/VoIP modes, use valid entitlements
  and signing, register via PushKit, and report **every incoming VoIP push
  promptly to CallKit** before asynchronous backend checks. Test on real devices.
  Never send cancellation-only pushes through PushKit: Apple requires a new
  CallKit call for each VoIP push and can terminate/throttle violators.
  Cancellation instead uses ordinary FCM/APNs background data; it may be
  throttled, so native expiration and authenticated reconciliation are mandatory.
  Delivery/relaunch after user force-quit is not guaranteed. This is not an
  emergency-call delivery service.

No push contains credentials or authorization. Validate the current account,
fetch the call, reject expired/stale invitations, deduplicate by call UUID, and
only acquire credentials after the user accepts. Already-enqueued provider
notifications cannot be recalled after logout; clients must suppress them when
logged out or signed in as a different participant. FCM/APNs are at-least-once /
best-effort systems, not guaranteed signalling transports. Regular authenticated
incoming polling remains the fallback while the app is running.

## Validation

Existing pytest runner, from `microservices/data-service`, with a test-only
`JWT_SECRET`:

```text
python -m pytest tests/test_calls.py tests/test_call_providers.py tests/test_social.py -q --basetemp=.pytest-calls
```

Tests use isolated JSON stores, fake users/credentials/clock, mocked FCM, HTTP/2
APNs and LiveKit requests. They cover authorization, membership, token claims,
direct/group transitions, idempotency, busy conflicts, races, leases/timeouts,
token ownership, stale notifications and retryable cleanup. The APNs signing
test generates a disposable test key inside pytest's project-local test folder;
it never reads a deployment key. Real Cloud delivery, native background behavior,
signing, permissions and microphone/camera routing still require a configured
deployment and physical-device/browser acceptance tests.

References: [LiveKit token grants and Cloud revocation](https://docs.livekit.io/frontends/reference/tokens-grants/),
[LiveKit participant removal](https://docs.livekit.io/intro/basics/rooms-participants-tracks/participants/),
[Firebase priority](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-priority),
[Apple PushKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit).
