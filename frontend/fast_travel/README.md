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

## Docker (Flutter web)

The [Dockerfile](Dockerfile) builds the Flutter web release in a Linux builder
and serves only the generated web files in an Nginx runtime container. A local
Flutter installation is not required. This container does not run Android,
iOS, or desktop apps.

Start Docker Desktop with the Linux container engine enabled. From the repository
root, run in PowerShell:

```powershell
Set-Location .\frontend\fast_travel
docker compose up --build -d
```

Open http://localhost:2012. By default, the browser calls the existing API at
`https://fasttravel-web.duckdns.org/api`; the frontend container does not start
or proxy the backend. To use a backend already running on your computer:

```powershell
$env:API_BASE_URL = "http://localhost:8000"
docker compose up --build -d
```

`API_BASE_URL` is compiled into the web app, so changes require rebuilding the
image, not just restarting the container. Use an absolute URL with no trailing
slash. The URL must be reachable from the **browser**, not from Docker: do not
use an internal service name such as `api-gateway`. For a browser on another
device, replace `localhost` with your computer's reachable hostname or IP.
The backend must allow the frontend origin through CORS.

Optional Compose settings are `FRONTEND_PORT` (default `2012`) and
`FLUTTER_VERSION` (default `3.44.1`). Nginx supports client-side route fallback,
returns 404 for missing static assets, and exposes `/healthz` for the container's
health check. This check verifies the web server only, not backend availability.

```powershell
docker compose ps
docker compose logs frontend
docker compose down
```

For production, put the container behind an HTTPS reverse proxy and build with
an HTTPS API URL (the event connection then uses WSS). HTTPS is also required
outside localhost for browser microphone/camera and notification features.
Do not pass API secrets as build arguments: Flutter web configuration is public.
The [.dockerignore](.dockerignore) allowlist excludes local build output,
platform projects, development caches, and private credential files.

### Deployment checklist

- Commit the Dockerfile, Compose file, Nginx configuration, dependency manifests,
  Flutter source, and bundled assets. Do not commit environment files, private
  credentials, generated builds, or local Compose overrides.
- Run `flutter pub get` after dependency changes and commit the updated
  `pubspec.lock` for reproducible application builds.
- Before release, run `flutter analyze` and `flutter test`, then
  `docker compose up --build -d`. Confirm `docker compose ps` reports the
  frontend as healthy and check http://localhost:2012/healthz.
- Verify the app loads, a browser refresh on a nested route works, and
  authentication/API requests and live updates reach the configured backend.
- For production, route the HTTPS reverse proxy to port `2012` on the Docker
  host. Keep the backend's `/api` and WebSocket routing intact. If the reverse
  proxy is on the same host, restrict the published port to loopback or protect
  it with a firewall.
- This Compose setup is manual: adding it does not switch the existing Jenkins
  deployment to containers.

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
- Community supports one shared voice or video call at a time. Start one using
  **Voice call** or **Video call**, or tap **Join call** on the live banner.
  Calls are opt-in: community members are never automatically rung or connected.
  Anyone signed in can join while the call remains active; it ends when the last
  participant leaves. Discovery and joining need internet, not cached call state.
  Private and group call invitations continue to work as before.
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
