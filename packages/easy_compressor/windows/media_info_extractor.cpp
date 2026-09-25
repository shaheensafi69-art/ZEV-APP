#include "media_info_extractor.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>

#include <string>
#include <codecvt>
#include <locale>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "propsys.lib")

namespace easy_compressor {

static std::wstring Utf8ToWideLocal(const std::string &str) {
    if (str.empty()) return L"";
    int size = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
    std::wstring result(size - 1, 0);
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, &result[0], size);
    return result;
}

flutter::EncodableValue MediaInfoExtractor::Extract(const std::string &inputPath) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    MFStartup(MF_VERSION);

    std::wstring wPath = Utf8ToWideLocal(inputPath);

    flutter::EncodableMap result;
    result[flutter::EncodableValue("path")] = flutter::EncodableValue(inputPath);

    // File size
    int64_t fileSize = 0;
    {
        WIN32_FILE_ATTRIBUTE_DATA fileInfo;
        if (GetFileAttributesExW(wPath.c_str(), GetFileExInfoStandard, &fileInfo)) {
            LARGE_INTEGER li;
            li.HighPart = fileInfo.nFileSizeHigh;
            li.LowPart = fileInfo.nFileSizeLow;
            fileSize = li.QuadPart;
        }
    }
    result[flutter::EncodableValue("fileSize")] = flutter::EncodableValue(static_cast<int>(fileSize));

    IMFSourceReader *reader = nullptr;
    HRESULT hr = MFCreateSourceReaderFromURL(wPath.c_str(), nullptr, &reader);

    int width = 0, height = 0, bitrate = 0;
    double frameRate = 0;
    int durationMs = 0;
    bool hasAudio = false;
    std::string videoCodec = "";
    std::string audioCodec = "";
    int audioBitrate = 0;

    if (SUCCEEDED(hr) && reader) {
        // Duration
        PROPVARIANT durationVar;
        PropVariantInit(&durationVar);
        hr = reader->GetPresentationAttribute(MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &durationVar);
        if (SUCCEEDED(hr)) {
            int64_t durationHns = 0;
            PropVariantToInt64(durationVar, &durationHns);
            durationMs = static_cast<int>(durationHns / 10000);
        }
        PropVariantClear(&durationVar);

        // Video info
        IMFMediaType *videoType = nullptr;
        hr = reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &videoType);
        if (SUCCEEDED(hr) && videoType) {
            UINT32 w = 0, h = 0;
            MFGetAttributeSize(videoType, MF_MT_FRAME_SIZE, &w, &h);
            width = w;
            height = h;

            UINT32 fpsNum = 0, fpsDen = 1;
            MFGetAttributeRatio(videoType, MF_MT_FRAME_RATE, &fpsNum, &fpsDen);
            if (fpsDen > 0) frameRate = static_cast<double>(fpsNum) / fpsDen;

            videoType->GetUINT32(MF_MT_AVG_BITRATE, reinterpret_cast<UINT32 *>(&bitrate));
            if (bitrate == 0 && durationMs > 0) {
                bitrate = static_cast<int>((fileSize * 8 * 1000) / durationMs);
            }

            GUID subtype;
            videoType->GetGUID(MF_MT_SUBTYPE, &subtype);
            if (subtype == MFVideoFormat_H264) videoCodec = "h264";
            else if (subtype == MFVideoFormat_HEVC) videoCodec = "hevc";
            else videoCodec = "unknown";

            videoType->Release();
        }

        // Audio info
        IMFMediaType *audioType = nullptr;
        hr = reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, &audioType);
        if (SUCCEEDED(hr) && audioType) {
            hasAudio = true;

            GUID subtype;
            audioType->GetGUID(MF_MT_SUBTYPE, &subtype);
            if (subtype == MFAudioFormat_AAC) audioCodec = "aac";
            else if (subtype == MFAudioFormat_MP3) audioCodec = "mp3";
            else audioCodec = "unknown";

            UINT32 ab = 0;
            audioType->GetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, &ab);
            audioBitrate = ab * 8;

            audioType->Release();
        }

        reader->Release();
    }

    result[flutter::EncodableValue("duration")] = flutter::EncodableValue(durationMs);
    result[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
    result[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
    result[flutter::EncodableValue("frameRate")] = flutter::EncodableValue(frameRate);
    result[flutter::EncodableValue("bitrate")] = flutter::EncodableValue(bitrate);
    result[flutter::EncodableValue("videoCodec")] = flutter::EncodableValue(videoCodec);
    result[flutter::EncodableValue("audioCodec")] = flutter::EncodableValue(audioCodec);
    result[flutter::EncodableValue("audioBitrate")] = flutter::EncodableValue(audioBitrate);
    result[flutter::EncodableValue("rotation")] = flutter::EncodableValue(0);
    result[flutter::EncodableValue("hasAudio")] = flutter::EncodableValue(hasAudio);

    MFShutdown();
    CoUninitialize();

    return flutter::EncodableValue(result);
}

std::vector<uint8_t> MediaInfoExtractor::GetThumbnail(
    const std::string &inputPath,
    int positionMs,
    int quality,
    int maxHeight) {
    // Windows thumbnail extraction using MF Source Reader
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    MFStartup(MF_VERSION);

    std::wstring wPath = Utf8ToWideLocal(inputPath);

    IMFSourceReader *reader = nullptr;
    HRESULT hr = MFCreateSourceReaderFromURL(wPath.c_str(), nullptr, &reader);

    std::vector<uint8_t> result;

    if (FAILED(hr) || !reader) {
        MFShutdown();
        CoUninitialize();
        return result;
    }

    // Configure to output RGB32
    IMFMediaType *outputType = nullptr;
    MFCreateMediaType(&outputType);
    outputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    outputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, outputType);
    outputType->Release();

    // Seek to position
    PROPVARIANT seekPos;
    PropVariantInit(&seekPos);
    seekPos.vt = VT_I8;
    seekPos.hVal.QuadPart = static_cast<LONGLONG>(positionMs) * 10000; // to 100ns units
    reader->SetCurrentPosition(GUID_NULL, seekPos);
    PropVariantClear(&seekPos);

    // Read a single frame
    DWORD streamIndex = 0, flags = 0;
    LONGLONG timestamp = 0;
    IMFSample *sample = nullptr;

    hr = reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
                             &streamIndex, &flags, &timestamp, &sample);

    if (SUCCEEDED(hr) && sample) {
        IMFMediaBuffer *buffer = nullptr;
        sample->ConvertToContiguousBuffer(&buffer);

        if (buffer) {
            BYTE *data = nullptr;
            DWORD dataLen = 0;
            buffer->Lock(&data, nullptr, &dataLen);

            // Return raw BGRA bytes — the Dart layer or a more complete
            // implementation would encode to JPEG, but for simplicity we
            // return the raw bitmap data. In practice, this could be enhanced
            // with WIC (Windows Imaging Component) encoding.
            if (data && dataLen > 0) {
                result.assign(data, data + dataLen);
            }

            buffer->Unlock();
            buffer->Release();
        }
        sample->Release();
    }

    reader->Release();
    MFShutdown();
    CoUninitialize();

    return result;
}

}  // namespace easy_compressor
