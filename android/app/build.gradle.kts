plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.bangun"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.bangun"
        minSdk = 24 // Required for TensorFlow Lite
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Signed with the debug keys so `flutter run --release` works
            // without extra setup.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // The TFLite runtime ships via the tflite_flutter plugin (LiteRT
    // artifacts). No manual org.tensorflow deps: AGP enforces unique
    // manifest namespaces and org.tensorflow.lite would collide.
    packagingOptions {
        doNotStrip("*/libtensorflowlite_jni.so")
        doNotStrip("*/libtensorflowlite_gpu_jni.so")
        pickFirst("**/libtensorflowlite_jni.so")
        pickFirst("**/libtensorflowlite_gpu_jni.so")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
