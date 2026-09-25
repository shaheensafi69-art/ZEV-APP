import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentContext {
  final String studentName;
  final List<String> enrolledCourses;
  final List<String> enrolledClassGroups;
  final List<String> availableAcademyCourses;
  final List<String> availableTeachers;

  StudentContext({
    required this.studentName,
    required this.enrolledCourses,
    required this.enrolledClassGroups,
    required this.availableAcademyCourses,
    required this.availableTeachers,
  });
}

class GeminiAiService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _apiKey {
    final key =
        dotenv.env['GOOGLE_GEMINI_API_KEY'] ??
        dotenv.env['GEMINI_API_KEY'] ??
        '';
    return key.trim();
  }

  /// Fetch user context and platform catalog from database
  Future<StudentContext> fetchStudentContext(String studentId) async {
    String studentName = "User";
    List<String> enrolledCourses = [];
    List<String> enrolledClassGroups = [];
    List<String> availableAcademyCourses = [];
    List<String> availableTeachers = [];

    try {
      // 1. Fetch user name from profiles
      final profile = await _supabase
          .from("profiles")
          .select("first_name, last_name")
          .eq("id", studentId)
          .maybeSingle();

      if (profile != null) {
        final fName = profile['first_name'] ?? '';
        final lName = profile['last_name'] ?? '';
        studentName = "$fName $lName".trim();
        if (studentName.isEmpty) studentName = "User";
      }

      // 2. Fetch enrolled courses
      final enrollments = await _supabase
          .from("enrollments")
          .select("courses(title, category)")
          .eq("student_id", studentId);

      for (var item in (enrollments as List)) {
        if (item['courses'] != null && item['courses']['title'] != null) {
          enrolledCourses.add(item['courses']['title'].toString());
        }
      }

      // 3. Fetch enrolled live classes
      final classStudents = await _supabase
          .from("class_students")
          .select("class_groups(class_name, schedule_info)")
          .eq("student_id", studentId);

      for (var item in (classStudents as List)) {
        if (item['class_groups'] != null &&
            item['class_groups']['class_name'] != null) {
          enrolledClassGroups.add(
            item['class_groups']['class_name'].toString(),
          );
        }
      }

      // 4. Fetch general platform catalog
      final allCourses = await _supabase
          .from("courses")
          .select("title, category, instructor_name, price")
          .limit(20);

      for (var c in (allCourses as List)) {
        final title = c['title'] ?? '';
        final instructor = c['instructor_name'] ?? '';
        if (title.isNotEmpty) {
          availableAcademyCourses.add(
            "$title ${instructor.isNotEmpty ? "(Mentor: $instructor)" : ""}",
          );
        }
      }

      // 5. Fetch mentors list
      final teachers = await _supabase
          .from("teacher_info")
          .select("first_name, last_name, bio")
          .limit(10);

      for (var t in (teachers as List)) {
        final name = "${t['first_name'] ?? ''} ${t['last_name'] ?? ''}".trim();
        if (name.isNotEmpty) availableTeachers.add(name);
      }
    } catch (e) {
      debugPrint("GeminiAiService: Error fetching student context: $e");
    }

    return StudentContext(
      studentName: studentName,
      enrolledCourses: enrolledCourses,
      enrolledClassGroups: enrolledClassGroups,
      availableAcademyCourses: availableAcademyCourses,
      availableTeachers: availableTeachers,
    );
  }

  /// Build rich, intelligent system prompt
  String _buildSystemPrompt(StudentContext ctx) {
    final enrolledCoursesStr = ctx.enrolledCourses.isNotEmpty
        ? ctx.enrolledCourses.join(", ")
        : "None";

    final enrolledClassesStr = ctx.enrolledClassGroups.isNotEmpty
        ? ctx.enrolledClassGroups.join(", ")
        : "None";

    final availableCoursesStr = ctx.availableAcademyCourses.isNotEmpty
        ? ctx.availableAcademyCourses.map((c) => "- $c").join("\n")
        : "Active catalog";

    final availableTeachersStr = ctx.availableTeachers.isNotEmpty
        ? ctx.availableTeachers.join(", ")
        : "ZEV Team";

    return '''
You are ZEV AI, the official intelligent assistant for ZEV Social Network (zevapp.com).
Always be friendly, creative, professional, and inspiring. Guide users with captions, reel ideas, networking, and creative content creation.

User Name: ${ctx.studentName}

Guidelines:
1. Your tone is warm, supportive, inspiring, and professional.
2. Help users brainstorm reel concepts, engaging captions, trending hashtags, and creative ideas.
3. Always respond in the exact language the user used to speak with you.
''';
  }

  /// Send request to AI and receive response
  Future<String> generateResponse({
    required String studentId,
    required String userPrompt,
    List<Map<String, String>> conversationHistory = const [],
  }) async {
    final key = _apiKey;
    if (key.isEmpty) {
      return "⚠️ Gemini API key not found. Please check your .env configuration.";
    }

    // 1. Extract context from database
    final context = await fetchStudentContext(studentId);
    final systemPrompt = _buildSystemPrompt(context);

    // 2. Build content prompt for Gemini API
    final List<Map<String, dynamic>> contents = [];

    // Append recent conversation history
    for (var msg in conversationHistory) {
      contents.add({
        "role": msg['role'] == 'user' ? 'user' : 'model',
        "parts": [
          {"text": msg['content']},
        ],
      });
    }

    // Current user prompt
    contents.add({
      "role": "user",
      "parts": [
        {"text": userPrompt},
      ],
    });

    final requestBody = jsonEncode({
      "systemInstruction": {
        "parts": [
          {"text": systemPrompt},
        ],
      },
      "contents": contents,
      "generationConfig": {"temperature": 0.7, "maxOutputTokens": 1500},
    });

    // 3. Call Gemini API endpoints
    final endpoints = [
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$key",
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=$key",
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=$key",
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$key",
    ];

    String aiText = "";
    List<String> errorDetails = [];

    for (var endpoint in endpoints) {
      try {
        final response = await http
            .post(
              Uri.parse(endpoint),
              headers: {"Content-Type": "application/json"},
              body: requestBody,
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              aiText = parts[0]['text'] ?? "";
              if (aiText.isNotEmpty) break;
            }
          }
        } else {
          final errBody = response.body;
          final modelName = Uri.parse(
            endpoint,
          ).pathSegments.reversed.skip(1).first;
          errorDetails.add("$modelName: HTTP ${response.statusCode}");
          debugPrint(
            "Gemini Endpoint ($endpoint) Error Status: ${response.statusCode} Body: $errBody",
          );
        }
      } catch (e) {
        errorDetails.add("Exception: $e");
        debugPrint("Gemini Endpoint Call Exception: $e");
      }
    }

    if (aiText.isEmpty) {
      aiText = "Service is currently unavailable. Please try again later.";
    }

    return aiText;
  }

  /// Text-to-speech generation using Gemini TTS
  /// TTS generation using dedicated models or interactions API
  Future<String?> generateSpeech(String text, {String voice = 'Kore'}) async {
    final key = _apiKey;
    if (key.isEmpty) {
      debugPrint("Gemini TTS Error: API key is empty.");
      return null;
    }

    // Strip markdown formatting for smooth speech synthesis
    final cleanText = text
        .replaceAll(RegExp(r'\*\*?'), '') // Remove asterisks
        .replaceAll(RegExp(r'#+'), '') // Remove header hashes
        .replaceAll(RegExp(r'`'), '') // Remove backticks
        .replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '') // Remove links
        .trim();

    if (cleanText.isEmpty) return null;

    // 1. Primary method: Direct call to gemini-3.1-flash-tts-preview
    final generateContentUrl =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-tts-preview:generateContent?key=$key";
    try {
      final response = await http
          .post(
            Uri.parse(generateContentUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {"text": cleanText},
                  ],
                },
              ],
              "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {
                  "voiceConfig": {
                    "prebuiltVoiceConfig": {"voiceName": voice},
                  },
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final inlineData = parts[0]['inlineData'];
            if (inlineData != null && inlineData['data'] != null) {
              return inlineData['data'].toString();
            }
          }
        }
      }
      debugPrint(
        "TTS Model API returned HTTP ${response.statusCode}: ${response.body}",
      );
    } catch (e) {
      debugPrint("TTS Model generateContent Call Exception: $e");
    }

    // 2. Fallback method: Call interactions endpoint
    final interactionsUrl =
        "https://generativelanguage.googleapis.com/v1beta/interactions?key=$key";
    try {
      final response = await http
          .post(
            Uri.parse(interactionsUrl),
            headers: {
              "Content-Type": "application/json",
              "Api-Revision": "2026-05-20",
            },
            body: jsonEncode({
              "model": "gemini-3.1-flash-tts-preview",
              "input": cleanText,
              "response_format": {"type": "audio"},
              "generation_config": {
                "speech_config": [
                  {"voice": voice},
                ],
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['interaction'] != null &&
            data['interaction']['output_audio'] != null) {
          return data['interaction']['output_audio'].toString();
        } else if (data['outputAudio'] != null) {
          return data['outputAudio'].toString();
        } else if (data['audioContent'] != null) {
          return data['audioContent'].toString();
        }
      }
      debugPrint(
        "TTS Interactions API returned HTTP ${response.statusCode}: ${response.body}",
      );
    } catch (e) {
      debugPrint("TTS Interactions API Call Exception: $e");
    }

    // 3. Final fallback: gemini-2.5-flash-preview-tts
    final backupTtsUrl =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$key";
    try {
      final response = await http
          .post(
            Uri.parse(backupTtsUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {"text": cleanText},
                  ],
                },
              ],
              "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {
                  "voiceConfig": {
                    "prebuiltVoiceConfig": {"voiceName": voice},
                  },
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final inlineData = parts[0]['inlineData'];
            if (inlineData != null && inlineData['data'] != null) {
              return inlineData['data'].toString();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Backup TTS Model generateContent Exception: $e");
    }

    return null;
  }
}
