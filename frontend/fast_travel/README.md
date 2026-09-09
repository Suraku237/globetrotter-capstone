# fast_travel

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Weak connections and live updates

- Read responses for destinations, recommendations, trips, the feed, profile,
  assistant history, friendships, and chats are cached on the device. Previously
  loaded content opens immediately; stale content refreshes in the background.
- The JSON cache is isolated by API server and account, capped at 80 entries and
  4 MiB (including serialized metadata), and expires after seven days. Most reads
  stay fresh for 60 seconds; stickers for 12 hours. Identical simultaneous reads
  share a request. The profile is retained preferentially for offline startup.
- Signing out removes the account's JSON cache. A valid, unexpired saved login
  can restore the app offline when a profile has already been saved. A network
  failure does not delete the saved login. An authentication rejection does.
- The connection banner distinguishes reconnecting updates, offline content, and
  local cache-storage failures. Retry requests a fresh synchronization.
- One authenticated WebSocket carries invalidations for active screens and
  calls. Reconnection uses exponential backoff and triggers a full resync so
  missed friendship approvals/messages are fetched after an interruption.
  Credentials are sent in the first socket frame, never in its URL.
- Community chat is available from the toolbar and navigation drawer; workers
  can open it from their home screen. It is public to all signed-in users.
  Private chats and groups remain separate. All three chat histories load in pages
  instead of downloading the entire conversation each time.
- Data Saver is enabled by default: videos require an explicit tap instead of
  autoplay. Change this in Profile. Images use a reusable bounded cache on
  supported native platforms; browser image storage is controlled by the browser.
  The shared native image cache retains up to 200 objects for seven days; decoded
  images are limited to 80 entries / 64 MiB in memory. Stalled video initialization
  offers Retry after 30 seconds, and leaving an initializing video cancels it.

Offline browsing is not offline delivery: sending messages, mutations, AI
responses, and calls require connectivity. Failed text sends retain the draft
for explicit retry; requests are not automatically replayed, avoiding duplicate
posts/messages or repeated friendship actions. Whole videos, voice recordings,
and offline map regions are not automatically downloaded.

### Deployment

Deploy the corresponding backend and enable WebSocket upgrades through the
reverse proxy; see [backend real-time notes](../../microservices/REALTIME.md).
Use HTTPS/WSS in production. For a local backend, build/run Flutter with
`--dart-define=API_BASE_URL=http://localhost:8000` (no trailing slash).
Use a device-reachable hostname instead of `localhost` on physical phones.

Foreground updates do not replace background call notifications. Those still
require working FCM/APNs/CallKit, platform permissions, and LiveKit configuration
as documented in [CALLS.md](../../microservices/CALLS.md). No transport can
guarantee instant delivery while a device is offline or its OS blocks delivery.
