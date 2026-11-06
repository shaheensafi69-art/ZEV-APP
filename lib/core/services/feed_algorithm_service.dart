import 'dart:math';

import '../../features/feed/models/feed_post_item.dart';
import '../../features/reels/models/reel_item.dart';

/// Next-Generation Instagram-Caliber Feed & Reels Mixing Engine for ZEV.
/// Implements multi-factor engagement ranking, author dispersion,
/// recency decay, and serendipitous discovery interleaving.
class FeedAlgorithmService {
  FeedAlgorithmService._();
  static final FeedAlgorithmService instance = FeedAlgorithmService._();

  final Random _random = Random();

  /// Mixes and ranks feed posts using Instagram-grade algorithmic distribution.
  /// Guarantees that:
  /// - A new post is not trivially forced to index 0.
  /// - High-engagement, trending, followed creators, and recent posts are mixed.
  /// - No single creator dominates consecutive feed slots (author dispersion).
  List<FeedPostItem> mixPosts(
    List<FeedPostItem> posts, {
    String? currentUserId,
  }) {
    if (posts.length <= 2) return posts;

    final now = DateTime.now();

    // 1. Calculate algorithmic weight for every post
    final List<_ScoredItem<FeedPostItem>> scored = posts.map((post) {
      final ageHours =
          max(0.1, now.difference(post.createdAt).inMinutes / 60.0);

      // Smooth time-decay (half-life around 20 hours)
      final recencyScore = 100.0 / (1.0 + (ageHours * 0.08));

      // Engagement power
      final engagementScore = (post.likesCount * 2.0) +
          (post.commentsCount * 4.0) +
          (post.repostsCount * 3.0);

      // Relationship & Trust affinity
      double affinityBonus = 0.0;
      if (post.isAuthorFollowed) affinityBonus += 25.0;
      if (post.isVerified) affinityBonus += 8.0;
      if (currentUserId != null && post.authorId == currentUserId) {
        // Author's own fresh posts get reasonable placement without hijacking top
        affinityBonus += 14.0;
      }

      // Serendipity / Exploration jitter (gives Instagram-style freshness on refresh)
      final explorationJitter = _random.nextDouble() * 22.0;

      final totalScore = (recencyScore * 0.40) +
          (engagementScore * 0.35) +
          affinityBonus +
          explorationJitter;

      return _ScoredItem(
        item: post,
        score: totalScore,
        authorId: post.authorId,
      );
    }).toList();

    // 2. Sort by computed score
    scored.sort((a, b) => b.score.compareTo(a.score));

    // 3. Author Dispersion & Interleaving (prevents consecutive posts from same author)
    return _disperseAuthors(
      scored.map((s) => s.item).toList(),
      (p) => p.authorId,
    );
  }

  /// Mixes and ranks video reels using Instagram Reels discovery cadence.
  List<ReelItem> mixReels(
    List<ReelItem> reels, {
    String? currentUserId,
  }) {
    if (reels.length <= 2) return reels;

    final now = DateTime.now();

    final List<_ScoredItem<ReelItem>> scored = reels.map((reel) {
      final ageHours =
          max(0.1, now.difference(reel.createdAt).inMinutes / 60.0);

      final recencyScore = 100.0 / (1.0 + (ageHours * 0.06));
      final engagementScore = (reel.likesCount * 2.0) +
          (reel.commentsCount * 3.5) +
          (reel.viewsCount * 0.05);

      double affinityBonus = 0.0;
      if (reel.isAuthorFollowed) affinityBonus += 20.0;
      if (reel.isVerified) affinityBonus += 10.0;

      final explorationJitter = _random.nextDouble() * 28.0;

      final totalScore = (recencyScore * 0.38) +
          (engagementScore * 0.40) +
          affinityBonus +
          explorationJitter;

      return _ScoredItem(
        item: reel,
        score: totalScore,
        authorId: reel.userId,
      );
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));

    return _disperseAuthors(
      scored.map((s) => s.item).toList(),
      (r) => r.userId,
    );
  }

  /// Re-orders a list of items so that items with the same authorId are spaced out
  List<T> _disperseAuthors<T>(List<T> items, String Function(T) getAuthorId) {
    if (items.length <= 2) return items;

    final List<T> result = [];
    final List<T> pool = List.from(items);

    String? lastAuthorId;

    while (pool.isNotEmpty) {
      // Find the best next candidate whose author is different from lastAuthorId
      int candidateIndex =
          pool.indexWhere((item) => getAuthorId(item) != lastAuthorId);

      if (candidateIndex == -1) {
        // If all remaining items are from the same author, take the first
        candidateIndex = 0;
      }

      final chosen = pool.removeAt(candidateIndex);
      result.add(chosen);
      lastAuthorId = getAuthorId(chosen);
    }

    return result;
  }
}

class _ScoredItem<T> {
  final T item;
  final double score;
  final String authorId;

  _ScoredItem({
    required this.item,
    required this.score,
    required this.authorId,
  });
}

