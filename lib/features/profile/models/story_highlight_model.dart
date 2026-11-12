import 'dart:convert';
import 'dart:math';

/// Generates a RFC-4122 UUIDv4 string cleanly without requiring an external package.
String generateUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

final RegExp _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isValidUuid(String? value) =>
    value != null && _uuidRegex.hasMatch(value.trim());

/// Single item within a Story Highlight (Image, Video, or Text Note).
class StoryHighlightItem {
  final String id;
  final String? storyId;
  final String mediaUrl;
  final String mediaType; // 'image', 'video', 'text'
  final String caption;
  final DateTime createdAt;
  final List<int>? bgGradientColors; // For text stories: [0xFF..., 0xFF...]
  final String? thumbnailUrl;

  const StoryHighlightItem({
    required this.id,
    this.storyId,
    required this.mediaUrl,
    this.mediaType = 'image',
    this.caption = '',
    required this.createdAt,
    this.bgGradientColors,
    this.thumbnailUrl,
  });

  static String encodeCaptionWithGradient(
    String caption,
    List<int>? gradientColors,
  ) {
    if (gradientColors == null || gradientColors.length < 2) return caption;
    final hexList = gradientColors
        .map((c) => '0x${c.toRadixString(16).toUpperCase().padLeft(8, '0')}')
        .join(',');
    return '__grad:${hexList}__|$caption';
  }

  static ({String caption, List<int>? gradientColors}) decodeCaptionWithGradient(
    String rawCaption,
  ) {
    if (!rawCaption.startsWith('__grad:')) {
      return (caption: rawCaption, gradientColors: null);
    }
    final markerEnd = rawCaption.indexOf('__|');
    if (markerEnd == -1) {
      return (caption: rawCaption, gradientColors: null);
    }
    final header = rawCaption.substring('__grad:'.length, markerEnd);
    final actualCaption = rawCaption.substring(markerEnd + 3);
    final colors = header
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .toList();
    return (
      caption: actualCaption,
      gradientColors: colors.length >= 2 ? colors : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'story_id': storyId,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'caption': caption,
        'created_at': createdAt.toIso8601String(),
        'bg_gradient_colors': bgGradientColors,
        'thumbnail_url': thumbnailUrl,
      };

  factory StoryHighlightItem.fromJson(Map<String, dynamic> json) {
    final decodedCaption = decodeCaptionWithGradient(
      json['caption']?.toString() ?? '',
    );
    final explicitGrad = (json['bg_gradient_colors'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList();

    return StoryHighlightItem(
      id: isValidUuid(json['id']?.toString())
          ? json['id'].toString()
          : generateUuidV4(),
      storyId: isValidUuid(json['story_id']?.toString())
          ? json['story_id'].toString()
          : null,
      mediaUrl: json['media_url']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? 'image',
      caption: decodedCaption.caption,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      bgGradientColors: explicitGrad ?? decodedCaption.gradientColors,
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
      id: isValidUuid(json['id']?.toString())
          ? json['id'].toString()
          : generateUuidV4(),
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
