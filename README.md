# TaskProof

TaskProof is a Flutter mobile app for Android and iOS. The repository keeps only
the two mobile platform projects; desktop and web scaffolding are intentionally
excluded.

Object verification runs on-device. ML Kit first localizes objects in each
camera frame, then TaskProof compares those regions with the object's saved
multi-angle scan; camera images are not uploaded for recognition.

## Project layout

- `lib/` contains screens, camera verification, recognition, and persistence.
- `android/` contains the Android runner and Firebase configuration.
- `ios/` contains the iPhone/iPad runner.
- `assets/` contains the images used by the app.
- `test/` contains automated tests for shared application logic.

Generated directories such as `build/` and `.dart_tool/` are not source code and
can be recreated with `flutter pub get` and `flutter run`.

## Setup

1. Install Flutter and run `flutter pub get`.
2. Configure an iOS app in the existing Firebase project before running on an
   iPhone. This must generate `ios/Runner/GoogleService-Info.plist` and add the
   iOS configuration to `lib/firebase_options.dart`.
3. Run the app with `flutter run` on an Android or iOS device.

The ML Kit plugins require iOS 15.5 or newer. For the best recognition quality,
create new object scans after installing this version so the saved views use
the localized, higher-resolution scan pipeline.
