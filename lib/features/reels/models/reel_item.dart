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
}

