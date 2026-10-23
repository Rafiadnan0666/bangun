# Release-only keep rules.
#
# shared_preferences_android 2.5+ uses Pigeon JNI. Its generated registrar
# exposes suspend functions whose JVM descriptors include
# kotlin.coroutines.Continuation, and its Java bridge loads kotlin.Result by
# name. R8 renames or strips those stdlib classes while keeping the registrar,
# so release builds fail with NoSuchMethodError or ClassNotFoundException.
# Keep the Kotlin runtime and the generated registrars intact.
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.github.dart_lang.jni.** { *; }

# The AndroidX @Keep annotation, used by generated Pigeon/JNI code. The
# default Android rules only understand the old android.support annotation.
-keep class androidx.annotation.Keep
-keep @androidx.annotation.Keep class * { *; }
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
