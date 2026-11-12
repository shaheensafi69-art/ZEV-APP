/// Single ordered media slide belonging to a ZEV feed post carousel.
class FeedPostMediaItem {
  final String id;
  final String mediaType;
  final String mediaUrl;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final int sortOrder;

  const FeedPostMediaItem({
    required this.id,
    this.mediaType = 'image',
    required this.mediaUrl,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.durationSeconds,
    this.sortOrder = 0,
  });

  factory FeedPostMediaItem.fromMap(Map<String, dynamic> m) {
    return FeedPostMediaItem(
      id: m['id']?.toString() ?? '',
      mediaType: (m['media_type'] ?? 'image').toString(),
      mediaUrl: (m['media_url'] ?? '').toString(),
      thumbnailUrl: m['thumbnail_url']?.toString(),
      width: (m['width'] as num?)?.toInt(),
      height: (m['height'] as num?)?.toInt(),
      durationSeconds: (m['duration_seconds'] as num?)?.toInt(),
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Lightweight user profile reference for post collaborators or tagged users.
class FeedPostUserTag {
  final String id;
  final String username;
  final String firstName;
  final String lastName;
  final String avatarUrl;
  final bool isVerified;

  const FeedPostUserTag({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
    this.avatarUrl = '',
    this.isVerified = false,
  });

  String get fullName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : '@$username';
  }

  factory FeedPostUserTag.fromMap(Map<String, dynamic> m) {
    final uname = (m['username'] ?? '').toString().trim();
    final fn = (m['first_name'] ?? '').toString().trim();
    final ln = (m['last_name'] ?? '').toString().trim();
    return FeedPostUserTag(
      id: m['id']?.toString() ?? '',
      username: uname.isNotEmpty ? uname : 'user',
      firstName: fn,
      lastName: ln,
      avatarUrl: (m['avatar_url'] ?? '').toString(),
      isVerified: m['is_verified'] == true,
    );
  }
}

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
  final bool isBookmarkedByMe;
  final bool isAuthorFollowed;
  final DateTime? editedAt;
  final String location;
  final List<FeedPostMediaItem> mediaItems;
  final List<FeedPostUserTag> collaborators;
  final List<FeedPostUserTag> taggedUsers;
  final bool isDraft;
  final DateTime? scheduledAt;

  const FeedPostItem({
    required this.id,
    required this.authorId,
    required this.authorUsername,
    required this.authorFullName,
    required this.authorAvatar,
    this.isVerified = false,
    required this.title,
    required this.content,
    required this.imageUrl,
    required this.createdAt,
    this.likesCount = 0,
    this.isLikedByMe = false,
    this.commentsCount = 0,
    this.categoryTag = 'Explore',
    this.repostsCount = 0,
    this.isRepostedByMe = false,
    this.isBookmarkedByMe = false,
    this.isAuthorFollowed = false,
    this.editedAt,
    this.location = '',
    this.mediaItems = const [],
    this.collaborators = const [],
    this.taggedUsers = const [],
    this.isDraft = false,
    this.scheduledAt,
  });

  /// Returns ordered carousel media descriptors (`mediaItems` sorted by `sortOrder`),
  /// falling back cleanly to a synthetic item from legacy [imageUrl] when present.
  List<FeedPostMediaItem> get effectiveMediaItems {
    if (mediaItems.isNotEmpty) {
      final sorted = List<FeedPostMediaItem>.of(mediaItems)
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final valid = sorted.where((m) => m.mediaUrl.trim().isNotEmpty).toList();
      if (valid.isNotEmpty) return valid;
    }
    if (imageUrl.trim().isNotEmpty) {
      return [
        FeedPostMediaItem(
          id: '${id}_legacy',
          mediaType: 'image',
          mediaUrl: imageUrl.trim(),
        ),
      ];
    }
    return const [];
  }

  /// Returns ordered carousel URLs (`mediaItems` sorted by `sortOrder`),
  /// falling back cleanly to legacy [imageUrl] when present.
  List<String> get effectiveMediaUrls {
    return effectiveMediaItems.map((m) => m.mediaUrl.trim()).toList();
  }

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
    bool? isBookmarkedByMe,
    bool? isAuthorFollowed,
    DateTime? editedAt,
    String? location,
    List<FeedPostMediaItem>? mediaItems,
    List<FeedPostUserTag>? collaborators,
    List<FeedPostUserTag>? taggedUsers,
    bool? isDraft,
    DateTime? scheduledAt,
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
      isBookmarkedByMe: isBookmarkedByMe ?? this.isBookmarkedByMe,
      isAuthorFollowed: isAuthorFollowed ?? this.isAuthorFollowed,
      editedAt: editedAt ?? this.editedAt,
      location: location ?? this.location,
      mediaItems: mediaItems ?? this.mediaItems,
      collaborators: collaborators ?? this.collaborators,
      taggedUsers: taggedUsers ?? this.taggedUsers,
      isDraft: isDraft ?? this.isDraft,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }

