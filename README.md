# ICA16 Class A — Flutter Cloud Quiz (Undergraduate)

This is the **undergraduate** Class A project. It loads exactly ten easy General Knowledge multiple-choice questions from OpenTDB, tracks one answer per question, reviews all ten, and stores each completed round in **real Cloud Firestore** under the currently signed-in Firebase user. A successful write is **not** shown as verified until the exact document has been fetched with `GetOptions(source: Source.server)` and checked.

> **Important:** This source ZIP is not a connected Firebase deployment, a tested APK, or completed experimental evidence. The last steps require YOUR real Firebase project, phone/emulator, and observed test results. Do not submit simulated test results as real evidence.

## Included files

- `lib/main.dart` — Firebase initialization and auth state routing
- `lib/screens/sign_in_screen.dart` — Email/Password sign in with errors
- `lib/screens/quiz_screen.dart` — quiz/review, state machine, recovery, T03/T09–T12 debug controls, server-only restart retrieval
- `lib/services/trivia_api.dart` — 10-second OpenTDB request, schema validation, decoding, shuffle-once, 5-second request throttle
- `lib/services/cloud_attempts.dart` — Firestore create-once transaction, six-field verification, development rule probes
- `lib/firebase_options.dart` — deliberate placeholder; **replace using `flutterfire configure`**
- `firestore.rules`, `firebase.json` — owner-only create/read, six fields only, no updates/deletes
- `test/trivia_api_test.dart` — pure validation test fixture
- `scripts/setup_windows.ps1`, `scripts/deploy_rules_windows.ps1`, `scripts/build_release_windows.ps1`
- `evidence/ICA16_A_YourName.docx` — fill in using **actual** observations and screenshots
- `evidence/TEST_CHECKLIST.md` — T01–T12 walkthrough and evidence checklist

## 1. Prerequisites

Install Flutter SDK, Android Studio + Android SDK, Java/Android tools, Node.js/npm (for Firebase CLI), and have a working Android emulator or phone. Check `flutter doctor`. Use your actual Firebase account. No paid plan is required for the core assignment.

On Windows, open PowerShell in this **unzipped project folder**:

```powershell
flutter --version
flutter doctor
npm install -g firebase-tools
firebase login
# If flutterfire is not already installed:
dart pub global activate flutterfire_cli
```

If PowerShell does not recognize `flutterfire`, add `%LOCALAPPDATA%\Pub\Cache\bin` to PATH or use:

```powershell
dart pub global run flutterfire_cli:flutterfire configure
```

## 2. Firebase Console (real cloud, not emulator)

1. Go to https://console.firebase.google.com and select/create a separate class project.
2. **Build → Authentication → Sign-in method → Email/Password → Enable**.
3. **Authentication → Users → Add user**: add test users A and B with private passwords. Do **not** put passwords in Git, screenshots, or this ZIP.
4. **Build → Firestore Database → Create database → Standard edition / Native mode → production mode**; select the appropriate region. Production-deny rules are expected at this stage.
5. Run the FlutterFire CLI from the project root. Select the **same** project and **Android** platform, and replace the placeholder `lib/firebase_options.dart`:

```powershell
flutter create . --platforms=android --project-name=ica16_quiz
flutter pub get
flutterfire configure --platforms=android --out=lib/firebase_options.dart
```

   If the CLI asks to overwrite `lib/firebase_options.dart`, choose **Yes**. Android app/package ID defaults to `com.example.ica16_quiz`; choose the Android application for this project, not a different class project. Re-run `flutterfire configure` after adding/changing Firebase plugins. Generated Firebase files should not contain passwords; never commit service-account/private-key files.

6. Deploy the **real** rules in this ZIP, replacing `YOUR_FIREBASE_PROJECT_ID` with the project ID from Firebase console:

```powershell
firebase deploy --only firestore:rules --project YOUR_FIREBASE_PROJECT_ID
```

Verify the rules in Firebase Console → Firestore Database → Rules. **Do not enable public access to fix permission errors.**

Shortcut on Windows: `powershell -ExecutionPolicy Bypass -File scripts/setup_windows.ps1` runs local project bootstrap and starts interactive FlutterFire configuration. You must still set up the Console and deploy rules.

## 3. Run, test, build

```powershell
flutter run
# Run debug to reveal labeled T03, T09–T12 controls.
flutter test
flutter build apk --release
```

The release artifact is `build/app/outputs/flutter-apk/app-release.apk`. Install it and test on an Android device/emulator, then **rename it** to `ICA16_A_YourName.apk` for the assignment. The Android Gradle wrapper and Flutter-generated metadata are created by `flutter create .` during setup, so do not skip that command. The released APK hides fault-injection controls; debug runs must use the **deployed cloud backend** for T09–T11.

**Without a real Firebase configuration this app will show an intentional setup error.** The ZIP cannot create an instructor Firebase project or a successful cloud screenshot on your behalf.

