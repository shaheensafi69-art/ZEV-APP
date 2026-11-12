import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../models/story_highlight_model.dart';

/// Production Story Highlight Service backed by `user_highlights` & `user_highlight_stories`.
class StoryHighlightService {
  static final StoryHighlightService _instance =
      StoryHighlightService._internal();
  factory StoryHighlightService() => _instance;
  StoryHighlightService._internal();

  final supabase = Supabase.instance.client;

  String _storageKey(String userId) => 'zev_user_highlights_v2_$userId';

  /// Load highlights from `user_highlights` + `user_highlight_stories` with offline cache fallback.
  Future<List<StoryHighlight>> loadHighlights(String userId) async {
    try {
      final res = await supabase
          .from('user_highlights')
          .select('id, user_id, title, cover_url, display_order, created_at')
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .order('created_at', ascending: false);

      final highlightRows = List<Map<String, dynamic>>.from(res as List);
      final highlightIds = highlightRows
          .map((h) => h['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final itemsByHighlight = <String, List<StoryHighlightItem>>{};
      if (highlightIds.isNotEmpty) {
        final storiesRes = await supabase
            .from('user_highlight_stories')
            .select(
              'id, highlight_id, story_id, media_url, media_type, caption, created_at',
            )
            .inFilter('highlight_id', highlightIds)
            .order('created_at', ascending: true);

        for (final row in (storiesRes as List)) {
          final m = Map<String, dynamic>.from(row as Map);
          final hId = m['highlight_id']?.toString() ?? '';
          if (hId.isEmpty) continue;
          (itemsByHighlight[hId] ??= []).add(StoryHighlightItem.fromJson(m));
        }
      }

      final list = highlightRows.map((row) {
        final id = row['id']?.toString() ?? '';
        return StoryHighlight(
          id: id,
          userId: row['user_id']?.toString() ?? userId,
          title: row['title']?.toString() ?? 'Highlight',
          coverUrl: row['cover_url']?.toString() ?? '',
          createdAt:
              DateTime.tryParse(row['created_at']?.toString() ?? '') ??
              DateTime.now(),
          items: itemsByHighlight[id] ?? const [],
        );
      }).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey(userId),
        StoryHighlight.encodeList(list),
      );
      return list;
    } catch (e) {
      debugPrint('Remote user_highlights query notice: $e');
    }

    // Offline cache fallback only on query failure
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId)) ?? '';
      if (raw.isNotEmpty) {
        return StoryHighlight.decodeList(raw);
      }
    } catch (e) {
      debugPrint('Local highlights read notice: $e');
    }

    return [];
  }

  /// Persists a StoryHighlight and its StoryHighlightItems to Postgres + local cache.
  Future<void> saveHighlight(String userId, StoryHighlight highlight) async {
    final safeHighlightId = isValidUuid(highlight.id)
        ? highlight.id
        : generateUuidV4();
    final safeHighlight = StoryHighlight(
      id: safeHighlightId,
      userId: userId,
      title: highlight.title,
      coverUrl: highlight.coverUrl,
      createdAt: highlight.createdAt,
      items: highlight.items.map((item) {
        return StoryHighlightItem(
          id: isValidUuid(item.id) ? item.id : generateUuidV4(),
          storyId: isValidUuid(item.storyId) ? item.storyId : null,
          mediaUrl: item.mediaUrl,
          mediaType: item.mediaType,
          caption: item.caption,
          createdAt: item.createdAt,
          bgGradientColors: item.bgGradientColors,
          thumbnailUrl: item.thumbnailUrl,
        );
      }).toList(),
    );

    await supabase.from('user_highlights').upsert({
      'id': safeHighlight.id,
      'user_id': userId,
      'title': safeHighlight.title,
      'cover_url': safeHighlight.coverUrl.isNotEmpty
          ? safeHighlight.coverUrl
          : null,
      'is_active': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    if (safeHighlight.items.isNotEmpty) {
      await supabase
          .from('user_highlight_stories')
          .delete()
          .eq('highlight_id', safeHighlight.id);

      final rows = safeHighlight.items.map((it) {
        final encodedCaption = StoryHighlightItem.encodeCaptionWithGradient(
          it.caption,
          it.bgGradientColors,
        );
        return {
          'id': it.id,
          'highlight_id': safeHighlight.id,
          'story_id': it.storyId,
          'media_url': it.mediaUrl.isNotEmpty ? it.mediaUrl : 'text://note',
          'media_type': it.mediaType,
          'caption': encodedCaption,
          'created_at': it.createdAt.toUtc().toIso8601String(),
        };
      }).toList();

      await supabase.from('user_highlight_stories').insert(rows);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId)) ?? '';
      final currentList = raw.isNotEmpty
          ? StoryHighlight.decodeList(raw)
          : <StoryHighlight>[];

      final index = currentList.indexWhere((h) => h.id == safeHighlight.id);
      if (index >= 0) {
        currentList[index] = safeHighlight;
      } else {
        currentList.insert(0, safeHighlight);
      }
      await prefs.setString(
        _storageKey(userId),
        StoryHighlight.encodeList(currentList),
      );
    } catch (e) {
      debugPrint('Save highlight local cache notice: $e');
    }
  }

  /// Deletes a highlight from Supabase (`user_highlights` cascades `user_highlight_stories`)
  /// and cleans up direct highlight media uploads.
  Future<void> deleteHighlight(String userId, String highlightId) async {
    final List<String> cleanupUrls = [];
    try {
      final storyRows = await supabase
          .from('user_highlight_stories')
          .select('media_url, story_id')
          .eq('highlight_id', highlightId);
      for (final row in (storyRows as List)) {
        final storyId = row['story_id']?.toString();
        final mediaUrl = row['media_url']?.toString() ?? '';
        // Only delete standalone highlight uploads, not original archived stories
        if ((storyId == null || storyId.isEmpty) &&
            mediaUrl.startsWith('http')) {
          cleanupUrls.add(mediaUrl);
        }
      }
    } catch (_) {}

    try {
      await supabase
          .from('user_highlights')
          .delete()
          .eq('id', highlightId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Remote user_highlights delete notice: $e');
    }

    if (cleanupUrls.isNotEmpty) {
      await CloudflareStorageService.instance.deleteUrls(cleanupUrls);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId)) ?? '';
      if (raw.isNotEmpty) {
        final currentList = StoryHighlight.decodeList(raw);
        currentList.removeWhere((h) => h.id == highlightId);
        await prefs.setString(
          _storageKey(userId),
          StoryHighlight.encodeList(currentList),
        );
      }
    } catch (e) {
      debugPrint('Delete highlight local notice: $e');
    }
  }

  /// Fetch all non-deleted historical stories published by this user from `user_stories`.
  Future<List<Map<String, dynamic>>> fetchUserStoriesArchive(
    String userId,
  ) async {
    try {
      final res = await supabase
          .from('user_stories')
          .select('id, media_url, media_type, caption, created_at, expires_at')
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(80);

      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('Fetch user stories archive notice: $e');
      return [];
    }
  }
}
