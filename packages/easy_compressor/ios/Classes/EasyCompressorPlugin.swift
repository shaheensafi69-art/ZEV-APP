import Flutter
import UIKit

public class EasyCompressorPlugin: NSObject, FlutterPlugin {
    private var compressor: VideoCompressor?
    private var progressSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = EasyCompressorPlugin()

        let channel = FlutterMethodChannel(
            name: "easy_compressor",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)

        let progressChannel = FlutterEventChannel(
            name: "easy_compressor/progress",
            binaryMessenger: registrar.messenger()
        )
        progressChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "compressVideo":
            guard let args = call.arguments as? [String: Any],
                  let inputPath = args["inputPath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing inputPath", details: nil))
                return
            }

            let quality = args["quality"] as? Int ?? 70
            let maxHeight = args["maxHeight"] as? Int
            let maxWidth = args["maxWidth"] as? Int
            let frameRate = args["frameRate"] as? Int
            let includeAudio = args["includeAudio"] as? Bool ?? true
            let audioBitrate = args["audioBitrate"] as? Int ?? 128000
            let videoCodec = args["videoCodec"] as? String ?? "h264"
            let outputPath = args["outputPath"] as? String

            compressor = VideoCompressor()
            compressor?.compress(
                inputPath: inputPath,
                quality: quality,
                maxHeight: maxHeight,
                maxWidth: maxWidth,
                frameRate: frameRate,
                includeAudio: includeAudio,
                audioBitrate: audioBitrate,
                videoCodec: videoCodec,
                outputPath: outputPath,
                onProgress: { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.progressSink?(progress)
                    }
                },
                completion: { compResult in
                    DispatchQueue.main.async {
                        switch compResult {
                        case .success(let data):
                            result(data)
                        case .failure(let error):
                            result(FlutterError(
                                code: "COMPRESSION_FAILED",
                                message: error.localizedDescription,
                                details: nil
                            ))
                        }
                    }
                }
            )

        case "getMediaInfo":
            guard let args = call.arguments as? [String: Any],
                  let inputPath = args["inputPath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing inputPath", details: nil))
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let info = try MediaInfoExtractor.extract(path: inputPath)
                    DispatchQueue.main.async { result(info) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "MEDIA_INFO_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }

        case "getThumbnail":
            guard let args = call.arguments as? [String: Any],
                  let inputPath = args["inputPath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing inputPath", details: nil))
                return
            }

            let positionMs = args["positionMs"] as? Int ?? 0
            let quality = args["quality"] as? Int ?? 80
            let maxHeight = args["maxHeight"] as? Int

            DispatchQueue.global(qos: .userInitiated).async {
                let data = MediaInfoExtractor.getThumbnail(
                    path: inputPath,
                    positionMs: positionMs,
                    quality: quality,
                    maxHeight: maxHeight
                )
                DispatchQueue.main.async {
                    result(data != nil ? FlutterStandardTypedData(bytes: data!) : nil)
                }
            }

        case "cancelCompression":
            compressor?.cancel()
            result(nil)

        case "clearCache":
            VideoCompressor.clearCache()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

extension EasyCompressorPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        progressSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        progressSink = nil
        return nil
    }
}
