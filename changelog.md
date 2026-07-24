# Changelog

All notable work done on GlobeTrotter Travel Assistant so far, grouped by area.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Phase 1 — Monolith] — In Progress

### Backend (FastAPI)
- Scaffolded a single-server FastAPI monolith with JSON file storage (`backend/app/main.py`).
- Implemented JWT-based authentication (register/login) using `passlib` (bcrypt) + `python-jose`.
- Implemented the 6 core endpoints:
  - `POST /register`
  - `POST /login`
  - `GET /destinations` (with optional `?q=` search)
  - `GET /recommendations` (naive tag-matching against user preferences)
  - `POST /itineraries`
  - `GET /itineraries`
  - `GET /health`
- Added CORS middleware (open for dev, to be tightened for production).
- Restricted seed data to **Cameroon-only destinations** — 10 locations across all 10 regions
  (Kribi, Limbe, Foumban, Yaoundé, Douala, Bamenda, Dschang, Maroua, Waza National Park,
  Mount Cameroon/Buea), replacing the earlier placeholder data that included non-Cameroon cities.
- Renamed destination field `country` → `region` to reflect the Cameroon-only scope.

### Security / Configuration
- Moved `JWT_SECRET` out of hardcoded source into a `.env` file, loaded via `python-dotenv`.
- App now refuses to start if `JWT_SECRET` is missing, instead of silently falling back to an
  insecure default.
- Added `.env.example` (safe to commit) and `.env` (real secret, git-ignored).
- Added `.gitignore` for `backend/` covering `.env`, `venv/`, `__pycache__/`, and the JSON
  "database" files under `app/data/`.
- Flagged and rotated a JWT secret that was pasted into chat, to avoid reusing an exposed value.

### Frontend (Flutter — mobile, desktop, web from one codebase)
- Scaffolded a full Flutter app (`frontend/`) styled around a Cameroon-geography theme
  (rainforest canopy, savanna sand, Waza-sun ochre, highland clay, coastal teal), using
  Fraunces + Inter + IBM Plex Mono via `google_fonts`.
- Built an adaptive shell: bottom navigation on phones, `NavigationRail` on tablet/desktop/web,
  switching at the 600px breakpoint.
- Built the signature **region ribbon** — a scrollable filter chip strip for all 10 Cameroon
  regions, used on the Discover screen.
- Implemented screens:
  - **Login / Register** — form validation, error handling, loading states.
  - **Discover** — search bar + region ribbon + responsive destination grid (1–4 columns
    depending on screen width).
  - **For You** — recommendations pulled from `/recommendations`.
  - **My Trips** — itinerary list + a "Plan a trip" dialog that posts to `/itineraries`,
    including a destination picker and date pickers.
- Built a typed `ApiService` with platform-aware base URL resolution (web/desktop → `localhost`,
  Android emulator → `10.0.2.2`, production → `--dart-define=API_BASE_URL=...`).
- Built a minimal `SessionState` (ChangeNotifier) to hold the signed-in user without pulling in
  a full state-management package.

### Debugging (Flutter setup on Windows)
- Resolved PowerShell execution-policy blocking venv activation (`Set-ExecutionPolicy -Scope
  Process -ExecutionPolicy RemoteSigned`).
- Clarified that `0.0.0.0` in `--host` is a bind address, not a browsable URL — use `localhost`
  or `127.0.0.1` instead.
- Fixed `flutter analyze` issues found during setup:
  - Wrapped a single-statement `if` in braces (`api_service.dart`).
  - Reverted `DropdownButtonFormField`'s `value` → `initialValue` to match this Flutter version's
    API (3.44.1 deprecated `value` in favor of `initialValue`).
  - Removed unnecessary double-underscore lambda params (`(_, __)` → `(_, _)`) in
    `itineraries_screen.dart` and `region_ribbon.dart`.
  - Replaced manual null-check spread with null-aware spread (`...?actions`) in
    `adaptive_shell.dart`.
  - Replaced the default `flutter create` test (which referenced a non-existent `MyApp` class)
    with a real smoke test against `GlobeTrotterApp`.
  - Diagnosed a `google_fonts` "not a dependency" error down to the on-disk `pubspec.yaml` not
    matching what had been reviewed — resolved via `flutter pub add google_fonts`.

### Documentation
- Wrote and iteratively reorganized `README.md` covering:
  - Running the backend locally (Windows PowerShell + macOS/Linux instructions).
  - Wiring up and running the Flutter app on web, desktop, and mobile.
  - Deploying the backend to a Contabo VPS (systemd service + Nginx reverse proxy + optional
    Certbot HTTPS).
  - A networking reference table for `baseUrl` across dev/prod situations.
- Documented a **Future Plans** section for GitHub Actions CI/CD (auto-deploy PC → GitHub → VPS
  on every push), including the workflow shape and prerequisites (SSH key as a GitHub Secret,
  repo cloned once on the VPS).

## Not Yet Done
- Actual deployment to the Contabo VPS (commands provided, not yet executed/confirmed live).
- GitHub Actions CI/CD workflow (planned, not built).
- Phase 2 (microservices), Phase 3 (cloud deployment/K8s), Phase 4 (resilience) — not started.
- Facebook group project description (written, posted by user separately from the codebase).