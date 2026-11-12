import 'dart:math';

import '../../features/feed/models/feed_post_item.dart';
import '../../features/reels/models/reel_item.dart';

/// Next-Generation Instagram-Caliber Feed & Reels Ranking Engine for ZEV.
/// Combines recency decay, weighted engagement signals, relationship trust,
/// lightweight session affinity (tags/categories/authors), negative-feedback
/// penalties, seen-item demotion, and strict author dispersion.
class FeedAlgorithmService {
  FeedAlgorithmService._();
  static final FeedAlgorithmService instance = FeedAlgorithmService._();

  final Random _random = Random();
  static final RegExp _hashtagPattern = RegExp(
    r'#([A-Za-z0-9_\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]+)',
  );

  // Bounded session-level personalization & suppression signals
  final Set<String> _seenPostIds = <String>{};
  final Set<String> _seenReelIds = <String>{};
  final Set<String> _suppressedPostIds = <String>{};
  final Set<String> _suppressedReelIds = <String>{};
  final Set<String> _suppressedAuthorIds = <String>{};
  final Map<String, double> _authorAffinity = <String, double>{};
  final Map<String, double> _topicAffinity = <String, double>{};

  void markSeen(String postId) {
    if (postId.isEmpty) return;
    if (_seenPostIds.length > 500) {
      _seenPostIds.remove(_seenPostIds.first);
    }
    _seenPostIds.add(postId);
  }

  void markReelSeen(String reelId) {
    if (reelId.isEmpty) return;
    if (_seenReelIds.length > 500) {
      _seenReelIds.remove(_seenReelIds.first);
    }
    _seenReelIds.add(reelId);
  }

  void recordPositiveInteraction({
    required String authorId,
    String? category,
    String? text,
    double weight = 4.0,
  }) {
    if (authorId.isNotEmpty) {
      _authorAffinity[authorId] =
          min(35.0, (_authorAffinity[authorId] ?? 0.0) + weight);
    }
    if (category != null && category.trim().isNotEmpty) {
      final key = category.trim().toLowerCase();
      _topicAffinity[key] = min(25.0, (_topicAffinity[key] ?? 0.0) + weight);
    }
    if (text != null && text.isNotEmpty) {
      for (final m in _hashtagPattern.allMatches(text)) {
        final tag = m.group(1)?.toLowerCase();
        if (tag != null && tag.isNotEmpty) {
          _topicAffinity['#$tag'] =
              min(25.0, (_topicAffinity['#$tag'] ?? 0.0) + weight);
        }
      }
    }
  }

  void recordNegativeFeedback({
    String? postId,
    String? reelId,
    String? authorId,
    bool suppressAuthor = false,
  }) {
    if (postId != null && postId.isNotEmpty) {
      _suppressedPostIds.add(postId);
    }
    if (reelId != null && reelId.isNotEmpty) {
      _suppressedReelIds.add(reelId);
    }
    if (authorId != null && authorId.isNotEmpty) {
      _authorAffinity[authorId] =
          max(-40.0, (_authorAffinity[authorId] ?? 0.0) - 18.0);
      if (suppressAuthor) {
        _suppressedAuthorIds.add(authorId);
      }
    }
  }

  void resetSessionSignals() {
    _seenPostIds.clear();
    _seenReelIds.clear();
    _suppressedPostIds.clear();
    _suppressedReelIds.clear();
    _suppressedAuthorIds.clear();
    _authorAffinity.clear();
    _topicAffinity.clear();
  }

  double _topicAffinityScore(String category, String text) {
    double bonus = 0.0;
    final cleanCat = category.trim().toLowerCase();
    if (cleanCat.isNotEmpty) {
      bonus += _topicAffinity[cleanCat] ?? 0.0;
    }
    if (text.isNotEmpty) {
      for (final m in _hashtagPattern.allMatches(text)) {
        final tag = m.group(1)?.toLowerCase();
        if (tag != null && tag.isNotEmpty) {
          bonus += _topicAffinity['#$tag'] ?? 0.0;
        }
      }
    }
    return min(25.0, bonus);
  }

