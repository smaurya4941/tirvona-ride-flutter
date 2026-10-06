# Tirvona Rides — Mobile App

One Flutter app for both **customers** and **drivers** of Tirvona Rides. The backend decides the role after login; the app opens the matching navigation shell (from Phase 1).

- Backend: `../tirvona/Tirvona_ride` (NestJS, port 5100)
- Admin panel: `../tirvona/Tirvona_ride_admin`
- Bundle ID: `com.tirvona.ride`

## Run

```powershell
flutter pub get
flutter run                                                          # Android emulator → http://10.0.2.2:5100
flutter run --dart-define=API_BASE_URL=http://<PC-LAN-IP>:5100       # physical phone on the same Wi-Fi
flutter run --dart-define-from-file=env/local.json                   # copy env/local.example.json first
```

Build-time settings (`--dart-define`):

| Key | Default | Purpose |
|---|---|---|
| `APP_ENV` | `development` | `development` or `production` |
| `API_BASE_URL` | emulator/localhost on port 5100 | API origin, without `/api/v1` |

Debug builds allow plain HTTP for local development; release builds are HTTPS-only.

Publishing to Google Play (signing, build command, Console forms, fingerprints):
see [docs/play-store/README.md](docs/play-store/README.md).

## Structure

```
lib/
├── main.dart                 # entry point → bootstrap()
├── bootstrap.dart            # error handlers, ProviderScope, config injection
├── app/
│   ├── app.dart              # MaterialApp.router + theme
│   └── router/               # go_router config and route paths
├── core/                     # app-wide, feature-agnostic code
│   ├── config/               # AppConfig (dart-define) + provider
│   ├── network/              # Dio client, endpoints, ApiException, interceptors
│   └── theme/                # Tirvona colours and ThemeData
└── features/<feature>/       # one folder per feature
    ├── data/                 # repositories (API calls, DTO mapping)
    ├── domain/               # models and business types
    └── presentation/         # screens, widgets, Riverpod providers
```

Planned features: `auth` (Phase 1), `customer/*` and `driver/*` (Phases 1–5), `system` (diagnostics — the Phase 0 landing screen).

State management: **Riverpod**. Navigation: **go_router**. HTTP: **Dio**.

## Checks

```powershell
flutter analyze
flutter test
```
