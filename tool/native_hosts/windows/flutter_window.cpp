#include "flutter_window.h"

#include <audioclient.h>
#include <d3d11.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/generated_plugin_registrant.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>

namespace {
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_method_channel;
std::unique_ptr<flutter::EventChannel<EncodableValue>> g_event_channel;
std::unique_ptr<flutter::EventSink<EncodableValue>> g_event_sink;

std::string Narrow(const wchar_t* value) {
  if (!value) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  std::string out(size > 0 ? size - 1 : 0, '\0');
  if (size > 1) WideCharToMultiByte(CP_UTF8, 0, value, -1, out.data(), size, nullptr, nullptr);
  return out;
}

void Emit(const char* event) {
  if (g_event_sink) g_event_sink->Success(EncodableValue(event));
}

EncodableMap ProbeCompute() {
  EncodableList decoders;
  ID3D11Device* device = nullptr;
  D3D_FEATURE_LEVEL level;
  if (SUCCEEDED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_VIDEO_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, &device, &level, nullptr))) {
    ID3D11VideoDevice* video = nullptr;
    if (SUCCEEDED(device->QueryInterface(__uuidof(ID3D11VideoDevice), reinterpret_cast<void**>(&video)))) {
      UINT count = video->GetVideoDecoderProfileCount();
      for (UINT i = 0; i < count; ++i) {
        GUID guid;
        if (FAILED(video->GetVideoDecoderProfile(i, &guid))) continue;
        const char* codec = nullptr;
        if (guid == D3D11_DECODER_PROFILE_H264_VLD_NOFGT) codec = "h264";
        if (guid == D3D11_DECODER_PROFILE_HEVC_VLD_MAIN || guid == D3D11_DECODER_PROFILE_HEVC_VLD_MAIN10) codec = "hevc";
        if (guid == D3D11_DECODER_PROFILE_MPEG2_VLD) codec = "mpeg2";
        if (!codec) continue;
        decoders.push_back(EncodableValue(EncodableMap{
            {EncodableValue("codec"), EncodableValue(codec)},
            {EncodableValue("support"), EncodableValue("supported")},
            {EncodableValue("hardwareAccelerated"), EncodableValue("supported")},
        }));
      }
      video->Release();
    }
    device->Release();
  }
  return EncodableMap{
      {EncodableValue("hardwareVideoDecoding"), EncodableValue(decoders.empty() ? "unknown" : "supported")},
      {EncodableValue("videoDecoders"), EncodableValue(decoders)},
  };
}

EncodableMap ProbeDisplay() {
  DEVMODEW mode = {};
  mode.dmSize = sizeof(mode);
  EnumDisplaySettingsW(nullptr, ENUM_CURRENT_SETTINGS, &mode);
  return EncodableMap{
      {EncodableValue("width"), EncodableValue(static_cast<int>(GetSystemMetrics(SM_CXSCREEN)))},
      {EncodableValue("height"), EncodableValue(static_cast<int>(GetSystemMetrics(SM_CYSCREEN)))},
      {EncodableValue("refreshRate"), EncodableValue(static_cast<double>(mode.dmDisplayFrequency))},
      {EncodableValue("genericHdrOutput"), EncodableValue("unknown")},
  };
}

EncodableMap ProbeAudio() {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  EncodableMap payload;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(&enumerator))) &&
      SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) {
    IPropertyStore* props = nullptr;
    if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &props))) {
      PROPVARIANT name;
      PropVariantInit(&name);
      if (SUCCEEDED(props->GetValue(PKEY_Device_FriendlyName, &name)) && name.vt == VT_LPWSTR) {
        payload[EncodableValue("routeName")] = EncodableValue(Narrow(name.pwszVal));
        payload[EncodableValue("sinkName")] = EncodableValue(Narrow(name.pwszVal));
      }
      PropVariantClear(&name);
      props->Release();
    }
    IAudioClient* client = nullptr;
    if (SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&client)))) {
      WAVEFORMATEX* format = nullptr;
      if (SUCCEEDED(client->GetMixFormat(&format)) && format) {
        payload[EncodableValue("pcmOutput")] = EncodableValue("supported");
        payload[EncodableValue("maxChannels")] = EncodableValue(static_cast<int>(format->nChannels));
        payload[EncodableValue("sampleRates")] = EncodableValue(EncodableList{EncodableValue(static_cast<int>(format->nSamplesPerSec))});
        CoTaskMemFree(format);
      }
      client->Release();
    }
  }
  if (device) device->Release();
  if (enumerator) enumerator->Release();
  return payload;
}

void SetupPlaybackChannels(flutter::BinaryMessenger* messenger) {
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();
  g_method_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "rodplayer/playback_capabilities", codec);
  g_method_channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "probeCompute") return result->Success(EncodableValue(ProbeCompute()));
    if (call.method_name() == "probeDisplay") return result->Success(EncodableValue(ProbeDisplay()));
    if (call.method_name() == "probeAudio") return result->Success(EncodableValue(ProbeAudio()));
    result->NotImplemented();
  });
  g_event_channel = std::make_unique<flutter::EventChannel<EncodableValue>>(messenger, "rodplayer/playback_capability_events", codec);
  g_event_channel->SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
      [](const EncodableValue*, std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink) {
        g_event_sink = std::move(sink);
        return nullptr;
      },
      [](const EncodableValue*) {
        g_event_sink.reset();
        return nullptr;
      }));
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project) : project_(project) {}
FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;
  RegisterPlugins(flutter_controller_->engine());
  SetupPlaybackChannels(flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept {
  if (message == WM_DISPLAYCHANGE) Emit("displayChanged");
  if (message == WM_DEVICECHANGE) Emit("audioRouteChanged");
  if (message == WM_POWERBROADCAST && wparam == PBT_APMRESUMEAUTOMATIC) Emit("resume");
  if (flutter_controller_) {
    std::optional<LRESULT> result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
