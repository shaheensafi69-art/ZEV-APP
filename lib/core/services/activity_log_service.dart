import 'dart:convert';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActivityLogEntry {
  final String id;
  final String deviceModel;
  final String osName;
  final String location;
  final String ipAddress;
  final DateTime timestamp;
  final bool isCurrent;

  ActivityLogEntry({
    required this.id,
    required this.deviceModel,
    required this.osName,
    required this.location,
    required this.ipAddress,
    required this.timestamp,
    this.isCurrent = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'device_model': deviceModel,
    'os_name': osName,
    'location': location,
    'ip_address': ipAddress,
    'timestamp': timestamp.toIso8601String(),
    'is_current': isCurrent,
  };

  factory ActivityLogEntry.fromJson(
    Map<String, dynamic> json, {
    bool isCurrent = false,
  }) {
    return ActivityLogEntry(
      id: json['id']?.toString() ?? '',
      deviceModel: json['device_model']?.toString() ?? 'Mobile Device',
      osName: json['os_name']?.toString() ?? '',
      location: json['location']?.toString() ?? 'Unknown Location',
      ipAddress: json['ip_address']?.toString() ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      isCurrent: isCurrent,
    );
  }
}

class ActivityLogService {
  static final ActivityLogService _instance = ActivityLogService._internal();
  factory ActivityLogService() => _instance;
  ActivityLogService._internal();

  static ActivityLogService get instance => _instance;

  final supabase = Supabase.instance.client;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _currentSessionId;

  String get currentSessionId {
    _currentSessionId ??= DateTime.now().millisecondsSinceEpoch.toString();
    return _currentSessionId!;
  }

  /// Get device model name
  Future<Map<String, String>> getDeviceDetails() async {
    String deviceModel = "Smartphone";
    String osName = "Mobile";

    try {
      if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        deviceModel = webInfo.browserName.name.toUpperCase();
        osName = webInfo.platform ?? "Web";
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        final brand = androidInfo.brand.toUpperCase();
        final model = androidInfo.model;
        deviceModel = "$brand $model";
        osName = "Android ${androidInfo.version.release}";
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceModel = iosInfo.name;
        osName = "iOS ${iosInfo.systemVersion}";
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        deviceModel = macInfo.model;
        osName = "macOS ${macInfo.osRelease}";
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        deviceModel = "Windows PC";
        osName = "Windows";
      }
    } catch (e) {
      debugPrint("Error detecting device info: $e");
    }

    return {"model": deviceModel, "os": osName};
  }

  /// Get precise IP location with fallback layer
  Future<Map<String, String>> getApproximateLocation() async {
    String location = "Online";
    String country = "Unknown";
    String city = "Unknown";
    String ip = "—";

    // 1. Primary fast IP lookup service (ipwho.is)
    try {
      final res = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          city = data['city']?.toString() ?? "";
          country = data['country']?.toString() ?? "";
          ip = data['ip']?.toString() ?? "—";
          final emoji = data['flag']?['emoji']?.toString() ?? "";

          if (city.isNotEmpty && country.isNotEmpty) {
            location = "$emoji $city, $country".trim();
          } else if (country.isNotEmpty) {
            location = "$emoji $country".trim();
          }
          if (country.isNotEmpty) {
            return {"location": location, "country": country, "city": city, "ip": ip};
          }
        }
      }
    } catch (e) {
      debugPrint("ipwho.is error: $e");
    }

    // 2. Secondary fallback service (ip-api.com)
    try {
      final res2 = await http
          .get(Uri.parse('http://ip-api.com/json'))
          .timeout(const Duration(seconds: 3));

      if (res2.statusCode == 200) {
        final data = jsonDecode(res2.body);
        if (data['status'] == 'success') {
          city = data['city']?.toString() ?? "";
          country = data['country']?.toString() ?? "";
          ip = data['query']?.toString() ?? "—";

          if (city.isNotEmpty && country.isNotEmpty) {
            location = "$city, $country";
          } else if (country.isNotEmpty) {
            location = country;
          }
          if (country.isNotEmpty) {
            return {"location": location, "country": country, "city": city, "ip": ip};
          }
        }
      }
    } catch (e) {
      debugPrint("ip-api.com fallback error: $e");
    }

    // 3. Minimal IP fallback
    try {
      final res3 = await http
          .get(Uri.parse('https://api.ipify.org?format=json'))
          .timeout(const Duration(seconds: 2));
      if (res3.statusCode == 200) {
        final data = jsonDecode(res3.body);
        ip = data['ip']?.toString() ?? ip;
      }
    } catch (_) {}

    return {"location": location, "country": country, "city": city, "ip": ip};
  }

  /// Record login in device_activities and local cache
  Future<void> recordLogin(String userId, {bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRecordedKey = "last_recorded_activity_$userId";
      final lastTime = prefs.getInt(lastRecordedKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Debounce if logged in within 3 minutes unless forced
      if (!force && (now - lastTime < 3 * 60 * 1000)) {
        debugPrint("Activity already recorded recently for $userId, skipping.");
        return;
      }

      final device = await getDeviceDetails();
      final loc = await getApproximateLocation();
      final sessionId = currentSessionId;

      final newEntry = ActivityLogEntry(
        id: sessionId,
        deviceModel: device["model"] ?? "Mobile Device",
        osName: device["os"] ?? "OS",
        location: loc["location"] ?? "Online",
        ipAddress: loc["ip"] ?? "—",
        timestamp: DateTime.now(),
        isCurrent: true,
      );

      // 1. Update or append device entry in local SharedPreferences
      final key = "activity_logs_$userId";
      final rawList = prefs.getStringList(key) ?? [];

      List<Map<String, dynamic>> list = rawList
          .map((item) {
            try {
              return jsonDecode(item) as Map<String, dynamic>;
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .where((m) => m['device_model'] != newEntry.deviceModel) // Remove prior record for this device
          .toList();

      list.insert(0, newEntry.toJson());
      if (list.length > 20) {
        list = list.sublist(0, 20); // Keep last 20 logs
      }

      await prefs.setStringList(key, list.map((m) => jsonEncode(m)).toList());
      await prefs.setInt(lastRecordedKey, now);

      // 2. Save or update record in device_activities table
      try {
        final existing = await supabase
            .from('device_activities')
            .select('id')
            .eq('student_id', userId)
            .eq('device_name', newEntry.deviceModel)
            .maybeSingle();

        if (existing != null && existing['id'] != null) {
          final existingId = existing['id'].toString();
          await supabase.from('device_activities').update({
            'country': loc['country'] ?? 'Unknown',
            'city': loc['city'] ?? 'Unknown',
            'ip_address': loc['ip'] ?? '—',
            'logged_in_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', existingId);
          debugPrint("Updated login timestamp for existing device: ${newEntry.deviceModel}");
        } else {
          final insertData = {
            'id': _generateUuidV4(),
            'student_id': userId,
            'device_name': newEntry.deviceModel,
            'country': loc['country'] ?? 'Unknown',
            'city': loc['city'] ?? 'Unknown',
            'ip_address': loc['ip'] ?? '—',
            'logged_in_at': DateTime.now().toUtc().toIso8601String(),
          };
          await supabase.from('device_activities').insert(insertData);
          debugPrint("Inserted new device record: ${newEntry.deviceModel}");
        }
      } catch (e) {
        debugPrint("Error syncing device_activities in Supabase: $e");
      }
    } catch (e) {
      debugPrint("Failed to record activity log: $e");
    }
  }

  /// Delete session (remote device logout)
  Future<bool> removeSession(String userId, String logId) async {
    try {
      await supabase
          .from('device_activities')
          .delete()
          .eq('id', logId)
          .eq('student_id', userId);
    } catch (e) {
      debugPrint("Error deleting remote device_activity: $e");
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = "activity_logs_$userId";
      final rawList = prefs.getStringList(key) ?? [];
      final list = rawList
          .map((item) {
            try {
              return jsonDecode(item) as Map<String, dynamic>;
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .where((m) => m['id']?.toString() != logId)
          .toList();
      await prefs.setStringList(key, list.map((m) => jsonEncode(m)).toList());
      return true;
    } catch (e) {
      debugPrint("Error removing local activity log: $e");
      return false;
    }
  }

  /// Fetch user login activity (sync from device_activities)
  Future<List<ActivityLogEntry>> getLogs(String userId) async {
    final List<ActivityLogEntry> logs = [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = "activity_logs_$userId";

      // Fetch from primary database table device_activities
      try {
        final List<dynamic> dbRows = await supabase
            .from('device_activities')
            .select('*')
            .eq('student_id', userId)
            .order('logged_in_at', ascending: false)
            .limit(20);

        if (dbRows.isNotEmpty) {
          for (var i = 0; i < dbRows.length; i++) {
            final row = dbRows[i] as Map<String, dynamic>;
            final country = row['country']?.toString() ?? '';
            final city = row['city']?.toString() ?? '';
            String loc = "$city, $country".replaceAll(
              RegExp(r'^,\s*|,\s*$'),
              '',
            );
            if (loc.isEmpty) loc = "Online Session";

            final entry = ActivityLogEntry(
              id: row['id']?.toString() ?? i.toString(),
              deviceModel: row['device_name']?.toString() ?? 'Mobile Device',
              osName: 'Mobile',
              location: loc,
              ipAddress: row['ip_address']?.toString() ?? '—',
              timestamp:
                  DateTime.tryParse(row['logged_in_at']?.toString() ?? '') ??
                  DateTime.now(),
              isCurrent: (i == 0),
            );
            logs.add(entry);
          }

          // Save to local cache
          await prefs.setStringList(
            key,
            logs.map((e) => jsonEncode(e.toJson())).toList(),
          );
          return logs;
        } else {
          // If no record exists, record current session immediately
          await recordLogin(userId, force: true);
          final List<dynamic> retryRows = await supabase
              .from('device_activities')
              .select('*')
              .eq('student_id', userId)
              .order('logged_in_at', ascending: false)
              .limit(20);

          if (retryRows.isNotEmpty) {
            for (var i = 0; i < retryRows.length; i++) {
              final row = retryRows[i] as Map<String, dynamic>;
              final country = row['country']?.toString() ?? '';
              final city = row['city']?.toString() ?? '';
              String loc = "$city, $country".replaceAll(RegExp(r'^,\s*|,\s*$'), '');
              if (loc.isEmpty) loc = "Online Session";

              logs.add(ActivityLogEntry(
                id: row['id']?.toString() ?? i.toString(),
                deviceModel: row['device_name']?.toString() ?? 'Mobile Device',
                osName: 'Mobile',
                location: loc,
                ipAddress: row['ip_address']?.toString() ?? '—',
                timestamp: DateTime.tryParse(row['logged_in_at']?.toString() ?? '') ?? DateTime.now(),
                isCurrent: (i == 0),
              ));
            }
            await prefs.setStringList(
              key,
              logs.map((e) => jsonEncode(e.toJson())).toList(),
            );
            return logs;
          }
        }
      } catch (e) {
        debugPrint(
          "Could not fetch remote device_activities, falling back to local: $e",
        );
      }

      // Fallback to local cache if offline
      final rawList = prefs.getStringList(key) ?? [];
      for (var item in rawList) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          final isCurr = map['id'] == _currentSessionId;
          logs.add(ActivityLogEntry.fromJson(map, isCurrent: isCurr));
        } catch (_) {}
      }

      // Create current session log if none exists
      if (logs.isEmpty) {
        final device = await getDeviceDetails();
        final loc = await getApproximateLocation();
        final currentEntry = ActivityLogEntry(
          id: currentSessionId,
          deviceModel: device["model"] ?? "Mobile Device",
          osName: device["os"] ?? "OS",
          location: loc["location"] ?? "Online",
          ipAddress: loc["ip"] ?? "—",
          timestamp: DateTime.now(),
          isCurrent: true,
        );
        logs.add(currentEntry);
        await prefs.setStringList(key, [jsonEncode(currentEntry.toJson())]);
      }
    } catch (e) {
      debugPrint("Error fetching activity logs: $e");
    }

    return logs;
  }

  /// Clear login activity history
  Future<void> clearLogs(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = "activity_logs_$userId";
      final logs = await getLogs(userId);
      final currentOnly = logs.where((l) => l.isCurrent).toList();
      await prefs.setStringList(
        key,
        currentOnly.map((e) => jsonEncode(e.toJson())).toList(),
      );

      // Clear records from database
      try {
        await supabase
            .from('device_activities')
            .delete()
            .eq('student_id', userId);
      } catch (_) {}
    } catch (_) {}
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    // Set version to 4
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122
    values[8] = (values[8] & 0x3f) | 0x80;

    final hexDigits = values.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${hexDigits.sublist(0, 4).join()}-${hexDigits.sublist(4, 6).join()}-${hexDigits.sublist(6, 8).join()}-${hexDigits.sublist(8, 10).join()}-${hexDigits.sublist(10, 16).join()}';
  }
}

