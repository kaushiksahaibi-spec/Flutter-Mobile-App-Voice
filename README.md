# Flutter Voice Recognition App (on-device native STT)

Cross-platform Flutter app (Android & iOS) that listens for **6 seconds**
when the user taps a centered microphone button, then transcribes the
captured English speech and shows it below the mic — using the
**platform-native, on-device** speech recognition engines:

| Platform | API used                                                    | Notes                                                                                                |
| -------- | ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Android  | `SpeechRecognizer.createOnDeviceSpeechRecognizer()`         | API 31+ (Android 12+). On API 24-30 the project falls back to the standard `SpeechRecognizer`.       |
| iOS      | `SFSpeechRecognizer` with `requiresOnDeviceRecognition`     | iOS 13+. The flag is honoured by Apple when the locale's offline model is installed on the device.   |

Both APIs are reached through the well-maintained
[`speech_to_text`](https://pub.dev/packages/speech_to_text) Flutter
plugin (v7.3.0), which exposes the on-device path as
`SpeechListenOptions(onDevice: true)`.

## Demo flow

1. Launch app → `_initSpeech` runs once, asks for microphone (and on
   iOS, speech-recognition) permission, and verifies that the platform
   recognizer is available.
2. The mic button activates in the centre of the screen.
3. Tap mic → the app records for **6 seconds** with a live countdown
   and a pulsing ring; partial results stream in italic text below the
   mic so the user can see recognition in real time.
4. After 6 seconds (or when the recognizer fires its final result), the
   transcript is shown in the card below.

## Tech stack

- **Flutter:** `^3.11.5` (verified on 3.41.9).
- **STT:** [`speech_to_text`](https://pub.dev/packages/speech_to_text) `^7.3.0`.
- **Permissions:** [`permission_handler`](https://pub.dev/packages/permission_handler) `^12.0.1`.
- **No model download, no native binaries, no FFI.** The OS provides
  the recognizer.

## Project layout

```
lib/
  main.dart                                  ← UI + state machine
  services/
    stt_service.dart                         ← speech_to_text wrapper (on-device, 6 s window)
  widgets/
    mic_button.dart                          ← Animated mic FAB
android/app/src/main/AndroidManifest.xml     ← Permissions + RecognitionService query
android/app/build.gradle.kts                 ← compileSdk 36, targetSdk 36, minSdk 24
ios/Runner/Info.plist                        ← NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription
```

## Prerequisites

- Flutter `>=3.11.5` stable (project verified on 3.41.9).
- For Android: device or emulator running **Android 7.0 (API 24)** or
  higher. For the *guaranteed on-device* path, **Android 12 (API 31)+**
  is required.
- For iOS: macOS with Xcode 15+, device/simulator running **iOS 13+**.

## Setup

```bash
flutter pub get
flutter run --release
```

That's it. There is no model file to download.

### Android specifics

Permissions declared in `android/app/src/main/AndroidManifest.xml`:

- `RECORD_AUDIO`
- `INTERNET` (for fallback recognizer / metadata only — on-device
  recognition itself works offline)
- `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_CONNECT` (so the recognizer
  can use a connected BT headset's mic)

A `<queries>` element exposes `android.speech.RecognitionService` so
that Android 11+ resolves the installed recognizer (required because
`targetSdk = 36` triggers package-visibility filtering).

`build.gradle.kts` pins:

```kotlin
android {
    compileSdk = maxOf(36, flutter.compileSdkVersion)
    defaultConfig {
        minSdk = 24
        targetSdk = 36
        ...
    }
}
```

### iOS specifics

`Info.plist` ships both required keys:

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

The Xcode project's `IPHONEOS_DEPLOYMENT_TARGET = 13.0` is preserved
across all three configurations. After `flutter pub get`, on macOS run
once:

```bash
cd ios && pod install --repo-update && cd ..
```

If you customize the `Podfile`, ensure the platform line reads
`platform :ios, '13.0'` (or higher).

## Where to look in the code

- `lib/services/stt_service.dart` — initializes `SpeechToText`, asks for
  the right permissions, and exposes a single `listenOnce()` method
  that returns a stream of `SttUpdate`s. It enforces a 6-second window
  via `listenFor: Duration(seconds: 6)` *and* `pauseFor: Duration(seconds: 6)`,
  forces on-device recognition with `SpeechListenOptions(onDevice: true)`,
  and gracefully retries with `onDevice: false` if the OS rejects the
  on-device factory (e.g. on Android 11 with no offline model).
- `lib/main.dart` — minimal state machine
  (`initializing → ready → listening → finalizing`) and the UI layout:
  centered mic button + live partial transcript above the transcript
  card.
- `lib/widgets/mic_button.dart` — Material 3 circular mic with a pulsing
  ring while recording and a spinner during finalization.

## Troubleshooting

### Android: "No speech was detected" / `error_no_match`

- Make sure the **English** offline language pack is installed:
  *Settings → System → Languages → Add a language → English (United
  States)* and, on Pixel/AOSP devices,
  *Settings → System → Languages → Voice → Offline speech recognition →
  Install English (United States)*.
- On Android emulators, enable the virtual mic from
  *Extended controls → Microphone → "Virtual microphone uses host
  audio input"* before testing.

### iOS: speech recognition not working in Simulator

Open *Settings → Accessibility → Spoken Content → Voices* in the
simulator and download any voice. After that the speech framework
becomes available. On a physical device, ensure your locale's offline
dictation pack is downloaded under
*Settings → General → Keyboard → Dictation*.

### `error_recognizer_busy` on Android

Another app is currently using the recognizer (e.g. Google Assistant).
Close it and try again. The plugin already cancels on error, so the
mic button returns to the idle state automatically.

### On-device falls back to the cloud recognizer

If on Android API 24-30 the dedicated on-device factory isn't
available, `stt_service.dart` retries with `onDevice: false`. The
status footer in the app updates to
"Platform default recognizer (on-device unavailable on this OS
version)" so this is visible to the user.

## License

App code is provided as-is. The `speech_to_text` plugin is BSD-3-Clause.
