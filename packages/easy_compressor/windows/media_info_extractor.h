#ifndef MEDIA_INFO_EXTRACTOR_H_
#define MEDIA_INFO_EXTRACTOR_H_

#include <flutter/encodable_value.h>
#include <string>
#include <vector>

namespace easy_compressor {

class MediaInfoExtractor {
 public:
  static flutter::EncodableValue Extract(const std::string &inputPath);
  static std::vector<uint8_t> GetThumbnail(
      const std::string &inputPath,
      int positionMs,
      int quality,
      int maxHeight);
};

}  // namespace easy_compressor

#endif  // MEDIA_INFO_EXTRACTOR_H_
