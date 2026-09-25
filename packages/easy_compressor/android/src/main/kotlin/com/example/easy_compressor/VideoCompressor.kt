package com.example.easy_compressor

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import kotlinx.coroutines.*
import java.io.File
import kotlin.math.min
import kotlin.math.roundToInt

@UnstableApi
class VideoCompressor(private val context: Context) {

    private var transformer: Transformer? = null
    @Volatile
    private var isCancelled = false

    companion object {
        private const val CACHE_DIR_NAME = "easy_compressor_cache"

        fun clearCache(context: Context) {
            val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
            if (cacheDir.exists()) {
                cacheDir.deleteRecursively()
            }
        }

        private fun getResolutionCap(height: Int): Int {
            return when {
                height <= 480 -> 2_500_000
                height <= 720 -> 5_000_000
                height <= 1080 -> 8_000_000
                height <= 1440 -> 14_000_000
                else -> 20_000_000
            }
        }

        private fun calculateTargetBitrate(originalBitrate: Int, quality: Int, outputHeight: Int): Int {
            val factor = 0.05 + 0.95 * (quality.coerceIn(0, 100) / 100.0)
            val qualityBitrate = (originalBitrate * factor).roundToInt()
            val capBitrate = getResolutionCap(outputHeight)
            return min(qualityBitrate, capBitrate)
        }
    }

    suspend fun compress(
        inputPath: String,
        quality: Int,
        maxHeight: Int?,
        maxWidth: Int?,
        frameRate: Int?,
        includeAudio: Boolean,
        audioBitrate: Int,
        videoCodec: String,
        outputPath: String?,
        onProgress: (Double) -> Unit
    ): Map<String, Any> = withContext(Dispatchers.IO) {
        isCancelled = false
        val startTime = System.currentTimeMillis()
        val inputFile = File(inputPath)

        if (!inputFile.exists()) {
            throw IllegalArgumentException("Input file does not exist: $inputPath")
        }

        val originalSize = inputFile.length()

        // Extract original media info
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(inputPath)

        val originalWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 1920
        val originalHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 1080
        val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        val originalBitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 10_000_000
        val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        retriever.release()

        // Calculate output dimensions
        var targetWidth = originalWidth
        var targetHeight = originalHeight

        // Handle rotation: if rotated 90/270, swap dimensions for calculation
        if (rotation == 90 || rotation == 270) {
            targetWidth = originalHeight
            targetHeight = originalWidth
        }

        if (maxHeight != null && targetHeight > maxHeight) {
            val scale = maxHeight.toDouble() / targetHeight
            targetHeight = maxHeight
            targetWidth = (targetWidth * scale).roundToInt()
        }
        if (maxWidth != null && targetWidth > maxWidth) {
            val scale = maxWidth.toDouble() / targetWidth
            targetWidth = maxWidth
            targetHeight = (targetHeight * scale).roundToInt()
        }

        // Ensure even dimensions
        targetWidth = (targetWidth / 2) * 2
        targetHeight = (targetHeight / 2) * 2
        if (targetWidth < 2) targetWidth = 2
        if (targetHeight < 2) targetHeight = 2

        val targetBitrate = calculateTargetBitrate(originalBitrate, quality, targetHeight)

        // Determine output file
        val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
        if (!cacheDir.exists()) cacheDir.mkdirs()
        val outFile = if (outputPath != null) {
            File(outputPath)
        } else {
            File(cacheDir, "compressed_${System.currentTimeMillis()}.mp4")
        }

        // If output file already exists, delete it
        if (outFile.exists()) outFile.delete()

        val result = CompletableDeferred<Map<String, Any>>()

        val mimeType = when (videoCodec) {
            "h265" -> MimeTypes.VIDEO_H265
            else -> MimeTypes.VIDEO_H264
        }

        val transformerBuilder = Transformer.Builder(context)
            .setVideoMimeType(mimeType)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)

        if (!includeAudio) {
            transformerBuilder.setRemoveAudio(true)
        }

        val listener = object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                val compressedSize = outFile.length()
                val compressionTime = System.currentTimeMillis() - startTime
                result.complete(
                    mapOf(
                        "outputPath" to outFile.absolutePath,
                        "originalSize" to originalSize.toInt(),
                        "compressedSize" to compressedSize.toInt(),
                        "duration" to durationMs.toInt(),
                        "compressionTime" to compressionTime.toInt(),
                        "width" to targetWidth,
                        "height" to targetHeight,
                        "status" to "success"
                    )
                )
            }

            override fun onError(
                composition: Composition,
                exportResult: ExportResult,
                exportException: ExportException
            ) {
                if (isCancelled) {
                    result.complete(
                        mapOf(
                            "outputPath" to outFile.absolutePath,
                            "originalSize" to originalSize.toInt(),
                            "compressedSize" to 0,
                            "duration" to durationMs.toInt(),
                            "compressionTime" to (System.currentTimeMillis() - startTime).toInt(),
                            "width" to targetWidth,
                            "height" to targetHeight,
                            "status" to "cancelled"
                        )
                    )
                } else {
                    result.completeExceptionally(exportException)
                }
            }
        }

        withContext(Dispatchers.Main) {
            transformer = transformerBuilder
                .addListener(listener)
                .build()

            val mediaItem = MediaItem.fromUri(Uri.fromFile(inputFile))

            val isRotated = rotation == 90 || rotation == 270
            val effectiveOriginalWidth = if (isRotated) originalHeight else originalWidth
            val effectiveOriginalHeight = if (isRotated) originalWidth else originalHeight

            // Build effects for scaling if needed
            val effects = if (targetWidth != effectiveOriginalWidth || targetHeight != effectiveOriginalHeight) {
                val scaleX = targetWidth.toFloat() / effectiveOriginalWidth.toFloat()
                val scaleY = targetHeight.toFloat() / effectiveOriginalHeight.toFloat()
                Effects(
                    emptyList(),
                    listOf(
                        ScaleAndRotateTransformation.Builder()
                            .setScale(scaleX, scaleY)
                            .build()
                    )
                )
            } else {
                Effects(emptyList(), emptyList())
            }

            val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                .setEffects(effects)
                .setRemoveAudio(!includeAudio)
                .build()

            transformer!!.start(editedMediaItem, outFile.absolutePath)

            // Poll progress
            scope@ launch {
                val progressHolder = ProgressHolder()
                while (transformer != null && !result.isCompleted) {
                    val state = transformer?.getProgress(progressHolder)
                    if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                        val progress = progressHolder.progress / 100.0
                        onProgress(progress.coerceIn(0.0, 1.0))
                    }
                    delay(250)
                }
            }
        }

        result.await()
    }

    fun cancel() {
        isCancelled = true
        transformer?.cancel()
    }
}
