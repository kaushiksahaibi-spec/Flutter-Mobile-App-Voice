plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.risersx.flutter_voice_recg_app"
    // Android 16 (API 36) is the current target requested for the project.
    // Use the Flutter SDK's pinned compileSdk if it's already 36+, else
    // bump to 36 explicitly.
    compileSdk = maxOf(36, flutter.compileSdkVersion)
    // Highest NDK required by any plugin in our dependency graph
    // (speech_to_text needs 28.2.13676358). NDKs are backward compatible.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.risersx.flutter_voice_recg_app"
        // 24 is the floor required by the project. Note that the
        // dedicated `SpeechRecognizer.createOnDeviceSpeechRecognizer`
        // factory ships in API 31 (Android 12); on API 24-30 the
        // platform falls back to the standard SpeechRecognizer with
        // EXTRA_PREFER_OFFLINE.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
