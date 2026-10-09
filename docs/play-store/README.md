# Publishing Tirvona Rides on Google Play

Package: `com.tirvona.ride` · one app for riders and drivers · version in
`pubspec.yaml` (`1.0.0+1` = name 1.0.0, build number / versionCode 1).

## What the code already does

| Requirement | Where |
|---|---|
| Release signed with **your upload key**; the Play bundle build refuses to run without it | `android/app/build.gradle.kts`, `android/key.properties` |
| R8 shrinking + resource shrinking, Razorpay keep rules, native debug symbols in the bundle | `build.gradle.kts`, `proguard-rules.pro` |
| Target API 36, min API 24, HTTPS-only in release (cleartext is debug-only) | Flutter 3.47 defaults, `src/debug/AndroidManifest.xml` |
| No Google Drive / device-transfer backup of tokens | `allowBackup=false`, `res/xml/data_extraction_rules.xml` |
| **In-app account deletion** + web deletion page | Settings → Delete account; `/api/v1/legal/delete-account` |
| **Privacy policy** and Terms (public URLs + links in the app) | `/api/v1/legal/privacy`, `/api/v1/legal/terms` |
| Developer "System status" page hidden in production builds | `APP_ENV=production` in `env/prod.json` |
| Location only while in use (driver: foreground service with notification), no background-location permission | `AndroidManifest.xml` |
| Maps / Firebase / Razorpay keys kept out of git | `android/secrets.properties`, `env/*.json` (git-ignored) |

## What only you can do

### 1. Production backend (do this first; the app is useless without it)

1. Host the NestJS API (`tirvona/Tirvona_ride`) on an **always-on HTTPS** server
   with WebSocket support. A free tier that sleeps (e.g. Render free) will make
   ride requests and driver live-location fail; use a paid always-on instance
   or a VPS.
2. MongoDB Atlas production cluster (paid tier recommended, backups on).
3. Create `.env.production` from `.env.production.example` and fill **all** of:
   JWT secrets (32+ chars each, different), `CORS_ORIGINS` (admin panel origin
   only), `PUBLIC_BASE_URL` (the https API origin), **`SUPPORT_EMAIL`**,
   `LEGAL_ENTITY_NAME`, Razorpay **live** key/secret/webhook secret,
   `WHATSAPP_*` (Meta production number + approved OTP template),
   `OTP_HASH_SECRET`, `FIREBASE_SERVICE_ACCOUNT_BASE64`, Google Maps / Places /
   Routes server keys. The API refuses to start in production if a required value is missing.
4. Razorpay dashboard: switch to live mode, set the webhook to
   `https://<api>/api/v1/payments/webhook/razorpay`.
5. Meta WhatsApp: approved `AUTHENTICATION` template for login/signup codes, and
   the SOS templates (`tirvona_sos_alert`, optional `tirvona_sos_update`).
6. `npm run seed:admin`, deploy the admin panel (`Tirvona_ride_admin`) with
   `VITE_API_URL` set to the API origin (and `VITE_GOOGLE_MAPS_API_KEY` for the live map).
7. **Driver documents and profile photos are stored in MongoDB GridFS** (same Atlas
   cluster), so no disk or volume is needed. Make sure Atlas Network Access allows
   your host and the cluster is a paid tier before real traffic (see
   `Tirvona_ride/docs/storage/README.md`). Run `npm run storage:migrate` once
   if old documents exist.
8. Open `https://<api>/api/v1/legal/privacy` in a browser: it must load and show
   your support email. **Have the policy and terms text reviewed** (they are drafts).
9. Put the same API origin in `env/prod.json` → `API_BASE_URL`.

### 2. Upload keystore (once, keep it forever)

```powershell
New-Item -ItemType Directory D:\Tirvona\_secrets -Force
keytool -genkeypair -v -storetype JKS -keystore D:\Tirvona\_secrets\tirvona-upload-keystore.jks `
  -alias tirvona-upload -keyalg RSA -keysize 2048 -validity 10000
```

Copy `android/key.properties.example` to `android/key.properties`, fill the
passwords and adjust `storeFile`. **Back the `.jks` and both passwords up outside
this PC** (password manager + cloud). Losing the upload key means a support
request to Google to reset it; leaking it lets someone push updates as you.
Use Play App Signing (the default when you create the app): Google keeps the
real signing key and you only hold the upload key.

### 3. Build the bundle

```powershell
cd D:\Tirvona\tirvona-ride-app
flutter build appbundle --release --dart-define-from-file=env/prod.json --obfuscate --split-debug-info=build/symbols
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Keep `build/symbols/`
for every release you ship (needed to read Dart stack traces). Each new upload
needs a higher build number: bump the `+N` in `pubspec.yaml`.

### 4. Fingerprints (after the first upload)

Play Console → your app → **Test and release → Setup → App signing** shows the
**SHA-1 / SHA-256 of the app signing key**. Add them:

