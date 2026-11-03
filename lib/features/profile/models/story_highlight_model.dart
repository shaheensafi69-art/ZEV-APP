import 'dart:convert';

/// Single item within a Story Highlight (Image, Video, or Text Note).
class StoryHighlightItem {
  final String id;
  final String mediaUrl;
  final String mediaType; // 'image', 'video', 'text'
  final String caption;
  final DateTime createdAt;
  final List<int>? bgGradientColors; // For text stories: [0xFF..., 0xFF...]
  final String? thumbnailUrl;

  const StoryHighlightItem({
    required this.id,
    required this.mediaUrl,
    this.mediaType = 'image',
    this.caption = '',
    required this.createdAt,
    this.bgGradientColors,
    this.thumbnailUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'caption': caption,
        'created_at': createdAt.toIso8601String(),
        'bg_gradient_colors': bgGradientColors,
        'thumbnail_url': thumbnailUrl,
      };

  factory StoryHighlightItem.fromJson(Map<String, dynamic> json) {
    return StoryHighlightItem(
      id: json['id']?.toString() ?? '',
      mediaUrl: json['media_url']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? 'image',
      caption: json['caption']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      bgGradientColors: (json['bg_gradient_colors'] as List?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
    );
  }
}

/// Curated Story Highlight displayed on the user's Instagram-grade profile.
class StoryHighlight {
  final String id;
  final String userId;
  final String title;
  final String coverUrl;
  final DateTime createdAt;
  final List<StoryHighlightItem> items;

  const StoryHighlight({
    required this.id,
    required this.userId,
    required this.title,
    required this.coverUrl,
    required this.createdAt,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'cover_url': coverUrl,
        'created_at': createdAt.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory StoryHighlight.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    return StoryHighlight(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Highlight',
      coverUrl: json['cover_url']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      items: rawItems
          .map((i) => StoryHighlightItem.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
    );
  }

  static String encodeList(List<StoryHighlight> list) =>
      jsonEncode(list.map((h) => h.toJson()).toList());

  static List<StoryHighlight> decodeList(String jsonString) {
    if (jsonString.isEmpty) return [];
    try {
      final decoded = jsonDecode(jsonString) as List;
      return decoded
          .map((e) => StoryHighlight.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

