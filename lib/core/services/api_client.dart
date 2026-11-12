import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'auth_session_manager.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Authenticated HTTP client for all ZEV backend API calls (`/api/v1/*`).
/// Automatically injects the active Supabase JWT, performs singleflight 401
/// refresh-and-retry, and provides direct binary presigned PUT uploads.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(minutes: 2),
      headers: const {'Accept': 'application/json'},
    ),
  );

  final Dio _rawUploadDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 3),
      sendTimeout: const Duration(minutes: 5),
    ),
  );

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    bool requireAuth = true,
    bool attachOptionalAuth = false,
  }) async {
    return _request(
      method: 'POST',
      path: path,
      data: data,
      requireAuth: requireAuth,
      attachOptionalAuth: attachOptionalAuth,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? data,
    bool requireAuth = true,
    bool attachOptionalAuth = false,
  }) async {
    return _request(
      method: 'PATCH',
      path: path,
      data: data,
      requireAuth: requireAuth,
      attachOptionalAuth: attachOptionalAuth,
    );
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool requireAuth = true,
    bool attachOptionalAuth = false,
  }) async {
    return _request(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      requireAuth: requireAuth,
      attachOptionalAuth: attachOptionalAuth,
    );
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? data,
    bool requireAuth = true,
    bool attachOptionalAuth = false,
  }) async {
    return _request(
      method: 'DELETE',
      path: path,
      data: data,
      requireAuth: requireAuth,
      attachOptionalAuth: attachOptionalAuth,
    );
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    required bool requireAuth,
    bool attachOptionalAuth = false,
  }) async {
    String? token;
    if (requireAuth) {
      final session = await AuthSessionManager.instance.ensureValidSession();
      token = session?.accessToken;
      if (token == null || token.isEmpty) {
        throw ApiException('Authentication required.', statusCode: 401);
      }
    } else if (attachOptionalAuth) {
      try {
        final session = await AuthSessionManager.instance.ensureValidSession();
        token = session?.accessToken;
      } catch (_) {
        token = null;
      }
    }

    try {
      return await _executeOnce(
        method: method,
        path: path,
        data: data,
        queryParameters: queryParameters,
        bearerToken: token,
      );
    } on ApiException catch (e) {
      if (requireAuth && e.statusCode == 401) {
        final refreshed = await AuthSessionManager.instance.ensureValidSession(
          forceRefresh: true,
        );
        final freshToken = refreshed?.accessToken;
        if (freshToken != null && freshToken.isNotEmpty) {
          return _executeOnce(
            method: method,
            path: path,
            data: data,
            queryParameters: queryParameters,
            bearerToken: freshToken,
          );
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _executeOnce({
    required String method,
    required String path,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    String? bearerToken,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {
            'Content-Type': 'application/json',
            if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
          },
          validateStatus: (code) => code != null && code < 500,
        ),
      );

      final status = response.statusCode ?? 500;
      final body = response.data;
      final Map<String, dynamic> map = body is Map<String, dynamic>
          ? body
          : body is Map
              ? Map<String, dynamic>.from(body)
              : <String, dynamic>{};

      if (status >= 200 && status < 300) {
        return map;
      }

      final errorMsg =
          map['error']?.toString() ??
          map['message']?.toString() ??
          'Request failed with status $status';
      throw ApiException(errorMsg, statusCode: status);
    } on DioException catch (e) {
      final resData = e.response?.data;
      String msg = e.message ?? 'Network error';
      if (resData is Map && resData['error'] != null) {
        msg = resData['error'].toString();
      }
      throw ApiException(msg, statusCode: e.response?.statusCode);
    }
  }

  /// Uploads bytes directly to a presigned R2 URL using exact signed headers.
  Future<void> uploadToPresignedUrl({
    required String uploadUrl,
    required Uint8List bytes,
    required Map<String, String> headers,
    void Function(double progress)? onProgress,
  }) async {
    final requestHeaders = <String, dynamic>{
      ...headers,
      'Content-Length': bytes.length,
    };

    final response = await _rawUploadDio.put<dynamic>(
      uploadUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: requestHeaders,
        validateStatus: (code) => code != null && code < 500,
      ),
      onSendProgress: (sent, total) {
        if (onProgress == null) return;
        final denom = total > 0 ? total : bytes.length;
        if (denom > 0) {
          onProgress((sent / denom).clamp(0.0, 1.0));
        }
      },
    );

    final status = response.statusCode ?? 500;
    if (status < 200 || status >= 300) {
      throw ApiException(
        'Direct storage upload failed (HTTP $status).',
        statusCode: status,
      );
    }
  }
}

