#include "video_compressor.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <shlwapi.h>
#include <propvarutil.h>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <string>
#include <codecvt>
#include <locale>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "propsys.lib")

namespace easy_compressor {

namespace fs = std::filesystem;

static std::wstring Utf8ToWide(const std::string &str) {
    if (str.empty()) return L"";
    int size = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
    std::wstring result(size - 1, 0);
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, &result[0], size);
    return result;
}

static std::string WideToUtf8(const std::wstring &wstr) {
    if (wstr.empty()) return "";
    int size = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string result(size - 1, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &result[0], size, nullptr, nullptr);
    return result;
}

VideoCompressor::VideoCompressor() {}
VideoCompressor::~VideoCompressor() {}

int VideoCompressor::GetResolutionCap(int height) {
    if (height <= 480) return 2500000;
    if (height <= 720) return 5000000;
    if (height <= 1080) return 8000000;
    if (height <= 1440) return 14000000;
    return 20000000;
}

int VideoCompressor::CalculateTargetBitrate(int originalBitrate, int quality, int outputHeight) {
    int q = std::clamp(quality, 0, 100);
    double factor = 0.05 + 0.95 * (q / 100.0);
    int qualityBitrate = static_cast<int>(originalBitrate * factor);
    int capBitrate = GetResolutionCap(outputHeight);
    return std::min(qualityBitrate, capBitrate);
}

std::string VideoCompressor::GetCacheDir() {
    wchar_t tempPath[MAX_PATH];
    GetTempPathW(MAX_PATH, tempPath);
    fs::path cacheDir = fs::path(tempPath) / "easy_compressor_cache";
    fs::create_directories(cacheDir);
    return WideToUtf8(cacheDir.wstring());
}

void VideoCompressor::ClearCache() {
    wchar_t tempPath[MAX_PATH];
    GetTempPathW(MAX_PATH, tempPath);
    fs::path cacheDir = fs::path(tempPath) / "easy_compressor_cache";
    if (fs::exists(cacheDir)) {
        fs::remove_all(cacheDir);
    }
}

void VideoCompressor::Cancel() {
    is_cancelled_ = true;
}

