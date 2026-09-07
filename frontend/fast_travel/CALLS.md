# LiveKit Cloud calls and incoming notifications

LiveKit carries audio/video **after** the authenticated call API authorizes an
accepted call. Notifications are wake-up hints, never authorization or automatic
acceptance. Do not put LiveKit API secrets, Firebase service-account credentials,
APNs signing keys, access tokens, or room credentials in notification payloads or
Flutter build arguments. LiveKit server credentials belong only on the backend.

## Flutter integration

Dependencies: `firebase_messaging: ^15.2.10` (Firebase Core 3.x compatible),
`flutter_callkit_incoming: ^3.1.5`, and the existing `shared_preferences`.
CallKit 3.1.5 is intentional: its Android native accept/decline/end callbacks
preserve system actions when there is no Dart listener. Its Dart events are
typed classes, unlike the 2.x API. LiveKit's Flutter SDK supplies WebRTC.

1. After Firebase initialization, before `runApp`, await
   `initializeCallPushBackground()`.
2. Create one `CallPushService` and initialize it early. The callbacks receive a
   UUID call ID. `onIncoming` presents/reconciles an invitation, `onAccept` fetches
   and accepts the authorized call then starts its shared media runtime, and `onDecline`
   declines **or ends** the call according to its server state. All callbacks
   must check backend participation/status and handle already-ended calls.
   Before submitting an **in-app** acceptance request, await
   `push.markAccepting(callId)`; native CallKit accept events mark this
   automatically. This must precede `connectCall(..., accept: true)`, not just
   room connection, so the backend's stop-ringing push cannot tear down this
   installation's own newly accepted call. If acceptance fails, end the native
   call through `endCall`.
3. Only after restoring a valid authenticated session, call `restoreSession()`.
   This replays native actions and `activeCalls` acceptance **without permission
   prompts, a Navigator, or a rendered frame**. Already-authorized device tokens
   refresh separately from answering. Call `registerDevice()` to explicitly request
   notification permissions and register FCM and iOS VoIP device tokens. Call it
   again after a user enables notifications/settings or retries a failed grant.
   The Friends app-bar **Enable call notifications** button invokes this flow
   explicitly. On web, `registerDevice` starts `requestPermission` before any
   unrelated asynchronous work, preserving the button click's user activation.
   Previously blocked permissions may still require browser/system settings;
   the button cannot override a permanent denial.
4. Call `unregisterDevice()` **before** removing authentication on sign-out.
   Call `endCall(id)` for local/remote terminal states; it suppresses feedback
   from programmatically closing CallKit. Call `dispose()` when the owner ends.
   `SessionState.beforeSignOut` should await this method for explicit logout.
   Also invoke it after unauthorized-session invalidation: it first persists
   local delivery as disabled, clears pending actions and native UI, and disables
   PushKit before attempting any authenticated request. Network failures are
   reported without re-enabling local alerts; FCM token revocation is best effort.
5. Do not request camera/microphone or create local media tracks while ringing.
   Ask only after explicit acceptance; Android Bluetooth headset permission is
   also a runtime permission on Android 12+. CallKit audio-session callbacks are
   forwarded to WebRTC, but do not create tracks.
   Before `Room.connect` or local track creation, await
   `push.prepareAudio(callId)` for **both incoming and outgoing calls**. On iOS
   it selects LiveKit 2.11's `externalCallSystem` for a matching native call,
   otherwise `automatic` for an ordinary outgoing call. Other platforms no-op.
   This also restores audio availability for an outgoing call after a previous
   CallKit call ended. Do not globally select `externalCallSystem` when outgoing
   calls are not reported to CallKit.
6. After the authorized call's LiveKit room connects successfully, await
   `push.markConnected(callId)`. This marks an existing native incoming call as
   connected without ending its ongoing system UI. Repeated calls and outgoing
   calls without a native entry are no-ops. It suppresses any redundant native
   answer event emitted by CallKit's connected transition. Use `endCall` only
   for terminal states; its persistent suppression prevents decline recursion.
   `markMediaReady` releases the native answer background task only after media
   setup completes. `CallMediaSession` owns the Room, microphone, camera lifecycle
   and idempotent teardown. `CallScreen` borrows it instead of creating another
   publisher. Native mute updates apply immediately (including before connection);
   app mute updates CallKit without echo loops.