  /// Mixes and ranks feed posts using Instagram-grade algorithmic distribution.
  List<FeedPostItem> mixPosts(
    List<FeedPostItem> posts, {
    String? currentUserId,
  }) {
    final visible = posts
        .where(
          (p) =>
              !_suppressedPostIds.contains(p.id) &&
              !_suppressedAuthorIds.contains(p.authorId),
        )
        .toList();
    if (visible.length <= 2) return visible;

    final now = DateTime.now();

    final List<_ScoredItem<FeedPostItem>> scored = visible.map((post) {
      final ageHours =
          max(0.1, now.difference(post.createdAt).inMinutes / 60.0);

      // Smooth time-decay (half-life ~18-20 hours)
      final recencyScore = 100.0 / (1.0 + (ageHours * 0.08));

      // Engagement signal weighted cleanly without spam domination
      final engagementScore = (post.likesCount * 2.0) +
          (post.commentsCount * 4.0) +
          (post.repostsCount * 3.0);

      // Relationship, creator trust & session interest affinity
      double affinityBonus = 0.0;
      if (post.isAuthorFollowed) affinityBonus += 26.0;
      if (post.isVerified) affinityBonus += 7.0;
      affinityBonus += _authorAffinity[post.authorId] ?? 0.0;
      affinityBonus += _topicAffinityScore(
        post.categoryTag,
        '${post.title} ${post.content}',
      );
      if (currentUserId != null && post.authorId == currentUserId) {
        affinityBonus += ageHours <= 2.0 ? 22.0 : 12.0;
      }

      // Demote previously seen items on refresh while keeping them reachable
      final seenPenalty = _seenPostIds.contains(post.id) ? -42.0 : 0.0;

      // Controlled exploration jitter for organic variety
      final explorationJitter = _random.nextDouble() * 14.0;

      final totalScore = (recencyScore * 0.40) +
          (engagementScore * 0.35) +
          affinityBonus +
          seenPenalty +
          explorationJitter;

      return _ScoredItem(
        item: post,
        score: totalScore,
        authorId: post.authorId,
      );
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));

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
    final visible = reels
        .where(
          (r) =>
              !_suppressedReelIds.contains(r.id) &&
              !_suppressedAuthorIds.contains(r.userId),
        )
        .toList();
    if (visible.length <= 2) return visible;

    final now = DateTime.now();

    final List<_ScoredItem<ReelItem>> scored = visible.map((reel) {
      final ageHours =
          max(0.1, now.difference(reel.createdAt).inMinutes / 60.0);

      final recencyScore = 100.0 / (1.0 + (ageHours * 0.06));
      final engagementScore = (reel.likesCount * 2.2) +
          (reel.commentsCount * 4.0) +
          (reel.viewsCount * 0.05);

      double affinityBonus = 0.0;
      if (reel.isAuthorFollowed) affinityBonus += 20.0;
      if (reel.isVerified) affinityBonus += 9.0;
      affinityBonus += _authorAffinity[reel.userId] ?? 0.0;
      affinityBonus += _topicAffinityScore(
        reel.category,
        '${reel.title} ${reel.description}',
      );
      if (currentUserId != null && reel.userId == currentUserId && ageHours <= 2.0) {
        affinityBonus += 16.0;
      }

      final seenPenalty = _seenReelIds.contains(reel.id) ? -48.0 : 0.0;
      final explorationJitter = _random.nextDouble() * 18.0;

      final totalScore = (recencyScore * 0.38) +
          (engagementScore * 0.40) +
          affinityBonus +
          seenPenalty +
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

  /// Spaces out consecutive items from the same creator.
  List<T> _disperseAuthors<T>(List<T> items, String Function(T) getAuthorId) {
    if (items.length <= 2) return items;

    final List<T> result = [];
    final List<T> pool = List.from(items);
    String? lastAuthorId;

    while (pool.isNotEmpty) {
      int candidateIndex =
          pool.indexWhere((item) => getAuthorId(item) != lastAuthorId);

      if (candidateIndex == -1) {
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
