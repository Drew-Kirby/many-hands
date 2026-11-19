# Many Hands — Flutter mobile app

A native Flutter version of the Many Hands volunteer app (Android + web for iPhone), connected to my own Firebase project.

**Features:** email sign-in (show/hide password, password reset), Home with your tasks / unclaimed tasks / issues at risk,
Issues with search + Active/Resolved/All + sort, issue detail with task groups and health, tasks (take, give back,
status, reassign as issue owner, comments), Members with search and workload, profiles, **voice-to-text** on every
text box (mic button), and **Ask AI** search powered by Gemini through Firebase AI Logic.

It uses the same Firestore collections and security rules as the website, so the website and the app share data.

## One-time setup (Windows)

From the `many-hands` folder:

```
flutter create --org edu.svsu.drewkirby --project-name many_hands --platforms android,web mobile
cd mobile
flutter pub add firebase_core firebase_auth cloud_firestore firebase_ai speech_to_text
dart pub global activate flutterfire_cli
npm install -g firebase-tools
firebase login
flutterfire configure --project=YOUR_PROJECT_ID --platforms=android,web
```

Then copy this folder's `lib/` over the generated one, and in `android/app/src/main/AndroidManifest.xml` add, above `<application`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<queries>
    <intent>
        <action android:name="android.speech.RecognitionService"/>
    </intent>
</queries>
```

In the Firebase console, turn on **AI Logic → Get started → Gemini Developer API** (free tier) for Ask AI.

## Run and build

```
flutter analyze
flutter run -d chrome            # quick test in the browser
flutter run                      # on a connected Android phone or emulator
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
flutter build web --release --base-href /many-hands-app/
```

If the Android build says Firebase needs a higher `minSdk`, set `minSdk = 23` in `android/app/build.gradle.kts`.

## Stress-test data

See `../seed/`: `npm install`, put your `service-account.json` there (never commit it), then `node seed.js`.
It creates 20 members, 60 issues and 255 tasks; every member, including real accounts, gets 10 tasks across 10 issues.
