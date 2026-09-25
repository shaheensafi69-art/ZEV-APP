import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
export 'package:image_picker/image_picker.dart' show ImageSource;

/// Robust media and file picker for Android and iOS
/// Strictly complies with Google Play Photo & Video Permissions Policy:
/// - Gallery media (Images, Videos, Files): Exclusively uses FilePicker / Storage Access Framework (SAF) with ZERO storage/gallery runtime permissions.
/// - Camera: Only requests Camera permission when source is ImageSource.camera.
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

  /// Save bytes to temporary file if path is not directly available
  Future<File?> _saveBytesToTempFile(Uint8List bytes, String fileName) async {
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
