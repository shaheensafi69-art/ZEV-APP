import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/story_highlight_model.dart';

/// Real, Production Story Highlight Service for ZEV.
/// Reads from Supabase tables (story_highlights & user_stories) with zero demo/mock data.
class StoryHighlightService {
  static final StoryHighlightService _instance = StoryHighlightService._internal();
  factory StoryHighlightService() => _instance;
  StoryHighlightService._internal();

  final supabase = Supabase.instance.client;

  String _storageKey(String userId) => 'zev_user_highlights_$userId';

  /// Load authentic highlights for a user directly from Supabase & cached local storage.
  /// ZERO mock or demo data.
  Future<List<StoryHighlight>> loadHighlights(String userId) async {
    List<StoryHighlight> result = [];

    // 1. Attempt to fetch from Supabase story_highlights table
    try {
      final res = await supabase
          .from('story_highlights')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final list = (res as List)
          .map((row) => StoryHighlight.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      if (list.isNotEmpty) {
        // Cache to local
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey(userId), StoryHighlight.encodeList(list));
        return list;
      }
    } catch (e) {
      debugPrint("Remote story_highlights query notice: $e");
    }

    // 2. Fallback to cached local storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId)) ?? '';
      if (raw.isNotEmpty) {
        result = StoryHighlight.decodeList(raw);
      }
    } catch (e) {
      debugPrint("Local highlights read notice: $e");
    }

    // Return real list only (empty if user has not created any highlights)
    return result;
  }

  /// Save or add a new highlight to Supabase & local storage
  Future<void> saveHighlight(String userId, StoryHighlight highlight) async {
    // 1. Try to persist to Supabase
    try {
      await supabase.from('story_highlights').upsert({
        'id': highlight.id,
        'user_id': userId,
        'title': highlight.title,
        'cover_url': highlight.coverUrl,
        'created_at': highlight.createdAt.toIso8601String(),
        'items': highlight.items.map((i) => i.toJson()).toList(),
      });
    } catch (e) {
      debugPrint("Remote story_highlights upsert notice: $e");
    }

    // 2. Persist to local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId)) ?? '';
      final currentList = raw.isNotEmpty ? StoryHighlight.decodeList(raw) : <StoryHighlight>[];

      final index = currentList.indexWhere((h) => h.id == highlight.id);
      if (index >= 0) {
        currentList[index] = highlight;
      } else {
        currentList.insert(0, highlight);
      }

      await prefs.setString(_storageKey(userId), StoryHighlight.encodeList(currentList));
    } catch (e) {
      debugPrint("Save highlight local error: $e");
    }
  }

  /// Delete a highlight from Supabase & local storage
  Future<void> deleteHighlight(String userId, String highlightId) async {
    // 1. Delete from Supabase
    try {
      await supabase.from('story_highlights').delete().eq('id', highlightId);
    } catch (e) {
      debugPrint("Remote story_highlights delete notice: $e");
    }

    // 2. Delete from local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId)) ?? '';
      if (raw.isNotEmpty) {
        final currentList = StoryHighlight.decodeList(raw);
        currentList.removeWhere((h) => h.id == highlightId);
        await prefs.setString(_storageKey(userId), StoryHighlight.encodeList(currentList));
      }
    } catch (e) {
      debugPrint("Delete highlight local error: $e");
    }
  }

  /// Fetch all historical stories published by this user from Supabase user_stories
  Future<List<Map<String, dynamic>>> fetchUserStoriesArchive(String userId) async {
    try {
      final res = await supabase
          .from('user_stories')
          .select('id, media_url, media_type, caption, created_at, expires_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(80);

      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint("Fetch user stories archive notice: $e");
      return [];
    }
  }
}
