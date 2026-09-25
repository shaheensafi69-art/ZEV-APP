package com.example.easy_compressor

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*

class EasyCompressorPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var progressChannel: EventChannel
    private lateinit var context: Context
    private var progressSink: EventChannel.EventSink? = null
    private var compressor: VideoCompressor? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "easy_compressor")
        channel.setMethodCallHandler(this)

        progressChannel = EventChannel(binding.binaryMessenger, "easy_compressor/progress")
        progressChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressSink = events
            }

            override fun onCancel(arguments: Any?) {
                progressSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "compressVideo" -> {
                val inputPath = call.argument<String>("inputPath")!!
                val quality = call.argument<Int>("quality") ?: 70
                val maxHeight = call.argument<Int>("maxHeight")
                val maxWidth = call.argument<Int>("maxWidth")
                val frameRate = call.argument<Int>("frameRate")
                val includeAudio = call.argument<Boolean>("includeAudio") ?: true
                val audioBitrate = call.argument<Int>("audioBitrate") ?: 128000
                val videoCodec = call.argument<String>("videoCodec") ?: "h264"
                val outputPath = call.argument<String>("outputPath")

                scope.launch {
                    try {
                        compressor = VideoCompressor(context)
                        val compResult = compressor!!.compress(
                            inputPath = inputPath,
                            quality = quality,
                            maxHeight = maxHeight,
                            maxWidth = maxWidth,
                            frameRate = frameRate,
                            includeAudio = includeAudio,
                            audioBitrate = audioBitrate,
                            videoCodec = videoCodec,
                            outputPath = outputPath,
                            onProgress = { progress ->
                                scope.launch(Dispatchers.Main) {
                                    progressSink?.success(progress)
                                }
                            }
                        )
                        result.success(compResult)
                    } catch (e: Exception) {
                        result.error("COMPRESSION_FAILED", e.message, e.toString())
                    }
                }
            }

            "getMediaInfo" -> {
                val inputPath = call.argument<String>("inputPath")!!
                scope.launch {
                    try {
                        val info = MediaInfoExtractor.extract(context, inputPath)
                        result.success(info)
                    } catch (e: Exception) {
                        result.error("MEDIA_INFO_FAILED", e.message, e.toString())
                    }
                }
            }

            "getThumbnail" -> {
                val inputPath = call.argument<String>("inputPath")!!
                val positionMs = call.argument<Int>("positionMs") ?: 0
                val quality = call.argument<Int>("quality") ?: 80
                val maxHeight = call.argument<Int>("maxHeight")

                scope.launch {
                    try {
                        val bytes = MediaInfoExtractor.getThumbnail(
                            context, inputPath, positionMs.toLong(), quality, maxHeight
                        )
                        result.success(bytes)
                    } catch (e: Exception) {
                        result.error("THUMBNAIL_FAILED", e.message, e.toString())
                    }
                }
            }

            "cancelCompression" -> {
                compressor?.cancel()
                result.success(null)
            }

            "clearCache" -> {
                scope.launch {
                    try {
                        VideoCompressor.clearCache(context)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CLEAR_CACHE_FAILED", e.message, e.toString())
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }
}
