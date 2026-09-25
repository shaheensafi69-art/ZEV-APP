import AVFoundation
import CoreMedia

class VideoCompressor {
    private var assetReader: AVAssetReader?
    private var assetWriter: AVAssetWriter?
    private var isCancelled = false

    private static let cacheDirName = "easy_compressor_cache"

    static func clearCache() {
        let tempDir = NSTemporaryDirectory()
        let cacheDir = (tempDir as NSString).appendingPathComponent(cacheDirName)
        try? FileManager.default.removeItem(atPath: cacheDir)
    }

    private static func getResolutionCap(_ height: Int) -> Int {
        switch height {
        case ...480: return 2_500_000
        case ...720: return 5_000_000
        case ...1080: return 8_000_000
        case ...1440: return 14_000_000
        default: return 20_000_000
        }
    }

    private static func calculateTargetBitrate(originalBitrate: Int, quality: Int, outputHeight: Int) -> Int {
        let q = max(0, min(100, quality))
        let factor = 0.05 + 0.95 * (Double(q) / 100.0)
        let qualityBitrate = Int(Double(originalBitrate) * factor)
        let capBitrate = getResolutionCap(outputHeight)
        return min(qualityBitrate, capBitrate)
    }

    func compress(
        inputPath: String,
        quality: Int,
        maxHeight: Int?,
        maxWidth: Int?,
        frameRate: Int?,
        includeAudio: Bool,
        audioBitrate: Int,
        videoCodec: String,
        outputPath: String?,
        onProgress: @escaping (Double) -> Void,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        isCancelled = false
        let startTime = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let result = try self.performCompression(
                    inputPath: inputPath,
                    quality: quality,
                    maxHeight: maxHeight,
                    maxWidth: maxWidth,
                    frameRate: frameRate,
                    includeAudio: includeAudio,
                    audioBitrate: audioBitrate,
                    videoCodec: videoCodec,
                    outputPath: outputPath,
                    startTime: startTime,
                    onProgress: onProgress
                )
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func performCompression(
        inputPath: String,
        quality: Int,
        maxHeight: Int?,
        maxWidth: Int?,
        frameRate: Int?,
        includeAudio: Bool,
        audioBitrate: Int,
        videoCodec: String,
        outputPath: String?,
        startTime: Date,
        onProgress: @escaping (Double) -> Void
    ) throws -> [String: Any] {
        let inputURL = URL(fileURLWithPath: inputPath)
        let asset = AVAsset(url: inputURL)

        let originalSize = try FileManager.default.attributesOfItem(atPath: inputPath)[.size] as? Int ?? 0

        // Get video track
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw NSError(domain: "EasyCompressor", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No video track found"
            ])
        }

        let naturalSize = videoTrack.naturalSize
        let transform = videoTrack.preferredTransform
        let durationMs = Int(CMTimeGetSeconds(asset.duration) * 1000)

        // Determine actual dimensions (accounting for rotation)
        let isRotated = transform.a == 0
        var originalWidth = Int(isRotated ? naturalSize.height : naturalSize.width)
        var originalHeight = Int(isRotated ? naturalSize.width : naturalSize.height)

        let originalBitrate = Int(videoTrack.estimatedDataRate)

        // Calculate output dimensions
        var targetWidth = originalWidth
        var targetHeight = originalHeight

        if let mh = maxHeight, targetHeight > mh {
            let scale = Double(mh) / Double(targetHeight)
            targetHeight = mh
            targetWidth = Int(Double(targetWidth) * scale)
        }
        if let mw = maxWidth, targetWidth > mw {
            let scale = Double(mw) / Double(targetWidth)
            targetWidth = mw
            targetHeight = Int(Double(targetHeight) * scale)
        }

        // Ensure even dimensions
        targetWidth = (targetWidth / 2) * 2
        targetHeight = (targetHeight / 2) * 2
        if targetWidth < 2 { targetWidth = 2 }
        if targetHeight < 2 { targetHeight = 2 }

        let targetBitrate = VideoCompressor.calculateTargetBitrate(
            originalBitrate: originalBitrate,
            quality: quality,
            outputHeight: targetHeight
        )

