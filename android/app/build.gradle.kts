plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "id.ac.bsi.awake"
    // flutter_plugin_android_lifecycle 2.0.30+ (pulled in by file_picker)
    // demands compileSdk >= 36; pin explicitly instead of flutter's preset.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "id.ac.bsi.awake"
        minSdk = 24 // Required for TensorFlow Lite
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // Release signing: read from android/keystore.properties (git-ignored).
    // Copy android/keystore.properties.example -> android/keystore.properties
    // and fill in the keystore path + passwords. CI supplies these via secrets.
    val keystorePropertiesFile = rootProject.file("keystore.properties")
    val keystoreProperties = java.util.Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Release builds use the documented release keystore when present,
            // otherwise fall back to debug signing for local dev (never for store).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