Native actions are journaled on the device without credentials. They are copied
to a Dart persistent queue and replayed after authentication. Decline/end takes
precedence over a queued accept. Unaccepted `activeCalls` are not auto-accepted.
Windows, Linux, and macOS skip mobile CallKit/FCM registration safely; they can
still use the running app's realtime signaling and LiveKit UI.

## Backend push contract

Send data-only payloads (all FCM data values are strings):

```json
{
  "type": "incoming_call",
  "call_id": "624ac083-8b80-4c48-bc39-70bd5d868774",
  "caller_name": "Caller display name",
  "kind": "voice",
  "expires_at": "2026-09-07T12:01:00Z"
}
```

`kind` is `voice` or `video`. `expires_at` is required and must be in the future.
Terminal payloads are `{"type":"call_ended","call_id":"<same UUID>"}`.
Despite its name, `call_ended` is a **reconciliation/stop-ringing hint**, not proof
the conversation ended: accepting sends it to all installations of that user.
The background handler preserves native/local accepted calls and queues an
authenticated `ApiService.getCall` fetch for foreground/session restoration.
Only authoritative `status == ended` closes an accepted native call. Unaccepted
sibling installations dismiss their ring immediately. The coordinator continues
reconciling its own screen/room from server state and heartbeat results.
Use `platform` values `android`, `ios`, `web`; token `kind` values `fcm`, `voip`.
Token refreshes are registered and previous known tokens removed. Prune tokens
when FCM/APNs reports permanent unregistration. Device endpoints must authenticate
and associate tokens with the current user; never allow cross-user deletion.

### Android

- Configure this app's Firebase Android application and `google-services.json`.
  The app ID is currently `com.example.fast_travel`. Use JDK 17 and the project's
  current Flutter Android compile/target SDK.
- Send FCM **HIGH priority data**, without a `notification` block. Set TTL no
  longer than the remaining ringing interval and avoid collapsing unrelated
  calls. Normal priority can be delayed in Doze and OS-generated notification
  payloads bypass the background Dart handler needed for CallKit.
- `CallPushApplication` preserves native events even when no activity exists.
  If introducing another Application subclass, merge this callback registration
  rather than replacing it. MainActivity is `singleInstance` for CallKit.
- Android 13 notification consent is requested explicitly. Android 14+
  full-screen eligibility is checked and the settings request is offered.
  Full-screen alerts require user/OS approval and appropriate Play policy
  eligibility; this is not guaranteed merely by declaring the permission.
  Users can still receive a heads-up notification when full-screen is denied.
- Microphone, camera, audio routing, Bluetooth, wake lock and notification/service
  permissions are declared. Permissions alone do not start background recording;
  the accepted-call media owner controls track/service lifecycle.
- A **force-stopped** app cannot receive FCM until reopened. OEM battery savers,
  denied permissions, network loss, DND and notification-channel settings can
  prevent or delay ringing. Do not promise guaranteed delivery.

### iOS / PushKit / signing

- Build and test on a physical iPhone using Xcode on macOS; Windows cannot compile
  or sign this target. Configure a real unique bundle ID (currently
  `com.example.fastTravel`), Apple Developer team and matching Firebase iOS app.
- Runner's entitlements include `aps-environment=development`. Enable **Push
  Notifications** and **Background Modes: Voice over IP, Remote notifications,
  Audio** in Signing & Capabilities. All Runner configurations reference
  `Runner/Runner.entitlements`. Development profiles use the APNs sandbox;
  distribution provisioning/export must sign with the production APNs entitlement.
  Verify the final signed entitlements, do not simply change the APNs server URL.
- Configure APNs `.p8` key, key ID, team ID, environment, and bundle topic on the
  backend; upload an APNs key to Firebase for ordinary iOS FCM. Never bundle `.p8`.
  PushKit tokens are not interchangeable with FCM tokens or ordinary APNs tokens.
