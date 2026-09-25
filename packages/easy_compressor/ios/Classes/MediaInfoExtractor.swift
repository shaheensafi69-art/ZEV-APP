import AVFoundation
import UIKit

class MediaInfoExtractor {

    static func extract(path: String) throws -> [String: Any?] {
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let durationMs = Int(CMTimeGetSeconds(asset.duration) * 1000)

        var width = 0
        var height = 0
        var frameRate: Double = 0
        var bitrate = 0
        var videoCodec: String?
        var rotation = 0

        if let videoTrack = asset.tracks(withMediaType: .video).first {
            let naturalSize = videoTrack.naturalSize
            let transform = videoTrack.preferredTransform

            let isRotated = transform.a == 0
            width = Int(isRotated ? naturalSize.height : naturalSize.width)
            height = Int(isRotated ? naturalSize.width : naturalSize.height)
            frameRate = Double(videoTrack.nominalFrameRate)
            bitrate = Int(videoTrack.estimatedDataRate)

            // Determine rotation
            if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
                rotation = 90
            } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
                rotation = 270
            } else if transform.a == -1.0 && transform.d == -1.0 {
                rotation = 180
            }

            // Get codec from format descriptions
            if let formatDescription = videoTrack.formatDescriptions.first {
                let desc = formatDescription as! CMFormatDescription
                let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                videoCodec = fourCharCodeToString(mediaSubType)
            }
        }

        var audioCodec: String?
        var audioBitrate: Int?
        var hasAudio = false

        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            hasAudio = true
            audioBitrate = Int(audioTrack.estimatedDataRate)

            if let formatDescription = audioTrack.formatDescriptions.first {
                let desc = formatDescription as! CMFormatDescription
                let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                audioCodec = fourCharCodeToString(mediaSubType)
            }
        }

        return [
            "path": path,
            "fileSize": fileSize,
            "duration": durationMs,
            "width": width,
            "height": height,
            "frameRate": frameRate,
            "bitrate": bitrate,
            "videoCodec": videoCodec,
            "audioCodec": audioCodec,
            "audioBitrate": audioBitrate,
            "rotation": rotation,
            "hasAudio": hasAudio
        ]
    }

    static func getThumbnail(path: String, positionMs: Int, quality: Int, maxHeight: Int?) -> Data? {
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        if let mh = maxHeight {
            generator.maximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat(mh))
        }

        let time = CMTime(value: Int64(positionMs), timescale: 1000)

        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: CGFloat(max(0, min(100, quality))) / 100.0)
        } catch {
            return nil
        }
    }

    private static func fourCharCodeToString(_ code: FourCharCode) -> String {
        let chars: [Character] = [
            Character(UnicodeScalar((code >> 24) & 0xFF)!),
            Character(UnicodeScalar((code >> 16) & 0xFF)!),
            Character(UnicodeScalar((code >> 8) & 0xFF)!),
            Character(UnicodeScalar(code & 0xFF)!)
        ]
        return String(chars).trimmingCharacters(in: .whitespaces)
    }
}
