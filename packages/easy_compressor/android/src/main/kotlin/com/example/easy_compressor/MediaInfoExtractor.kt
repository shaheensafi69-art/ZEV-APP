package com.example.easy_compressor

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.roundToInt

object MediaInfoExtractor {

    suspend fun extract(context: Context, inputPath: String): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val file = File(inputPath)
            if (!file.exists()) {
                throw IllegalArgumentException("File does not exist: $inputPath")
            }

            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(inputPath)

            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                ?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0

            // Extract codec info and frame rate via MediaExtractor
            var videoCodec: String? = null
            var audioCodec: String? = null
            var audioBitrate: Int? = null
            var frameRate = 30.0
            var hasAudio = false

            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(inputPath)
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: continue

                    if (mime.startsWith("video/")) {
                        videoCodec = mime.replace("video/", "")
                        if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                            frameRate = format.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
                        }
                    } else if (mime.startsWith("audio/")) {
                        hasAudio = true
                        audioCodec = mime.replace("audio/", "")
                        if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
                            audioBitrate = format.getInteger(MediaFormat.KEY_BIT_RATE)
                        }
                    }
                }
            } finally {
                extractor.release()
            }

            retriever.release()

            mapOf(
                "path" to inputPath,
                "fileSize" to file.length().toInt(),
                "duration" to durationMs.toInt(),
                "width" to width,
                "height" to height,
                "frameRate" to frameRate,
                "bitrate" to bitrate,
                "videoCodec" to videoCodec,
                "audioCodec" to audioCodec,
                "audioBitrate" to audioBitrate,
                "rotation" to rotation,
                "hasAudio" to hasAudio
            )
        }

    suspend fun getThumbnail(
        context: Context,
        inputPath: String,
        positionMs: Long,
        quality: Int,
        maxHeight: Int?
    ): ByteArray? = withContext(Dispatchers.IO) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(inputPath)
            var bitmap = retriever.getFrameAtTime(
                positionMs * 1000, // convert ms to microseconds
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            ) ?: return@withContext null

            // Scale if maxHeight is specified
            if (maxHeight != null && bitmap.height > maxHeight) {
                val scale = maxHeight.toFloat() / bitmap.height
                val newWidth = (bitmap.width * scale).roundToInt()
                bitmap = Bitmap.createScaledBitmap(bitmap, newWidth, maxHeight, true)
            }

            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(0, 100), stream)
            stream.toByteArray()
        } finally {
            retriever.release()
        }
    }
}