- Deliver incoming calls directly to the PushKit token with
  `apns-push-type: voip`, `apns-topic: <bundle-id>.voip`,
  `apns-priority: 10`, and **`apns-expiration: 0`**. The JSON includes the call
  fields above at the top level. Send only currently ringing authorized calls.
- **Never send `call_ended`, keepalives, duplicate retries, or other non-call
  updates through VoIP pushes.** Apple requires incoming VoIP pushes to report a
  CallKit call promptly; repeated invalid/stale pushes can terminate the app or
  disable delivery. Cancellation uses ordinary FCM/APNs background delivery plus
  realtime signaling while awake, and local expiration is the final fallback.
  Every delivered VoIP push is still reported: invalid, expired, suppressed,
  logged-out, and duplicate deliveries use a separate CallKit provider with a
  synthetic UUID and generic “Call unavailable” label, then end immediately in
  the report completion. This never starts media or overwrites a legitimate call.
  A brief system UI flash cannot be ruled out; preventing invalid pushes at the
  sender is essential.
- iOS registers **both** a VoIP token and an FCM token. Alert-permission denial
  does not skip the FCM registration needed for silent cancellations; APNs-token
  readiness is retried briefly and again on resume/token refresh. Send
  `call_ended` through the iOS FCM token with APNs `content-available: 1`,
  `apns-push-type: background`, `apns-priority: 5`, and the regular bundle topic.
  Silent delivery is best effort; `expires_at` (normally the backend's 45-second
  ringing deadline) and foreground signaling still provide reconciliation.
- AppDelegate retains **one** explicit `FlutterEngine` with
  `allowHeadlessExecution: true`, registers all generated plugins, and runs the
  real `main` entrypoint on every process launch, including scene-less PushKit
  wakes. `main` initializes Firebase, restores/validates the saved session with
  bounded network timeouts, and starts the call coordinator before `runApp`.
  A locked-screen Answer therefore accepts the backend call and connects LiveKit
  without opening the app. No credentials or failed restoration disables local
  delivery and ends pending system calls; it never creates an unauthenticated Room.
- `SceneDelegate` attaches that same engine to a `FlutterViewController`; removing
  the view leaves the Dart engine, coordinator, heartbeat and Room alive. The
  `globetrotter/app_runtime` channel mounts the widget tree when a scene exists.
  Do not restore Main/scene storyboard keys, add an implicit second engine, or
  move session/call startup back into a post-frame callback. Scene foreground
  renders the existing media session with no reconnect or duplicate publisher.
- Accept/decline/end/timeouts are persisted natively before fulfilling CallKit
  actions. No network/authentication delay is placed inside a PushKit completion.
  Acceptance is replayed only after Flutter restores the authenticated session.
  Native terminal actions bypass pending connect operations. Answer startup uses
  a bounded iOS background task; expiration ends the call and closes audio rather
  than allowing a late connection. Provider reset also terminates tracked calls.
  Cold mute is recovered from CallKit state before media publication.
- Locked/headless microphone use requires permission granted previously while
  unlocked. If permission is absent, native Answer fails and ends safely; unlock
  and grant microphone access in an accepted foreground call first. Camera
  capture is never started headlessly and stays off until an accepted video call
  has a foreground view. No incoming invitation requests microphone/camera access.
- On native answer, AppDelegate configures `playAndRecord` with voice/video-chat
  mode under WebRTC's audio-session configuration lock. It does not activate the
  session or start capture itself: CallKit activation/deactivation is forwarded
  to WebRTC. The LiveKit 2.11 audio device module (ADM) is gated natively through
  `LiveKitPlugin.setEngineAvailability`: unavailable while ringing/deactivated,
  available in `didActivateAudioSession`. This API preserves the gate before
  Flutter/LiveKit registration during cold-start PushKit delivery. Native state
  is queried by `prepareAudio`, so a missed Dart activation event cannot leave
  an accepted cold-start call permanently muted. `externalCallSystem` prevents
  LiveKit from activating/deactivating a session owned by CallKit; outgoing
  calls without CallKit explicitly return to `automatic`. Audio configuration failure fails the
  native answer and closes the call rather than claiming a working connection.
