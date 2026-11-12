/// Data model representing a high-performance video Reel on ZEV.
class ReelItem {
  final String id;
  final String userId;
  final String authorUsername;
  final String authorFullName;
  final String authorAvatar;
  final bool isVerified;
  final String videoUrl;
  final String? thumbnailUrl;
  final String title;
  final String description;
  final String category;
  final int durationSeconds;
  final int viewsCount;
  final int likesCount;
  final bool isLikedByMe;
  final int commentsCount;
  final bool isBookmarkedByMe;
  final bool isAuthorFollowed;
  final DateTime createdAt;

  const ReelItem({
    required this.id,
    required this.userId,
    required this.authorUsername,
    required this.authorFullName,
    required this.authorAvatar,
    required this.isVerified,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.title,
    this.description = '',
    this.category = 'Explore',
    this.durationSeconds = 30,
    this.viewsCount = 0,
    this.likesCount = 0,
    this.isLikedByMe = false,
    this.commentsCount = 0,
    this.isBookmarkedByMe = false,
    this.isAuthorFollowed = false,
    required this.createdAt,
  });

  ReelItem copyWith({
    String? id,
    String? userId,
    String? authorUsername,
    String? authorFullName,
    String? authorAvatar,
    bool? isVerified,
    String? videoUrl,
    String? thumbnailUrl,
    String? title,
    String? description,
    String? category,
    int? durationSeconds,
    int? viewsCount,
    int? likesCount,
    bool? isLikedByMe,
    int? commentsCount,
    bool? isBookmarkedByMe,
    bool? isAuthorFollowed,
    DateTime? createdAt,
  }) {
    return ReelItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      authorUsername: authorUsername ?? this.authorUsername,
      authorFullName: authorFullName ?? this.authorFullName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      isVerified: isVerified ?? this.isVerified,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      viewsCount: viewsCount ?? this.viewsCount,
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      commentsCount: commentsCount ?? this.commentsCount,
      isBookmarkedByMe: isBookmarkedByMe ?? this.isBookmarkedByMe,
      isAuthorFollowed: isAuthorFollowed ?? this.isAuthorFollowed,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ReelItem.fromRpcMap(Map<String, dynamic> r) {
    final fn = (r['author_first_name'] ?? '').toString();
    final ln = (r['author_last_name'] ?? '').toString();
    final full = '$fn $ln'.trim();
    final username = (r['author_username'] ?? '').toString();

    return ReelItem(
      id: r['id']?.toString() ?? '',
      userId: r['user_id']?.toString() ?? '',
      authorUsername: username.isNotEmpty
          ? username
          : (full.isNotEmpty ? full : 'creator'),
      authorFullName: full,
      authorAvatar: (r['author_avatar_url'] ?? '').toString(),
      isVerified: r['author_is_verified'] == true,
      videoUrl: (r['video_url'] ?? '').toString(),
      thumbnailUrl: r['thumbnail_url']?.toString(),
      title: (r['title'] ?? '').toString(),
      description: (r['description'] ?? '').toString(),
      category: (r['category'] ?? 'Explore').toString(),
      durationSeconds: (r['duration_seconds'] as num?)?.toInt() ?? 30,
      viewsCount: (r['views_count'] as num?)?.toInt() ?? 0,
      likesCount: (r['likes_count'] as num?)?.toInt() ?? 0,
      isLikedByMe: r['is_liked_by_me'] == true,
      commentsCount: (r['comments_count'] as num?)?.toInt() ?? 0,
      isBookmarkedByMe: r['is_bookmarked_by_me'] == true,
      isAuthorFollowed: r['is_author_followed'] == true,
      createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

