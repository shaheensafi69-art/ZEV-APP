#ifndef FLUTTER_PLUGIN_EASY_COMPRESSOR_PLUGIN_H_
#define FLUTTER_PLUGIN_EASY_COMPRESSOR_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace easy_compressor {

class EasyCompressorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  EasyCompressorPlugin();
  virtual ~EasyCompressorPlugin();

  EasyCompressorPlugin(const EasyCompressorPlugin &) = delete;
  EasyCompressorPlugin &operator=(const EasyCompressorPlugin &) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> progress_sink_;
};

// C API for Flutter plugin registration
extern "C" {
  __declspec(dllexport) void EasyCompressorPluginCApiRegisterWithRegistrar(
      FlutterDesktopPluginRegistrarRef registrar);
}

}  // namespace easy_compressor

#endif  // FLUTTER_PLUGIN_EASY_COMPRESSOR_PLUGIN_H_
