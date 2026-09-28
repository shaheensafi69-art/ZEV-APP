import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
export 'package:image_picker/image_picker.dart' show ImageSource;

/// Container for picked media compatible across Mobile and Web
class AppPickedMedia {
  final String name;
  final Uint8List bytes;
  final String? path;
  final File? file;
  final bool isVideo;
  final String mimeType;

  const AppPickedMedia({
    required this.name,
    required this.bytes,
    this.path,
    this.file,
    this.isVideo = false,
    required this.mimeType,
  });
}

/// Robust media and file picker for Android, iOS, Desktop and Web
class AppMediaPicker {
  AppMediaPicker._();
  static final AppMediaPicker instance = AppMediaPicker._();

  final ImagePicker _imagePicker = ImagePicker();

  /// Validate and request permissions only for camera hardware
  Future<void> _ensureCameraPermission() async {
    try {
      if (kIsWeb) return;
      final status = await Permission.camera.status;
      if (!status.isGranted && !status.isPermanentlyDenied) {
        await Permission.camera.request();
      }
    } catch (e) {
      debugPrint("Camera permission check note: $e");
    }
  }

  /// Infer MIME type from file extension
  static String inferMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'svg':
        return 'image/svg+xml';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case '3gp':
        return 'video/3gpp';
      default:
        return 'application/octet-stream';
    }
  }

  /// Universal media picker returning raw bytes and metadata, 100% compatible with Mobile and Web
  Future<AppPickedMedia?> pickUniversalMedia({
    bool allowImages = true,
    bool allowVideos = true,
    ImageSource source = ImageSource.gallery,
  }) async {
    if (source == ImageSource.camera && !kIsWeb) {
      if (allowImages) {
        await _ensureCameraPermission();
        try {
          final XFile? picked =
              await _imagePicker.pickImage(source: ImageSource.camera);
          if (picked != null) {
            final bytes = await picked.readAsBytes();
            return AppPickedMedia(
              name: picked.name,
              bytes: bytes,
              path: picked.path,
              file: File(picked.path),
              isVideo: false,
              mimeType: inferMime(picked.name),
            );
          }
        } catch (e) {
          debugPrint("Camera pick error: $e");
        }
      }
      return null;
    }

    try {
      List<String> extensions = [];
      if (allowImages) {
        extensions.addAll([
          'jpg',
          'jpeg',
          'png',
          'webp',
          'gif',
          'bmp',
          'heic',
          'heif',
          'svg'
        ]);
      }
      if (allowVideos) {
        extensions.addAll(['mp4', 'mov', 'webm', 'avi', 'mkv', '3gp']);
      }

      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pf = result.files.single;
        Uint8List? bytes = pf.bytes;
        File? file;
        if (!kIsWeb && pf.path != null && pf.path!.isNotEmpty) {
          file = File(pf.path!);
          if (bytes == null && await file.exists()) {
            bytes = await file.readAsBytes();
          }
        }
        if (bytes != null && bytes.isNotEmpty) {
          final isVid = [
            'mp4',
            'mov',
            'webm',
            'avi',
            'mkv',
            '3gp'
          ].contains(pf.extension?.toLowerCase());
          return AppPickedMedia(
            name: pf.name,
            bytes: bytes,
            path: pf.path,
            file: file,
            isVideo: isVid,
            mimeType: inferMime(pf.name),
          );
        }
      }
    } catch (e) {
      debugPrint("pickUniversalMedia error: $e");
    }
    return null;
  }

  /// Save bytes to temporary file if path is not directly available (native only)
  Future<File?> _saveBytesToTempFile(Uint8List bytes, String fileName) async {
    if (kIsWeb) return null;
    try {
      final tempDir = Directory.systemTemp;
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final file = File('${tempDir.path}/$uniqueName');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      debugPrint("Error writing temp bytes: $e");
      return null;
    }
  }

  /// Pick image (profile, feed posts, stories, etc.)
  /// When source is gallery: Uses FilePicker without requiring any storage/gallery permissions.
  Future<File?> pickImage({
    ImageSource source = ImageSource.gallery,
    int imageQuality = 85,
    double? maxWidth,
    double? maxHeight,
  }) async {
    // 1. Gallery selection: 100% via FilePicker (No permissions needed)
    if (source == ImageSource.gallery) {
      try {
        final FilePickerResult? result = await FilePicker.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final platformFile = result.files.single;
          if (platformFile.path != null && platformFile.path!.isNotEmpty) {
            final file = File(platformFile.path!);
            if (await file.exists()) return file;
          } else if (platformFile.bytes != null) {
            return await _saveBytesToTempFile(
              platformFile.bytes!,
              platformFile.name,
            );
          }
        }
      } catch (fpErr) {
        debugPrint("FilePicker pickImage notice: $fpErr");
      }

      // Fallback with explicit image extensions via FilePicker
      try {
        final FilePickerResult? customResult = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
          allowMultiple: false,
          withData: true,
        );
        if (customResult != null && customResult.files.isNotEmpty) {
          final platformFile = customResult.files.single;
          if (platformFile.path != null && platformFile.path!.isNotEmpty) {
            final file = File(platformFile.path!);
            if (await file.exists()) return file;
          } else if (platformFile.bytes != null) {
            return await _saveBytesToTempFile(
              platformFile.bytes!,
              platformFile.name,
            );
          }
        }
      } catch (_) {}

      return null;
    }

    // 2. Camera mode via ImagePicker
    if (source == ImageSource.camera) {
      await _ensureCameraPermission();
      try {
        final XFile? picked = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: imageQuality,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
        if (picked != null && picked.path.isNotEmpty) {
          final file = File(picked.path);
          if (await file.exists()) return file;
        }
      } catch (e) {
        debugPrint("ImagePicker camera notice: $e");
      }
    }

    return null;
  }

  /// Pick video (Reels, story video, etc.)
  /// When source is gallery: Uses FilePicker without requiring any storage/gallery permissions.
  Future<File?> pickVideo({
    ImageSource source = ImageSource.gallery,
  }) async {
    // 1. Gallery selection: 100% via FilePicker (No permissions needed)
    if (source == ImageSource.gallery) {
      try {
        final FilePickerResult? result = await FilePicker.pickFiles(
          type: FileType.video,
          allowMultiple: false,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final platformFile = result.files.single;
          if (platformFile.path != null && platformFile.path!.isNotEmpty) {
            final file = File(platformFile.path!);
            if (await file.exists()) return file;
          } else if (platformFile.bytes != null) {
            return await _saveBytesToTempFile(
              platformFile.bytes!,
              platformFile.name,
            );
          }
        }
      } catch (fpErr) {
        debugPrint("FilePicker video notice: $fpErr");
      }

      // Fallback with explicit video extensions via FilePicker
      try {
        final FilePickerResult? customResult = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'],
          allowMultiple: false,
          withData: true,
        );
        if (customResult != null && customResult.files.isNotEmpty) {
          final platformFile = customResult.files.single;
          if (platformFile.path != null && platformFile.path!.isNotEmpty) {
            final file = File(platformFile.path!);
            if (await file.exists()) return file;
          } else if (platformFile.bytes != null) {
            return await _saveBytesToTempFile(
              platformFile.bytes!,
              platformFile.name,
            );
          }
        }
      } catch (_) {}

      return null;
    }

    // 2. Camera recording mode
    if (source == ImageSource.camera) {
      await _ensureCameraPermission();
      try {
        final XFile? picked = await _imagePicker.pickVideo(source: ImageSource.camera);
        if (picked != null && picked.path.isNotEmpty) {
          final file = File(picked.path);
          if (await file.exists()) return file;
        }
      } catch (e) {
        debugPrint("ImagePicker camera recording notice: $e");
      }
    }

    return null;
  }

  /// Pick documents, PDFs, certificates (100% via FilePicker)
  Future<File?> pickDocumentOrMedia({
    List<String> allowedExtensions = const [
      'pdf',
      'jpg',
      'jpeg',
      'png',
      'webp',
      'doc',
      'docx',
      'zip',
      'rar',
    ],
  }) async {
    String? finalPath;

    // 1. First attempt with FileType.any
    try {
      final FilePickerResult? anyResult = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (anyResult != null && anyResult.files.isNotEmpty) {
        final platformFile = anyResult.files.single;
        if (platformFile.path != null && platformFile.path!.isNotEmpty) {
          finalPath = platformFile.path;
        } else if (platformFile.bytes != null) {
          return await _saveBytesToTempFile(
            platformFile.bytes!,
            platformFile.name,
          );
        }
      }
    } catch (anyErr) {
      debugPrint("FilePicker any notice: $anyErr");
    }

    // 2. Second attempt with custom extensions
    if (finalPath == null) {
      try {
        final FilePickerResult? customResult =
            await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: allowedExtensions,
          allowMultiple: false,
          withData: true,
        );
        if (customResult != null && customResult.files.isNotEmpty) {
          final platformFile = customResult.files.single;
          if (platformFile.path != null && platformFile.path!.isNotEmpty) {
            finalPath = platformFile.path;
          } else if (platformFile.bytes != null) {
            return await _saveBytesToTempFile(
              platformFile.bytes!,
              platformFile.name,
            );
          }
        }
      } catch (customErr) {
        debugPrint("FilePicker custom notice: $customErr");
      }
    }

    if (finalPath != null && finalPath.isNotEmpty) {
      final file = File(finalPath);
      if (await file.exists()) {
        return file;
      }
    }
    return null;
  }
}
