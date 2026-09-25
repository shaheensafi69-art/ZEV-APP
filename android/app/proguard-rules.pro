# Flutter ProGuard / R8 Rules

# Flutter core
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Flutter Generated Plugin Registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant {
    *;
}

# Flutter Plugin interfaces
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    *;
}
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware {
    *;
}
-keepclassmembers class * implements io.flutter.plugin.common.StandardMessageCodec { *; }

# Pigeon Communication Channels (Crucial for shared_preferences, firebase_core, local_auth)
-keep class dev.flutter.pigeon.** { *; }
-keep class **.Pigeon** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Firebase Core & Messaging
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class io.flutter.plugins.googlemobileads.** { *; }

# Local Auth & Biometrics
-keep class io.flutter.plugins.localauth.** { *; }
-keep class androidx.biometric.** { *; }

# Keep all method channels & event channels intact
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}