flutter::EncodableValue VideoCompressor::Compress(
    const std::string &inputPath,
    int quality,
    int maxHeight,
    int maxWidth,
    int frameRate,
    bool includeAudio,
    int audioBitrate,
    const std::string &videoCodec,
    const std::string &outputPath,
    std::function<void(double)> onProgress) {

    is_cancelled_ = false;
    auto startTime = std::chrono::steady_clock::now();

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) hr = S_OK; // already initialized
    MFStartup(MF_VERSION);

    std::wstring wInputPath = Utf8ToWide(inputPath);

    // Get original file size
    int64_t originalSize = 0;
    {
        WIN32_FILE_ATTRIBUTE_DATA fileInfo;
        if (GetFileAttributesExW(wInputPath.c_str(), GetFileExInfoStandard, &fileInfo)) {
            LARGE_INTEGER li;
            li.HighPart = fileInfo.nFileSizeHigh;
            li.LowPart = fileInfo.nFileSizeLow;
            originalSize = li.QuadPart;
        }
    }

    // Create source reader
    IMFSourceReader *reader = nullptr;
    hr = MFCreateSourceReaderFromURL(wInputPath.c_str(), nullptr, &reader);
    if (FAILED(hr) || !reader) {
        MFShutdown();
        CoUninitialize();
        flutter::EncodableMap errorMap;
        errorMap[flutter::EncodableValue("status")] = flutter::EncodableValue("failed");
        errorMap[flutter::EncodableValue("outputPath")] = flutter::EncodableValue("");
        errorMap[flutter::EncodableValue("originalSize")] = flutter::EncodableValue(static_cast<int>(originalSize));
        errorMap[flutter::EncodableValue("compressedSize")] = flutter::EncodableValue(0);
        errorMap[flutter::EncodableValue("duration")] = flutter::EncodableValue(0);
        errorMap[flutter::EncodableValue("compressionTime")] = flutter::EncodableValue(0);
        errorMap[flutter::EncodableValue("width")] = flutter::EncodableValue(0);
        errorMap[flutter::EncodableValue("height")] = flutter::EncodableValue(0);
        return flutter::EncodableValue(errorMap);
    }

    // Get video info from source
    IMFMediaType *videoType = nullptr;
    reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &videoType);

    UINT32 origWidth = 0, origHeight = 0;
    MFGetAttributeSize(videoType, MF_MT_FRAME_SIZE, &origWidth, &origHeight);

    UINT32 fpsNum = 30, fpsDen = 1;
    MFGetAttributeRatio(videoType, MF_MT_FRAME_RATE, &fpsNum, &fpsDen);

    UINT32 origBitrate = 0;
    videoType->GetUINT32(MF_MT_AVG_BITRATE, &origBitrate);
    if (origBitrate == 0) {
        // Estimate from file size and duration
        PROPVARIANT duration;
        PropVariantInit(&duration);
        reader->GetPresentationAttribute(MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &duration);
        int64_t durationHns = 0;
        PropVariantToInt64(duration, &durationHns);
        PropVariantClear(&duration);
        double durationSec = durationHns / 10000000.0;
        if (durationSec > 0) {
            origBitrate = static_cast<UINT32>((originalSize * 8) / durationSec);
        } else {
            origBitrate = 10000000;
        }
    }
    videoType->Release();

    // Get duration
    PROPVARIANT durationVar;
    PropVariantInit(&durationVar);
    reader->GetPresentationAttribute(MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &durationVar);
    int64_t totalDurationHns = 0;
    PropVariantToInt64(durationVar, &totalDurationHns);
    PropVariantClear(&durationVar);
    int durationMs = static_cast<int>(totalDurationHns / 10000);

    // Calculate output dimensions
    int targetWidth = static_cast<int>(origWidth);
    int targetHeight = static_cast<int>(origHeight);

    if (maxHeight > 0 && targetHeight > maxHeight) {
        double scale = static_cast<double>(maxHeight) / targetHeight;
        targetHeight = maxHeight;
        targetWidth = static_cast<int>(targetWidth * scale);
    }
    if (maxWidth > 0 && targetWidth > maxWidth) {
        double scale = static_cast<double>(maxWidth) / targetWidth;
        targetWidth = maxWidth;
        targetHeight = static_cast<int>(targetHeight * scale);
    }

    targetWidth = (targetWidth / 2) * 2;
    targetHeight = (targetHeight / 2) * 2;
    if (targetWidth < 2) targetWidth = 2;
    if (targetHeight < 2) targetHeight = 2;

    int targetBitrate = CalculateTargetBitrate(origBitrate, quality, targetHeight);

    UINT32 targetFpsNum = fpsNum;
    UINT32 targetFpsDen = fpsDen;
    if (frameRate > 0) {
        targetFpsNum = frameRate;
        targetFpsDen = 1;
    }

    // Output path
    std::wstring wOutputPath;
    if (!outputPath.empty()) {
        wOutputPath = Utf8ToWide(outputPath);
    } else {
        auto cacheDir = GetCacheDir();
        auto timestamp = std::chrono::system_clock::now().time_since_epoch().count();
        wOutputPath = Utf8ToWide(cacheDir + "\\compressed_" + std::to_string(timestamp) + ".mp4");
    }

    // Delete existing output
    DeleteFileW(wOutputPath.c_str());

    // Configure reader to decode video
    IMFMediaType *readerVideoType = nullptr;
    MFCreateMediaType(&readerVideoType);
    readerVideoType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    readerVideoType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, readerVideoType);
    readerVideoType->Release();

    if (includeAudio) {
        IMFMediaType *readerAudioType = nullptr;
        MFCreateMediaType(&readerAudioType);
        readerAudioType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        readerAudioType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
        reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, nullptr, readerAudioType);
        readerAudioType->Release();
    }

    // Create sink writer
    IMFSinkWriter *writer = nullptr;
    IMFAttributes *writerAttrs = nullptr;
    MFCreateAttributes(&writerAttrs, 1);
    writerAttrs->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    hr = MFCreateSinkWriterFromURL(wOutputPath.c_str(), nullptr, writerAttrs, &writer);
    writerAttrs->Release();

    if (FAILED(hr) || !writer) {
        reader->Release();
        MFShutdown();
        CoUninitialize();
        flutter::EncodableMap errorMap;
        errorMap[flutter::EncodableValue("status")] = flutter::EncodableValue("failed");
        errorMap[flutter::EncodableValue("outputPath")] = flutter::EncodableValue(WideToUtf8(wOutputPath));
        errorMap[flutter::EncodableValue("originalSize")] = flutter::EncodableValue(static_cast<int>(originalSize));
        errorMap[flutter::EncodableValue("compressedSize")] = flutter::EncodableValue(0);
        errorMap[flutter::EncodableValue("duration")] = flutter::EncodableValue(durationMs);
        errorMap[flutter::EncodableValue("compressionTime")] = flutter::EncodableValue(0);
        errorMap[flutter::EncodableValue("width")] = flutter::EncodableValue(targetWidth);
        errorMap[flutter::EncodableValue("height")] = flutter::EncodableValue(targetHeight);
        return flutter::EncodableValue(errorMap);
    }

    // Add video output stream
    IMFMediaType *outputVideoType = nullptr;
    MFCreateMediaType(&outputVideoType);
    outputVideoType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    outputVideoType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    outputVideoType->SetUINT32(MF_MT_AVG_BITRATE, targetBitrate);
    MFSetAttributeSize(outputVideoType, MF_MT_FRAME_SIZE, targetWidth, targetHeight);
    MFSetAttributeRatio(outputVideoType, MF_MT_FRAME_RATE, targetFpsNum, targetFpsDen);
    MFSetAttributeRatio(outputVideoType, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    outputVideoType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);

    DWORD videoStreamIndex = 0;
    hr = writer->AddStream(outputVideoType, &videoStreamIndex);
    outputVideoType->Release();

    // Set video input type
    IMFMediaType *inputVideoType = nullptr;
    MFCreateMediaType(&inputVideoType);
    inputVideoType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    inputVideoType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    MFSetAttributeSize(inputVideoType, MF_MT_FRAME_SIZE, origWidth, origHeight);
    MFSetAttributeRatio(inputVideoType, MF_MT_FRAME_RATE, fpsNum, fpsDen);
    writer->SetInputMediaType(videoStreamIndex, inputVideoType, nullptr);
    inputVideoType->Release();

    // Add audio output stream
    DWORD audioStreamIndex = 0;
    bool hasAudio = false;
    if (includeAudio) {
        IMFMediaType *outputAudioType = nullptr;
        MFCreateMediaType(&outputAudioType);
        outputAudioType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        outputAudioType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
        outputAudioType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        outputAudioType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 44100);
        outputAudioType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
        outputAudioType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, audioBitrate / 8);

        hr = writer->AddStream(outputAudioType, &audioStreamIndex);
        outputAudioType->Release();

        if (SUCCEEDED(hr)) {
            hasAudio = true;
            IMFMediaType *inputAudioType = nullptr;
            MFCreateMediaType(&inputAudioType);
            inputAudioType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
            inputAudioType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
            inputAudioType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
            inputAudioType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 44100);
            inputAudioType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
            writer->SetInputMediaType(audioStreamIndex, inputAudioType, nullptr);
            inputAudioType->Release();
        }
    }

    // Start writing
    writer->BeginWriting();

    // Read and write samples
    bool videoComplete = false;
    bool audioComplete = !hasAudio;

    while (!videoComplete || !audioComplete) {
        if (is_cancelled_) break;

        DWORD streamIndex = 0;
        DWORD flags = 0;
        LONGLONG timestamp = 0;
        IMFSample *sample = nullptr;

        // Read from whichever stream is available
        DWORD readStream = videoComplete ? MF_SOURCE_READER_FIRST_AUDIO_STREAM
                                          : MF_SOURCE_READER_FIRST_VIDEO_STREAM;

        if (!videoComplete) {
            readStream = MF_SOURCE_READER_FIRST_VIDEO_STREAM;
        } else if (!audioComplete) {
            readStream = MF_SOURCE_READER_FIRST_AUDIO_STREAM;
        }

        hr = reader->ReadSample(readStream, 0, &streamIndex, &flags, &timestamp, &sample);

        if (FAILED(hr)) break;

        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
            if (readStream == MF_SOURCE_READER_FIRST_VIDEO_STREAM) {
                videoComplete = true;
            } else {
                audioComplete = true;
            }
            if (sample) sample->Release();
            continue;
        }

        if (sample) {
            DWORD writeStream = (readStream == MF_SOURCE_READER_FIRST_VIDEO_STREAM)
                                    ? videoStreamIndex
                                    : audioStreamIndex;
            sample->SetSampleTime(timestamp);
            writer->WriteSample(writeStream, sample);
            sample->Release();

            // Report progress
            if (totalDurationHns > 0 && readStream == MF_SOURCE_READER_FIRST_VIDEO_STREAM) {
                double progress = static_cast<double>(timestamp) / totalDurationHns;
                progress = std::clamp(progress, 0.0, 1.0);
                if (onProgress) onProgress(progress);
            }
        }
    }

    // If not cancelled, read audio samples if we haven't finished them
    if (!is_cancelled_ && hasAudio && !audioComplete) {
        while (!audioComplete) {
            if (is_cancelled_) break;

            DWORD streamIndex = 0;
            DWORD flags = 0;
            LONGLONG timestamp = 0;
            IMFSample *sample = nullptr;

            hr = reader->ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0,
                                     &streamIndex, &flags, &timestamp, &sample);
            if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) {
                audioComplete = true;
                if (sample) sample->Release();
                continue;
            }
            if (sample) {
                sample->SetSampleTime(timestamp);
                writer->WriteSample(audioStreamIndex, sample);
                sample->Release();
            }
        }
    }

    writer->Finalize();
    writer->Release();
    reader->Release();

    if (onProgress) onProgress(1.0);

    auto endTime = std::chrono::steady_clock::now();
    int compressionTime = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count());

    // Get compressed size
    int64_t compressedSize = 0;
    if (!is_cancelled_) {
        WIN32_FILE_ATTRIBUTE_DATA fileInfo;
        if (GetFileAttributesExW(wOutputPath.c_str(), GetFileExInfoStandard, &fileInfo)) {
            LARGE_INTEGER li;
            li.HighPart = fileInfo.nFileSizeHigh;
            li.LowPart = fileInfo.nFileSizeLow;
            compressedSize = li.QuadPart;
        }
    }

    MFShutdown();
    CoUninitialize();

    flutter::EncodableMap resultMap;
    resultMap[flutter::EncodableValue("outputPath")] =
        flutter::EncodableValue(WideToUtf8(wOutputPath));
    resultMap[flutter::EncodableValue("originalSize")] =
        flutter::EncodableValue(static_cast<int>(originalSize));
    resultMap[flutter::EncodableValue("compressedSize")] =
        flutter::EncodableValue(static_cast<int>(compressedSize));
    resultMap[flutter::EncodableValue("duration")] =
        flutter::EncodableValue(durationMs);
    resultMap[flutter::EncodableValue("compressionTime")] =
        flutter::EncodableValue(compressionTime);
    resultMap[flutter::EncodableValue("width")] =
        flutter::EncodableValue(targetWidth);
    resultMap[flutter::EncodableValue("height")] =
        flutter::EncodableValue(targetHeight);
    resultMap[flutter::EncodableValue("status")] =
        flutter::EncodableValue(is_cancelled_ ? "cancelled" : "success");

    return flutter::EncodableValue(resultMap);
}

}  // namespace easy_compressor
