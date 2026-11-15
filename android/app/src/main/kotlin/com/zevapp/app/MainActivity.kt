package com.zevapp.app

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterFragmentActivity() {
    private val pipChannelName = "com.zevapp.app/pip"
    private var methodChannel: MethodChannel? = null
    private var isPipSupported = false
    private var isPipActive = false
    private var currentAspectX = 9
    private var currentAspectY = 16

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        isPipSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            GeneratedPluginRegistrant.registerWith(flutterEngine)
        } catch (_: Exception) {}

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPipSupported" -> {
                        result.success(isPipSupported)
                    }
                    "enableAutoPip" -> {
                        val aspectX = (call.argument<Int>("aspectX") ?: 9).coerceAtLeast(1)
                        val aspectY = (call.argument<Int>("aspectY") ?: 16).coerceAtLeast(1)
                        currentAspectX = aspectX
                        currentAspectY = aspectY
                        isPipActive = true
                        updatePipParams(aspectX, aspectY, autoEnter = true)
                        result.success(true)
                    }
                    "disableAutoPip" -> {
                        isPipActive = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            try {
                                setPictureInPictureParams(
                                    PictureInPictureParams.Builder()
                                        .setAutoEnterEnabled(false)
                                        .build()
                                )
                            } catch (_: Exception) {}
                        }
                        result.success(true)
                    }
                    "enterPip" -> {
                        val aspectX = (call.argument<Int>("aspectX") ?: currentAspectX).coerceAtLeast(1)
                        val aspectY = (call.argument<Int>("aspectY") ?: currentAspectY).coerceAtLeast(1)
                        val success = enterPipMode(aspectX, aspectY)
                        result.success(success)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun updatePipParams(aspectX: Int, aspectY: Int, autoEnter: Boolean) {
        if (!isPipSupported) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                // Rational aspect ratio must be between 1:2.39 and 2.39:1 according to Android specs
                val clampedX = aspectX.coerceIn(1, 100)
                val clampedY = aspectY.coerceIn(1, 100)
                val rational = Rational(clampedX, clampedY)
                val builder = PictureInPictureParams.Builder().setAspectRatio(rational)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && autoEnter) {
                    builder.setAutoEnterEnabled(true)
                }
                setPictureInPictureParams(builder.build())
            } catch (_: Exception) {}
        }
    }

    private fun enterPipMode(aspectX: Int, aspectY: Int): Boolean {
        if (!isPipSupported) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return try {
                val clampedX = aspectX.coerceIn(1, 100)
                val clampedY = aspectY.coerceIn(1, 100)
                val rational = Rational(clampedX, clampedY)
                val builder = PictureInPictureParams.Builder().setAspectRatio(rational)
                enterPictureInPictureMode(builder.build())
            } catch (_: Exception) {
                false
            }
        }
        return false
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isPipActive && isPipSupported && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                if (!isInPictureInPictureMode) {
                    enterPipMode(currentAspectX, currentAspectY)
                }
            } catch (_: Exception) {}
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
