import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HashtagItem {
  final String id;
  final String tag;
  final int postsCount;
  final int reelsCount;

  const HashtagItem({
    required this.id,
    required this.tag,
    required this.postsCount,
    required this.reelsCount,
  });

  factory HashtagItem.fromMap(Map<String, dynamic> map) {
    return HashtagItem(
      id: map['id']?.toString() ?? '',
      tag: map['tag']?.toString() ?? '',
      postsCount: (map['posts_count'] as num?)?.toInt() ?? 0,
      reelsCount: (map['reels_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class HashtagService {
  HashtagService._internal();
  static final HashtagService instance = HashtagService._internal();

  final supabase = Supabase.instance.client;

  /// Extract all hashtags from post/reel text (e.g. #technology -> technology)
  List<String> extractHashtags(String text) {
    if (text.isEmpty) return [];
    final regex = RegExp(r'#([A-Za-z0-9_\u0600-\u06FF]+)');
    final matches = regex.allMatches(text);
    final Set<String> tags = {};
    for (var m in matches) {
      final tag = m.group(1)?.trim();
      if (tag != null && tag.isNotEmpty) {
        tags.add(tag);
      }
    }
    return tags.toList();
  }

  /// Sync post hashtags into hashtags and post_hashtags tables
  Future<void> syncPostHashtags(String postId, String text) async {
    final tags = extractHashtags(text);
    if (tags.isEmpty) return;

    for (var tag in tags) {
      try {
        // Upsert tag
        final res = await supabase
            .from('hashtags')
            .upsert(
              {'tag': tag},
              onConflict: 'tag',
            )
            .select('id, posts_count')
            .maybeSingle();

        if (res != null) {
          final hashtagId = res['id']?.toString();
          final currentCount = (res['posts_count'] as num?)?.toInt() ?? 0;

          if (hashtagId != null) {
            // Link to post
            await supabase.from('post_hashtags').upsert(
              {
                'post_id': postId,
                'hashtag_id': hashtagId,
              },
              onConflict: 'post_id,hashtag_id',
            );

            // Increment count
            await supabase.from('hashtags').update({
              'posts_count': currentCount + 1,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', hashtagId);
          }
        }
      } catch (e) {
        debugPrint('Error syncing post hashtag #$tag: $e');
      }
    }
  }

  /// Sync reel hashtags into hashtags and reel_hashtags tables
  Future<void> syncReelHashtags(String reelId, String text) async {
    final tags = extractHashtags(text);
    if (tags.isEmpty) return;

    for (var tag in tags) {
      try {
        final res = await supabase
            .from('hashtags')
            .upsert(
              {'tag': tag},
              onConflict: 'tag',
            )
            .select('id, reels_count')
            .maybeSingle();

        if (res != null) {
          final hashtagId = res['id']?.toString();
          final currentCount = (res['reels_count'] as num?)?.toInt() ?? 0;

          if (hashtagId != null) {
            await supabase.from('reel_hashtags').upsert(
              {
                'reel_id': reelId,
                'hashtag_id': hashtagId,
              },
              onConflict: 'reel_id,hashtag_id',
            );

            await supabase.from('hashtags').update({
              'reels_count': currentCount + 1,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', hashtagId);
          }
        }
      } catch (e) {
        debugPrint('Error syncing reel hashtag #$tag: $e');
      }
    }
  }

  /// Fetch trending hashtags for sidebar or explore
  Future<List<HashtagItem>> getTrendingHashtags({int limit = 8}) async {
    try {
      final res = await supabase
          .from('hashtags')
          .select('*')
          .order('posts_count', ascending: false)
          .limit(limit);

      return (res as List).map((m) => HashtagItem.fromMap(m)).toList();
    } catch (_) {
      // Fallback defaults
      return const [
        HashtagItem(id: '1', tag: 'Technology', postsCount: 14200, reelsCount: 2100),
        HashtagItem(id: '2', tag: 'Photography', postsCount: 8500, reelsCount: 1800),
        HashtagItem(id: '3', tag: 'ArtAndDesign', postsCount: 6100, reelsCount: 950),
        HashtagItem(id: '4', tag: 'Education', postsCount: 12800, reelsCount: 4200),
        HashtagItem(id: '5', tag: 'Music', postsCount: 5300, reelsCount: 1400),
      ];
    }
  }

  /// Search or suggest hashtags from database matching query (or top hashtags if query is empty)
  Future<List<HashtagItem>> searchHashtags(String query, {int limit = 10}) async {
    try {
      final cleanQuery = query.replaceAll('#', '').trim();
      var req = supabase.from('hashtags').select('*');
      if (cleanQuery.isNotEmpty) {
        req = req.ilike('tag', '%$cleanQuery%');
      }
      final res = await req
          .order('posts_count', ascending: false)
          .limit(limit);

      final list = (res as List).map((m) => HashtagItem.fromMap(m)).toList();
      if (list.isNotEmpty) return list;
      return await getTrendingHashtags(limit: limit);
    } catch (e) {
      debugPrint('Error searching hashtags: $e');
      return await getTrendingHashtags(limit: limit);
    }
  }
}