        // Output URL
        let outURL: URL
        if let op = outputPath {
            outURL = URL(fileURLWithPath: op)
        } else {
            let tempDir = NSTemporaryDirectory()
            let cacheDir = (tempDir as NSString).appendingPathComponent(VideoCompressor.cacheDirName)
            try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            let filename = "compressed_\(Int(Date().timeIntervalSince1970 * 1000)).mp4"
            outURL = URL(fileURLWithPath: (cacheDir as NSString).appendingPathComponent(filename))
        }

        // Remove existing output file
        try? FileManager.default.removeItem(at: outURL)

        // Setup reader
        let reader = try AVAssetReader(asset: asset)
        self.assetReader = reader

        let videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
        videoOutput.alwaysCopiesSampleData = false
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }

        var audioOutput: AVAssetReaderTrackOutput?
        let audioTrack = asset.tracks(withMediaType: .audio).first
        if includeAudio, let at = audioTrack {
            let audioReaderSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2
            ]
            let aOutput = AVAssetReaderTrackOutput(track: at, outputSettings: audioReaderSettings)
            aOutput.alwaysCopiesSampleData = false
            if reader.canAdd(aOutput) {
                reader.add(aOutput)
                audioOutput = aOutput
            }
        }

        // Setup writer
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        self.assetWriter = writer

        let codecType: AVVideoCodecType = videoCodec == "h265" ? .hevc : .h264

        let videoWriterSettings: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ] as [String: Any]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
        videoInput.expectsMediaDataInRealTime = false

        // Apply transform to handle rotation
        if !isRotated {
            videoInput.transform = transform
        }

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }

        var audioInput: AVAssetWriterInput?
        if includeAudio && audioOutput != nil {
            let audioWriterSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: audioBitrate
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioWriterSettings)
            aInput.expectsMediaDataInRealTime = false
            if writer.canAdd(aInput) {
                writer.add(aInput)
                audioInput = aInput
            }
        }

        // Start reading and writing
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalDuration = CMTimeGetSeconds(asset.duration)
        let videoFinished = DispatchSemaphore(value: 0)
        let audioFinished = DispatchSemaphore(value: 0)

        // Write video samples
        let videoQueue = DispatchQueue(label: "com.easycompressor.video")
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            while videoInput.isReadyForMoreMediaData {
                if self?.isCancelled == true {
                    videoInput.markAsFinished()
                    videoFinished.signal()
                    return
                }

                if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let currentTime = CMTimeGetSeconds(timestamp)
                    if totalDuration > 0 {
                        onProgress(min(currentTime / totalDuration, 1.0))
                    }
                    videoInput.append(sampleBuffer)
                } else {
                    videoInput.markAsFinished()
                    videoFinished.signal()
                    return
                }
            }
        }

        // Write audio samples
        if let aOutput = audioOutput, let aInput = audioInput {
            let audioQueue = DispatchQueue(label: "com.easycompressor.audio")
            aInput.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
                while aInput.isReadyForMoreMediaData {
                    if self?.isCancelled == true {
                        aInput.markAsFinished()
                        audioFinished.signal()
                        return
                    }

                    if let sampleBuffer = aOutput.copyNextSampleBuffer() {
                        aInput.append(sampleBuffer)
                    } else {
                        aInput.markAsFinished()
                        audioFinished.signal()
                        return
                    }
                }
            }
        } else {
            audioFinished.signal()
        }

        // Wait for both to finish
        videoFinished.wait()
        audioFinished.wait()

        if isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            return [
                "outputPath": outURL.path,
                "originalSize": originalSize,
                "compressedSize": 0,
                "duration": durationMs,
                "compressionTime": Int(Date().timeIntervalSince(startTime) * 1000),
                "width": targetWidth,
                "height": targetHeight,
                "status": "cancelled"
            ]
        }

        // Finish writing
        let finishSemaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finishSemaphore.signal()
        }
        finishSemaphore.wait()

        let compressedSize = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
        let compressionTime = Int(Date().timeIntervalSince(startTime) * 1000)

        onProgress(1.0)

        return [
            "outputPath": outURL.path,
            "originalSize": originalSize,
            "compressedSize": compressedSize,
            "duration": durationMs,
            "compressionTime": compressionTime,
            "width": targetWidth,
            "height": targetHeight,
            "status": "success"
        ]
    }

    func cancel() {
        isCancelled = true
        assetReader?.cancelReading()
    }
}
