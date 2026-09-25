#include "easy_compressor_plugin.h"
#include "video_compressor.h"
#include "media_info_extractor.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <thread>

namespace easy_compressor {

static std::unique_ptr<VideoCompressor> g_compressor;

void EasyCompressorPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "easy_compressor",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<EasyCompressorPlugin>();

  channel->SetMethodCallHandler(
      [plugin_ptr = plugin.get()](const auto &call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "easy_compressor/progress",
      &flutter::StandardMethodCodec::GetInstance());

  auto event_handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [plugin_ptr = plugin.get()](
          const flutter::EncodableValue *arguments,
          std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        plugin_ptr->progress_sink_ = std::move(events);
        return nullptr;
      },
      [plugin_ptr = plugin.get()](const flutter::EncodableValue *arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        plugin_ptr->progress_sink_.reset();
        return nullptr;
      });

  event_channel->SetStreamHandler(std::move(event_handler));

  registrar->AddPlugin(std::move(plugin));
}

EasyCompressorPlugin::EasyCompressorPlugin() {}
EasyCompressorPlugin::~EasyCompressorPlugin() {}

void EasyCompressorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  if (method_call.method_name() == "compressVideo") {
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }

    auto get_string = [&](const std::string &key) -> std::string {
      auto it = args->find(flutter::EncodableValue(key));
      if (it != args->end() && !it->second.IsNull()) {
        return std::get<std::string>(it->second);
      }
      return "";
    };

    auto get_int = [&](const std::string &key, int def) -> int {
      auto it = args->find(flutter::EncodableValue(key));
      if (it != args->end() && !it->second.IsNull()) {
        return std::get<int>(it->second);
      }
      return def;
    };

    auto get_bool = [&](const std::string &key, bool def) -> bool {
      auto it = args->find(flutter::EncodableValue(key));
      if (it != args->end() && !it->second.IsNull()) {
        return std::get<bool>(it->second);
      }
      return def;
    };

    auto get_optional_int = [&](const std::string &key) -> int {
      auto it = args->find(flutter::EncodableValue(key));
      if (it != args->end() && !it->second.IsNull()) {
        return std::get<int>(it->second);
      }
      return -1;
    };

    std::string inputPath = get_string("inputPath");
    int quality = get_int("quality", 70);
    int maxHeight = get_optional_int("maxHeight");
    int maxWidth = get_optional_int("maxWidth");
    int frameRateVal = get_optional_int("frameRate");
    bool includeAudio = get_bool("includeAudio", true);
    int audioBitrate = get_int("audioBitrate", 128000);
    std::string videoCodec = get_string("videoCodec");
    std::string outputPath = get_string("outputPath");

    auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
        std::move(result));

    auto progress_sink = progress_sink_.get();

    std::thread([=, this]() mutable {
      g_compressor = std::make_unique<VideoCompressor>();

      auto compResult = g_compressor->Compress(
          inputPath, quality, maxHeight, maxWidth, frameRateVal,
          includeAudio, audioBitrate, videoCodec, outputPath,
          [progress_sink](double progress) {
            if (progress_sink) {
              progress_sink->Success(flutter::EncodableValue(progress));
            }
          });

      shared_result->Success(compResult);
    }).detach();

  } else if (method_call.method_name() == "getMediaInfo") {
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }

    auto it = args->find(flutter::EncodableValue("inputPath"));
    if (it == args->end()) {
      result->Error("INVALID_ARGS", "Missing inputPath");
      return;
    }
    std::string inputPath = std::get<std::string>(it->second);

    auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
        std::move(result));

    std::thread([inputPath, shared_result]() {
      auto info = MediaInfoExtractor::Extract(inputPath);
      shared_result->Success(info);
    }).detach();

  } else if (method_call.method_name() == "getThumbnail") {
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }

    auto get_str = [&](const std::string &key) -> std::string {
      auto it = args->find(flutter::EncodableValue(key));
      if (it != args->end()) return std::get<std::string>(it->second);
      return "";
    };
    auto get_int = [&](const std::string &key, int def) -> int {
      auto it = args->find(flutter::EncodableValue(key));
      if (it != args->end() && !it->second.IsNull()) return std::get<int>(it->second);
      return def;
    };

    std::string inputPath = get_str("inputPath");
    int positionMs = get_int("positionMs", 0);
    int quality = get_int("quality", 80);
    int maxHeight = get_int("maxHeight", -1);

    auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
        std::move(result));

    std::thread([inputPath, positionMs, quality, maxHeight, shared_result]() {
      auto bytes = MediaInfoExtractor::GetThumbnail(inputPath, positionMs, quality, maxHeight);
      if (bytes.empty()) {
        shared_result->Success(flutter::EncodableValue());
      } else {
        shared_result->Success(flutter::EncodableValue(bytes));
      }
    }).detach();

  } else if (method_call.method_name() == "cancelCompression") {
    if (g_compressor) {
      g_compressor->Cancel();
    }
    result->Success(flutter::EncodableValue());

  } else if (method_call.method_name() == "clearCache") {
    VideoCompressor::ClearCache();
    result->Success(flutter::EncodableValue());

  } else {
    result->NotImplemented();
  }
}

extern "C" {
  __declspec(dllexport) void EasyCompressorPluginCApiRegisterWithRegistrar(
      FlutterDesktopPluginRegistrarRef registrar) {
    easy_compressor::EasyCompressorPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
  }
}

}  // namespace easy_compressor