- User force-quit, APNs delivery constraints and system policies still apply.
  Validate background, terminated, locked, and signed release behavior physically;
  simulator and foreground-only tests do not establish reliable VoIP delivery.
  This Windows implementation was not compiled or signed with Xcode. Physical
  iOS validation must cover a release cold launch with no scene, audible two-way
  audio while locked, native mute before/during connect, End during connection,
  foreground/background handoff without a second participant, denied microphone,
  expired auth, logout, duplicate/expired pushes, and provider reset.

### Web

- Serve over **HTTPS** (localhost is a development exception). Camera/microphone
  require a secure context and consent. Browser autoplay policies may require a
  gesture for remote audio.
- Generate a Firebase Cloud Messaging Web Push certificate/public VAPID key and
  build with `--dart-define=FIREBASE_WEB_VAPID_KEY=<public-key>`. The public VAPID
  key is not a server secret.
- Serve `firebase-messaging-sw.js` from the Flutter web root with JavaScript MIME
  type, not an SPA fallback. `index.html` registers it at Firebase's messaging
  scope separately from Flutter's asset-cache worker. Keep its public Firebase
  configuration synchronized with `lib/firebase_options.dart`. Allow
  `www.gstatic.com` scripts and Firebase messaging connections in CSP.
- Background data creates a tagged notification; a click focuses/navigates an
  existing app tab or opens a tab with `call_id` and `call_expires_at`.
  This opens an invitation, not an automatic answer. Refreshing an existing tab
  may interrupt its current UI; the authenticated backend must reconcile state.
  Send **data-only** web messages: adding `webpush.notification` causes Firebase
  to display an alert before the worker can validate expiry/logout. The worker
  tolerates legacy notification+data payloads without showing a duplicate and
  supports their click/cancellation metadata, but cannot prevent the initial
  Firebase-generated alert from briefly appearing.
  A web-only optional `data.link` may supply the configured app destination.
  The worker accepts it only when it is HTTPS and same-origin with the worker,
  overwrites `call_id` with the validated UUID, and adds `call_expires_at` from
  the validated payload. Invalid/cross-origin links fall back to the local app.
- The service worker persists a separate delivery-enabled flag in IndexedDB.
  `index.html` synchronizes only the shared-preferences `call_push_enabled` key
  (including writes in the same tab), so logout closes existing call
  notifications and blocks new ones even if server unregistration fails.
  Keep this synchronization script when changing the web bootstrap.
- Request notification permission from a user gesture if the browser blocks
  startup prompts using Friends → **Enable call notifications**, which calls
  `registerDevice()` again. Unsupported browsers or
  denied permissions fall back to in-app incoming UI/realtime signaling.
- **A fully closed browser cannot reliably ring like a phone.** Service-worker
  delivery depends on the browser/OS running background push services. Browser
  notifications are best effort, have no mobile system CallKit and no guarantee
  of sound, delivery, or timely cancellation.

## Release verification checklist

On two separate accounts/devices, verify voice/video invitations in foreground,
background, locked screen, and normal process termination; cold accept before
auth restoration; cold decline/end; duplicate and expired pushes; caller cancel
before/after delivery; timeout; another device accepting; denied notifications;
full-screen denial; token rotation; logout/account switch; disconnect/reconnect;
Bluetooth audio; microphone/camera denial; no capture until acceptance; and web
notification click navigation. Inspect the server's authoritative call state,
not just the displayed notification. Never log push tokens or room JWTs.

Official references:
[Flutter FCM receiving](https://firebase.google.com/docs/cloud-messaging/flutter/receive),
[FCM message priority](https://firebase.google.com/docs/cloud-messaging/android/message-priority),
[CallKit plugin](https://pub.dev/packages/flutter_callkit_incoming/versions/3.1.5),
[Apple PushKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit).