  factory FeedPostItem.fromRpcMap(Map<String, dynamic> p) {
    final fn = (p['author_first_name'] ?? '').toString();
    final ln = (p['author_last_name'] ?? '').toString();
    final full = '$fn $ln'.trim();
    final username = (p['author_username'] ?? '').toString();

    final parsedMedia = <FeedPostMediaItem>[];
    if (p['media_items'] is List) {
      for (final raw in (p['media_items'] as List)) {
        if (raw is Map) {
          final item = FeedPostMediaItem.fromMap(
            Map<String, dynamic>.from(raw),
          );
          if (item.mediaUrl.trim().isNotEmpty) {
            parsedMedia.add(item);
          }
        }
      }
      parsedMedia.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    var resolvedImageUrl = (p['image_url'] ?? '').toString();
    if (resolvedImageUrl.isEmpty && parsedMedia.isNotEmpty) {
      resolvedImageUrl = parsedMedia.first.mediaUrl;
    }

    final parsedCollaborators = <FeedPostUserTag>[];
    if (p['collaborator_profiles'] is List) {
      for (final raw in (p['collaborator_profiles'] as List)) {
        if (raw is Map) {
          final tag = FeedPostUserTag.fromMap(Map<String, dynamic>.from(raw));
          if (tag.id.isNotEmpty) parsedCollaborators.add(tag);
        }
      }
    }

    final parsedTagged = <FeedPostUserTag>[];
    if (p['tagged_profiles'] is List) {
      for (final raw in (p['tagged_profiles'] as List)) {
        if (raw is Map) {
          final tag = FeedPostUserTag.fromMap(Map<String, dynamic>.from(raw));
          if (tag.id.isNotEmpty) parsedTagged.add(tag);
        }
      }
    }

    return FeedPostItem(
      id: p['id']?.toString() ?? '',
      authorId: p['student_id']?.toString() ?? '',
      authorUsername: username.isNotEmpty
          ? username
          : (full.isNotEmpty ? full : 'user'),
      authorFullName: full,
      authorAvatar: (p['author_avatar_url'] ?? '').toString(),
      isVerified: p['author_is_verified'] == true,
      title: (p['title'] ?? '').toString(),
      content: (p['content'] ?? '').toString(),
      imageUrl: resolvedImageUrl,
      createdAt: DateTime.tryParse(p['created_at']?.toString() ?? '') ??
          DateTime.now(),
      likesCount: (p['likes_count'] as num?)?.toInt() ?? 0,
      isLikedByMe: p['is_liked_by_me'] == true,
      commentsCount: (p['comments_count'] as num?)?.toInt() ?? 0,
      repostsCount: (p['reposts_count'] as num?)?.toInt() ?? 0,
      isRepostedByMe: p['is_reposted_by_me'] == true,
      isBookmarkedByMe: p['is_bookmarked_by_me'] == true,
      isAuthorFollowed: p['is_author_followed'] == true,
      editedAt: DateTime.tryParse(p['edited_at']?.toString() ?? ''),
      location: (p['location'] ?? '').toString(),
      mediaItems: parsedMedia,
      collaborators: parsedCollaborators,
      taggedUsers: parsedTagged,
      isDraft: p['is_draft'] == true,
      scheduledAt: DateTime.tryParse(p['scheduled_at']?.toString() ?? ''),
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
  final bool hasUnseen;
  final bool hasCloseFriendStory;

  const ActiveFriendStory({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.storiesCount,
    this.isMe = false,
    this.hasUnseen = true,
    this.hasCloseFriendStory = false,
  });
}