* **Google Cloud → Credentials → "TIRVONA ANDROID MAPS KEY"** → Android apps →
  add `com.tirvona.ride` with the *app signing* SHA-1 (keep the upload and debug
  SHA-1 too). Without this the **map is blank in the store version**.
* **Firebase console → Project settings → Android app** → add the same SHA-1 /
  SHA-256 fingerprints, then download the new `google-services.json` into
  `android/app/` if Firebase asks.
* Make sure the browser/server Google keys used by the API are restricted to the
  server IP, and the Android key to Maps SDK for Android only.

### 5. Play Console account

* One-time US$25 developer fee and identity verification (an organisation
  account needs a D-U-N-S number; a *personal* account created after Nov 2023
  must also run a **closed test with at least 12 testers for 14 days** before
  production access is granted. Check the current rule in the Console).
* Add a payments profile if you sell anything (the app itself is free; ride
  payments go through Razorpay and are outside Play Billing).

### 6. Create the app and fill in the listing

| Item | What to enter |
|---|---|
| App name | Tirvona Rides (max 30 chars) |
| Short description | up to 80 chars |
| Full description | up to 4000 chars: pilgrimage rides in Braj, circuit packages, safety (SOS, share ride), WhatsApp sign-in |
| App icon | 512×512 PNG (use the logo) |
| Feature graphic | 1024×500 PNG/JPG |
| Phone screenshots | at least 2, 16:9 or 9:16; rider home, choose a ride, tracking, driver home, circuit |
| Category / tags | Maps & Navigation (or Travel & Local) |
| Contact | support email (same as `SUPPORT_EMAIL`), website, phone |
| **Privacy policy URL** | `https://<api>/api/v1/legal/privacy` |

### 7. App content forms (Policy → App content)

* **App access**: the app needs a login. Create two permanent test accounts in
  production (a rider and an **approved** driver) and give the reviewers the
  phone numbers and passwords. They cannot receive WhatsApp codes, so use
  password login. Do not delete these accounts.
* **Ads**: No.
* **Content rating**: answer the questionnaire (no violence, no user-generated
  public content; location is shared with other users during a ride).
* **Target audience**: 18+.
* **News / Government / Health / Financial features**: none of them (ride
  payments are not a "financial feature" under this form).
* **Data safety** (must match the privacy policy; see below).
* **Account deletion**: tick "users can request deletion" and enter
  `https://<api>/api/v1/legal/delete-account`.
* **Foreground service permissions** (`FOREGROUND_SERVICE_LOCATION`): declare
  "Location": drivers go online and share location with riders during rides,
  shown by an ongoing notification. Record a 30-second video: driver goes
  online → notification appears → rider sees the car moving.
* **Location permissions**: the app asks for foreground (while in use)
  location only; there is no background-location form to fill.

#### Data safety answers

| Data type | Collected | Shared | Purpose | Optional |
|---|---|---|---|---|
| Name, phone number, email | Yes | With the other party on a ride (first name) | Account, app functionality | email optional |
| Precise location | Yes | With the other party on a ride; Google (Maps/Routes) | App functionality | required to book/drive |
| Date of birth, gender, photo | Yes | No | Account / driver verification | optional (DOB required for drivers) |
| Payment info | Not collected by the app (Razorpay handles it) — declare payment history (amount/status) | Razorpay | App functionality | – |
| Photos / files (driver documents) | Yes, drivers | No | Verification | drivers only |
| Contacts (emergency contacts you type; the app does not read your address book) | Yes | Meta WhatsApp (SOS message) | Safety | optional |
| Device or other IDs (FCM token) | Yes | Google (Firebase) | Notifications | – |
| Audio | Not collected (voice search is processed on device by the system speech service) | – | – | – |

Also tick: data **encrypted in transit**; users **can request deletion**;
no data is sold. If you later add analytics or crash reporting (Crashlytics
etc.), update this form and the privacy policy.

### 8. Release

1. **Internal testing** track: upload the `.aab`, add your testers by email,
   install from the Play link and test on real phones: sign-up with WhatsApp
   code, booking, driver flow, payment, SOS, map, push notification, account
   deletion.
2. Check the **Pre-launch report** and fix crashes.
3. **Closed testing** (required for new personal accounts) → **Production**
   with a **staged rollout** (start at 10–20 %).
4. Review can take a few days. If rejected, the email says which policy; the
   usual causes are a missing/unreachable privacy policy, no test login, or a
   mismatch between the Data safety form and the app.

## Later releases

* Bump `version:` in `pubspec.yaml` (`1.0.1+2`), rebuild with the same command,
  upload to the Production track.
* Keep `android/key.properties`, the `.jks` and `build/symbols/<version>/` safe.
* Retire the old `render.yaml` if you moved hosts; keep `env/prod.json` pointing
  at the live API.
