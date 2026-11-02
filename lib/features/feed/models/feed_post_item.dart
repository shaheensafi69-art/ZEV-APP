/// Data model representing an Instagram-grade feed post on ZEV.
class FeedPostItem {
  final String id;
  final String authorId;
  final String authorUsername;
  final String authorFullName;
  final String authorAvatar;
  final bool isVerified;
  final String title;
  final String content;
  final String imageUrl;
  final DateTime createdAt;
  final int likesCount;
  final bool isLikedByMe;
  final int commentsCount;
  final String categoryTag;
  final int repostsCount;
  final bool isRepostedByMe;
  final bool isAuthorFollowed;

  const FeedPostItem({
    required this.id,
    required this.authorId,
    required this.authorUsername,
    required this.authorFullName,
    required this.authorAvatar,
    required this.isVerified,
    required this.title,
    required this.content,
    required this.imageUrl,
    required this.createdAt,
    required this.likesCount,
    required this.isLikedByMe,
    required this.commentsCount,
    this.categoryTag = 'Explore',
    this.repostsCount = 0,
    this.isRepostedByMe = false,
    this.isAuthorFollowed = false,
  });

  FeedPostItem copyWith({
    String? id,
    String? authorId,
    String? authorUsername,
    String? authorFullName,
    String? authorAvatar,
    bool? isVerified,
    String? title,
    String? content,
    String? imageUrl,
    DateTime? createdAt,
    int? likesCount,
    bool? isLikedByMe,
    int? commentsCount,
    String? categoryTag,
    int? repostsCount,
    bool? isRepostedByMe,
    bool? isAuthorFollowed,
  }) {
    return FeedPostItem(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorUsername: authorUsername ?? this.authorUsername,
      authorFullName: authorFullName ?? this.authorFullName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      isVerified: isVerified ?? this.isVerified,
      title: title ?? this.title,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      commentsCount: commentsCount ?? this.commentsCount,
      categoryTag: categoryTag ?? this.categoryTag,
      repostsCount: repostsCount ?? this.repostsCount,
      isRepostedByMe: isRepostedByMe ?? this.isRepostedByMe,
      isAuthorFollowed: isAuthorFollowed ?? this.isAuthorFollowed,
    );
  }
}

/// Model representing an active user story in the Stories Tray.
class ActiveFriendStory {
  final String userId;
  final String username;
  final String avatarUrl;
  final int storiesCount;
  final bool isMe;

  const ActiveFriendStory({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.storiesCount,
    this.isMe = false,
  });
}
