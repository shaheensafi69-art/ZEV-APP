# Flutter ProGuard / R8 Rules

# Flutter core
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

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

# Google Sign In & Play Services Auth
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class io.flutter.plugins.googlesignin.** { *; }

# Local Auth & Biometrics / Credential Manager
-keep class io.flutter.plugins.localauth.** { *; }
-keep class androidx.biometric.** { *; }
-keep class androidx.credentials.** { *; }

# Video Player & ExoPlayer / Media3
-keep class androidx.media3.** { *; }
-keep class io.flutter.plugins.videoplayer.** { *; }

# Audio Players & Audio Recording
-keep class xyz.luan.audioplayers.** { *; }
-keep class com.llfbandit.record.** { *; }

# FFmpeg & Video Compression
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.tinify.easy_compressor.** { *; }

# Speech To Text & Text To Speech
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class com.tundralabs.fluttertts.** { *; }

# File Picker & Image Picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }

# App Links / Deep Links
-keep class com.llfbandit.app_links.** { *; }

# OkHttp, Ktor, Coroutines & Network
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# Keep all method channels & event channels intact
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}