## 4. Live source and immutable schema

Request URL, verbatim:

`https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple`

Firestore path: `users/{FirebaseAuth.currentUser.uid}/attempts/{roundId}`.

Exactly these six fields, no extras:

| Field | Required |
|---|---|
| `schemaVersion` | integer `1` |
| `variant` | string `A` |
| `categoryId` | integer `9` |
| `questionCount` | integer `10` |
| `correctCount` | integer `0..10` |
| `submittedAt` | server timestamp |

No question text, password, name, tokens, or percentage is stored. Each round ID comes from `attempts.doc().id` **once at round start**. A transaction reads first; existing matching data is reused and mismatches are flagged as collisions. No update or delete is allowed under deployed rules. The Firestore rules prove **ownership and schema**, not that the score is genuine; authoritative score verification would need a trusted server.

## 5. State transitions / recovery

```text
Firebase auth stream: signedOut ──login──> signedIn
                                  └─authError: show in sign-in form
signedIn ──new round──> loading ──valid 10──> playing
                          └─bad HTTP/JSON/API/schema──> requestError ──manual retry──> loading
playing ──answer once ×10──> readyToSubmit
readyToSubmit ──one transaction──> submitting ──ack──> verifying ──server match──> cloudVerified
                                     │                   ├─denied──> permissionDenied
                                     │                   └─read error──> verificationUnavailable
                                     ├─lost ack / offline / exhausted──> saveUnknown
                                     └─denied / collision──> permissionDenied
saveUnknown ──manual Source.server get──> cloudVerified (document matches)
                                  └──> readyToSubmit (server confirms absent; SAME ID)
                                  └──> saveUnknown (server still unavailable)
verificationUnavailable ──manual Source.server get──> cloudVerified (matches)
                                          └──> verificationUnavailable (unavailable)
cloudVerified ──Replay──> loading (NEW ID, all answers reset)
```

The app never reports `Cloud verified` based on a transaction alone. The injected T09 flag runs a **real transaction** and throws *after* it finishes to suppress the UI acknowledgement. Recovery reads the **same document ID** from the server, and no extra document is made. The app does not automatically retry a submission. If server retrieval confirms an unknown attempt does not exist, the user can press Submit again with the **same** ID. Sign-out and replay are blocked during unresolved submissions. Asynchronous results check initiating UID and round ID before changing the UI.

**T07 after restart:** screenshot/copy the full Round ID and path. Restart app, sign in with test user A, paste the old ID into `Retrieve after app restart` and tap `Get exact attempt from server`. This does not depend on local preferences or cached snapshots.

## 6. Debug fault and Firestore rules tests

The expanded panel `Development tests • T03, T09–T12` appears only in `flutter run` debug mode, not in release.

- **T03**: choose `badJson`, `apiCode`, or `nineResults`, start a fresh round or retry, capture blocked play, wait >=5 seconds before next request.
- **T09**: finish a NEW real quiz, choose `lostAcknowledgement`, submit (a real transaction commits), see `saveUnknown`, tap `Recover — server read`, capture one document and verified response.
- **T10**: sign out when resolved; sign in as B, enter user A's UID and existing saved round ID, run read and write probes. BOTH must show `permission-denied` (not merely errors such as offline).
- **T11**: as A, run injected `score=11`, `extra field`, and after a verified attempt, `update saved attempt`. All three must show `permission-denied`, then confirm original remains unchanged on server.
- **T12**: before Submit on a new completed round choose `unavailable` or `resourceExhausted`. Capture distinct messages; recover via server read and submit with the same ID when safe. Repeat for second injection with a **new round**.

After a development fault test, return its fault selection to `none` before attempting a normal submission. For T08, disable network before submission, note that the app does not claim verification, reconnect, then recover. Depending on Firestore's offline behavior, you may need to restore connectivity to get a final transaction outcome. Never assume a timeout or cache means failure.

**Caution:** Direct rule probes are intentionally blocked operations; only run while connected to your own *deployed* class project. Never deploy permissive test rules. For screenshots redact sensitive identifiers as required.

## 7. Submission requirements (undergraduate only)

1. **Android release APK** — install-tested `ICA16_A_YourName.apk`.
2. **Public repository URL** — current source files, `firestore.rules`, this README, dependency files, and final commit hash, without passwords, tokens, secrets, or service accounts.
3. **Evidence document** — fill `evidence/ICA16_A_YourName.docx`: four build checkpoints, state diagram referencing actual variables, T01–T12 observed results with dates/screenshots and redacted ID suffix, six responses **120–180 words each** with app-specific evidence, critique of an AI design/instructor candidate, AI-use disclosure, and actual app/cloud screenshots.

Do not claim tests pass without running them. The instructor may ask you to reproduce a failed-first correction. Assignment deadline: **Nov 16, 2026 at 11:59 PM** (check course portal timezone).

## Useful official setup reference

https://firebase.google.com/docs/flutter/setup
