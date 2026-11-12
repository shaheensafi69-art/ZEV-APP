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

# Flutter Plugin interfaces & Message Codecs
-keep class io.flutter.plugin.common.** { *; }
-keep interface io.flutter.plugin.common.** { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }
-keepclassmembers class * implements io.flutter.plugin.common.StandardMessageCodec { *; }
-keepclassmembers class * implements io.flutter.plugin.common.BinaryMessenger { *; }
-keepclassmembers class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keepclassmembers class * implements io.flutter.plugin.common.BasicMessageChannel$MessageHandler { *; }

# Pigeon Communication Channels & SharedPreferences (Crucial for all storage, auth, and engine channels)
-keep class dev.flutter.pigeon.** { *; }
-keep interface dev.flutter.pigeon.** { *; }
-keepclassmembers class dev.flutter.pigeon.** { *; }
-keepclassmembers interface dev.flutter.pigeon.** { *; }
-keep class **.Pigeon** { *; }

-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep interface io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembers class io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembers interface io.flutter.plugins.sharedpreferences.** { *; }

# AndroidX DataStore & Preferences (Underpinning shared_preferences_android 2.4+)
-keep class androidx.datastore.** { *; }
-keep interface androidx.datastore.** { *; }
-keepclassmembers class androidx.datastore.** { *; }
-dontwarn androidx.datastore.**

-keep class androidx.preference.** { *; }
-keep interface androidx.preference.** { *; }
-keepclassmembers class androidx.preference.** { *; }
-dontwarn androidx.preference.**

-keep class kotlinx.coroutines.** { *; }
-keep interface kotlinx.coroutines.** { *; }
-keepclassmembers class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Firebase Core & Messaging
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class io.flutter.plugins.googlemobileads.** { *; }
-keep class com.google.android.ads.nativetemplates.** { *; }
-dontwarn com.google.android.ads.nativetemplates.**
-keep class com.google.android.gms.internal.ads.** { *; }

# Google Sign In & Play Services Auth (Native One-Tap & Account Picker)
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.auth.** { *; }
-keep class io.flutter.plugins.googlesignin.** { *; }
-keep interface io.flutter.plugins.googlesignin.** { *; }
-keepclassmembers class io.flutter.plugins.googlesignin.** { *; }
-keepclassmembers interface io.flutter.plugins.googlesignin.** { *; }

# Local Auth & Biometrics / Credential Manager
-keep class io.flutter.plugins.localauth.** { *; }
-keep class androidx.biometric.** { *; }
-keep class androidx.credentials.** { *; }

# Video Player & ExoPlayer / Media3
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**
-keep class io.flutter.plugins.videoplayer.** { *; }

# Audio Players & Audio Recording
-keep class xyz.luan.audioplayers.** { *; }
-keep class com.llfbandit.record.** { *; }

# FFmpeg & Video Compression
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.example.easy_compressor.** { *; }
-keep class com.tinify.easy_compressor.** { *; }

# Speech To Text & Text To Speech
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class com.tundralabs.fluttertts.** { *; }

# File Picker & Image Picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }

# Gal (Gallery Saver) & Plus Plugins
-keep class studio.midoridesign.gal.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.tekartik.sqflite.** { *; }

# App Links / Deep Links
-keep class com.llfbandit.app_links.** { *; }

# OkHttp, Ktor, Coroutines & Network
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# Google Play Core & Deferred Components (Referenced by Flutter Engine)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.gms.**
-dontwarn org.checkerframework.**

# Agora RTC Engine (Voice/Video Calls & Live Broadcasting)
-keepattributes *Annotation*
-keep class io.agora.** { *; }
-dontwarn io.agora.**
-dontwarn com.google.devtools.build.android.desugar.runtime.ThrowableExtension

# Keep all method channels & event channels intact
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}
