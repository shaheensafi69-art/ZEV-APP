#ifndef VIDEO_COMPRESSOR_H_
#define VIDEO_COMPRESSOR_H_

#include <flutter/encodable_value.h>
#include <functional>
#include <string>
#include <atomic>

namespace easy_compressor {

class VideoCompressor {
 public:
  VideoCompressor();
  ~VideoCompressor();

  flutter::EncodableValue Compress(
      const std::string &inputPath,
      int quality,
      int maxHeight,
      int maxWidth,
      int frameRate,
      bool includeAudio,
      int audioBitrate,
      const std::string &videoCodec,
      const std::string &outputPath,
      std::function<void(double)> onProgress);

  void Cancel();

  static void ClearCache();

 private:
  std::atomic<bool> is_cancelled_{false};

  static int GetResolutionCap(int height);
  static int CalculateTargetBitrate(int originalBitrate, int quality, int outputHeight);
  static std::string GetCacheDir();
};

}  // namespace easy_compressor

#endif  // VIDEO_COMPRESSOR_H_
