import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/media_processing_service.dart';
import '../../../core/utils/app_media_picker.dart';
import '../../../core/widgets/auth_required_modal.dart';
import '../widgets/reels_ad_card.dart';
import '../../../core/widgets/fast_cached_image.dart';

/// Modern 2-second floating toast in English with no system paths
void _showReelsToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.only(bottom: 36, left: 45, right: 45),
      padding: EdgeInsets.zero,
      content: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: isError
                ? const Color(0xFFE11D48).withValues(alpha: 0.96)
                : const Color(0xFF1E1E2E).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isError
                  ? Colors.redAccent.withValues(alpha: 0.6)
                  : const Color(0xFFFC466B).withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                color: isError ? Colors.white : const Color(0xFFFC466B),
                size: 19,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Instagram-like animated Heart Overlay for double tap
class _InstagramHeartOverlay extends StatefulWidget {
  final VoidCallback onAnimationComplete;
  const _InstagramHeartOverlay({super.key, required this.onAnimationComplete});

  @override
  State<_InstagramHeartOverlay> createState() => _InstagramHeartOverlayState();
}

class _InstagramHeartOverlayState extends State<_InstagramHeartOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.2,
          end: 1.3,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.3,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_animCtrl);

    _opacityAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 65),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
    ]).animate(_animCtrl);

    _animCtrl.forward().then((_) {
      widget.onAnimationComplete();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnim.value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66F494AC),
                      blurRadius: 35,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFFC466B),
                  size: 110,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ReelItemData {
  final String id;
  final String userId;
  final String videoUrl;
  final String? thumbnailUrl;
  final String title;
  final String? description;
  final String category;
  int viewsCount;
  int likesCount;
  int commentsCount;
  bool isLikedByMe;
  bool isSavedByMe;
  String authorName;
  String authorAvatar;
  DateTime? createdAt;

  ReelItemData({
    required this.id,
    required this.userId,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.title,
    this.description,
    required this.category,
    this.viewsCount = 0,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLikedByMe = false,
    this.isSavedByMe = false,
    this.authorName = 'ZEV User',
    this.authorAvatar = '',
    this.createdAt,
  });
}

class StudentReelsScreen extends StatefulWidget {
  final bool isActive;
  final String? targetReelId;
  const StudentReelsScreen({
    super.key,
    this.isActive = true,
    this.targetReelId,
  });

  @override
  State<StudentReelsScreen> createState() => _StudentReelsScreenState();
}

class _StudentReelsScreenState extends State<StudentReelsScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;

  String selectedTab = 'for_you'; // 'for_you' or 'friends'
  List<ReelItemData> allForYouReels = [];
  List<ReelItemData> allFriendsReels = [];
  List<ReelItemData> reels = [];
  int activeIndex = 0;
  final PageController _pageController = PageController();

  final Set<String> _viewedReelIds = {};
  final Set<String> _recentlyFeaturedReelIds = {};
  String? _activeHeartReelId;
  int _heartAnimTrigger = 0;

  static const Color primaryPink = Color(0xFFFC466B);

  void _handleDoubleTapReel(ReelItemData reel) {
    HapticFeedback.mediumImpact();
    setState(() {
      _activeHeartReelId = reel.id;
      _heartAnimTrigger++;
    });

    if (!reel.isLikedByMe) {
      _toggleLikeReel(reel);
    }
  }

  final List<String> categories = [
    '🔥 All',
    '🚀 Explore',
    '📊 Trading',
    '💻 Coding',
    '💡 Crypto',
    '🎓 Educational',
  ];
  String selectedCategory = '🔥 All';

  @override
  void initState() {
    super.initState();
    _fetchReels();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchReels() async {
    setState(() => isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      final currentUserId = user?.id ?? '';

      // 1. Fetch all published reels from reels table
      final res = await supabase
          .from('reels')
          .select('*')
          .eq('is_published', true);

      // 2. Batch fetch user likes and saved reels
      Set<String> myLikedReelIds = {};
      Set<String> mySavedReelIds = {};
      if (currentUserId.isNotEmpty) {
        try {
          final myLikes = await supabase
              .from('reel_likes')
              .select('reel_id')
              .eq('user_id', currentUserId);
          myLikedReelIds = (myLikes as List)
              .map((e) => e['reel_id']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toSet();
        } catch (e) {
          debugPrint('Error fetching user likes batch: $e');
        }

        // 2.5. Fetch previously viewed reels to prevent duplicate views
        try {
          final myViews = await supabase
              .from('reel_views')
              .select('reel_id')
              .eq('viewer_id', currentUserId);
          final viewedIds = (myViews as List)
              .map((e) => e['reel_id']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toSet();
          _viewedReelIds.addAll(viewedIds);
        } catch (e) {
          debugPrint('Error fetching user views batch: $e');
        }

        // 2.6. Batch fetch bookmarked reels
        try {
          final myBookmarks = await supabase
              .from('reel_bookmarks')
              .select('reel_id')
              .eq('user_id', currentUserId);
          mySavedReelIds = (myBookmarks as List)
              .map((e) => e['reel_id']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toSet();
        } catch (e) {
          debugPrint('Error fetching user reel bookmarks batch: $e');
        }
      }

      // 3. Fetch confirmed friends from student_friends table
      Set<String> friendIds = {};
      if (currentUserId.isNotEmpty) {
        try {
          final friendsRes = await supabase
              .from('student_friends')
              .select('sender_id, receiver_id')
              .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
              .eq('status', 'accepted');
          for (var f in (friendsRes as List)) {
            final s = f['sender_id']?.toString() ?? '';
            final r = f['receiver_id']?.toString() ?? '';
            if (s.isNotEmpty && s != currentUserId) friendIds.add(s);
            if (r.isNotEmpty && r != currentUserId) friendIds.add(r);
          }
        } catch (e) {
          debugPrint('Error fetching friend ids: $e');
        }
      }

      // 4. Batch fetch creator profiles
      final userIds = (res as List)
          .map((r) => r['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (userIds.isNotEmpty) {
        try {
          final profRes = await supabase
              .from('profiles')
              .select('id, first_name, last_name, avatar_url')
              .inFilter('id', userIds);
          for (var p in (profRes as List)) {
            profilesMap[p['id'].toString()] = p;
          }
        } catch (e) {
          debugPrint('Error batch fetching profiles: $e');
        }
      }

      // 5. Advanced explore ranking algorithm
      // Ranking based on comments, likes, views, recency and smart rotation
      double calculateExploreScore(Map<String, dynamic> r) {
        final likes = (r['likes_count'] as num?)?.toDouble() ?? 0.0;
        final comments = (r['comments_count'] as num?)?.toDouble() ?? 0.0;
        final views = (r['views_count'] as num?)?.toDouble() ?? 0.0;

        // 5x comments, 3x likes, 0.8x views
        double score = (comments * 5.0) + (likes * 3.0) + (views * 0.8);

        // Recency boost for fresh reels
        try {
          final createdAt = DateTime.parse(r['created_at'].toString());
          final hoursAgo = DateTime.now().difference(createdAt).inHours;
          if (hoursAgo < 6) {
            score += 55.0;
          } else if (hoursAgo < 24) {
            score += 38.0;
          } else if (hoursAgo < 72) {
            score += 22.0;
          } else if (hoursAgo < 168) {
            score += 10.0;
          }
        } catch (_) {}

        // Explore jitter for diverse feed rotation
        final dynamicJitter = Random().nextDouble() * 28.0;
        score += dynamicJitter;

        // Rotate previously featured top reels
        final id = r['id']?.toString() ?? '';
        if (_recentlyFeaturedReelIds.contains(id)) {
          score -= 35.0;
        }

        return score;
      }

      List<Map<String, dynamic>> rawList = List<Map<String, dynamic>>.from(
        res as List,
      );
      // Sort explore by highest score
      rawList.sort(
        (a, b) => calculateExploreScore(b).compareTo(calculateExploreScore(a)),
      );

      // Track top 4 reels for rotation
      _recentlyFeaturedReelIds.clear();
      for (var i = 0; i < min(4, rawList.length); i++) {
        final id = rawList[i]['id']?.toString();
        if (id != null) _recentlyFeaturedReelIds.add(id);
      }

      List<ReelItemData> loaded = [];

      for (var r in rawList) {
        final id = r['id'].toString();
        final uId = r['user_id'].toString();

        String authorName = 'ZEV User';
        String authorAvatar = '';

        if (profilesMap.containsKey(uId)) {
          final prof = profilesMap[uId]!;
          authorName = '${prof['first_name'] ?? ''} ${prof['last_name'] ?? ''}'
              .trim();
          if (authorName.isEmpty) authorName = 'ZEV User';
          authorAvatar = prof['avatar_url'] ?? '';
        }

        DateTime? createdAt;
        try {
          if (r['created_at'] != null) {
            createdAt = DateTime.parse(r['created_at'].toString());
          }
        } catch (_) {}

        loaded.add(
          ReelItemData(
            id: id,
            userId: uId,
            videoUrl: r['video_url'] ?? '',
            thumbnailUrl: r['thumbnail_url'],
            title: r['title'] ?? 'Educational Reel',
            description: r['description'],
            category: r['category'] ?? 'Educational',
            viewsCount: r['views_count'] ?? 0,
            likesCount: r['likes_count'] ?? 0,
            commentsCount: r['comments_count'] ?? 0,
            isLikedByMe: myLikedReelIds.contains(id),
            isSavedByMe: mySavedReelIds.contains(id),
            authorName: authorName,
            authorAvatar: authorAvatar,
            createdAt: createdAt,
          ),
        );
      }

      // If opened via deep link, prepend target reel
      if (widget.targetReelId != null) {
        final targetIndex = loaded.indexWhere(
          (r) => r.id == widget.targetReelId,
        );
        if (targetIndex != -1) {
          final targetReel = loaded.removeAt(targetIndex);
          loaded.insert(0, targetReel);
        }
      }

      allForYouReels = loaded;
      allFriendsReels = loaded
          .where((r) => friendIds.contains(r.userId))
          .toList();

      if (mounted) {
        setState(() {
          reels = (selectedTab == 'friends') ? allFriendsReels : allForYouReels;
          isLoading = false;
        });

        // Record view for initial reel
        if (reels.isNotEmpty && widget.isActive) {
          _recordView(reels.first);
        }
      }
    } catch (e) {
      debugPrint('Error fetching reels: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Record unique view in reel_views and reels table
  Future<void> _recordView(ReelItemData reel) async {
    final user = supabase.auth.currentUser;
    final currentUserId = user?.id ?? '';

    // 1. Local cache deduplication check
    if (_viewedReelIds.contains(reel.id)) return;
    _viewedReelIds.add(reel.id);

    if (currentUserId.isEmpty) return;

    try {
      // 2. Database deduplication check
      final existingView = await supabase
          .from('reel_views')
          .select('id')
          .eq('reel_id', reel.id)
          .eq('viewer_id', currentUserId)
          .maybeSingle();

      if (existingView != null) {
        // Reel already viewed by user; skip increment
        return;
      }

      // 3. Insert record in reel_views table
      await supabase.from('reel_views').insert({
        'reel_id': reel.id,
        'viewer_id': currentUserId,
        'viewed_at': DateTime.now().toIso8601String(),
      });

      // 4. Increment views_count in reels table
      reel.viewsCount += 1;
      await supabase
          .from('reels')
          .update({'views_count': reel.viewsCount})
          .eq('id', reel.id);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error recording unique reel view: $e');
    }
  }

  // Like or unlike reel with two-way sync in reel_likes and reels
  Future<void> _toggleLikeReel(ReelItemData reel) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "like reels");
      return;
    }

    final willBeLiked = !reel.isLikedByMe;

    setState(() {
      reel.isLikedByMe = willBeLiked;
      if (willBeLiked) {
        reel.likesCount += 1;
      } else {
        reel.likesCount = (reel.likesCount > 0) ? reel.likesCount - 1 : 0;
      }
    });

    try {
      if (willBeLiked) {
        // 1. Add to reel_likes table
        await supabase.from('reel_likes').insert({
          'reel_id': reel.id,
          'user_id': user.id,
          'created_at': DateTime.now().toIso8601String(),
        });

        // 2. Recount and update reels table
        final countRes = await supabase
            .from('reel_likes')
            .select('id')
            .eq('reel_id', reel.id);
        final realLikes = (countRes as List).length;
        reel.likesCount = realLikes;
        await supabase
            .from('reels')
            .update({'likes_count': realLikes})
            .eq('id', reel.id);

        // 3. Send notification to reel creator
        if (reel.userId != user.id) {
          try {
            final senderProfile = await supabase
                .from('profiles')
                .select('first_name, last_name')
                .eq('id', user.id)
                .maybeSingle();
            final String senderName = (senderProfile != null)
                ? '${senderProfile['first_name'] ?? 'Someone'} ${senderProfile['last_name'] ?? ''}'
                      .trim()
                : 'Someone';

            await supabase.from('user_notifications').insert({
              'user_id': reel.userId,
              'sender_id': user.id,
              'title': 'Liked your Reel ❤️',
              'message':
                  '$senderName liked your educational video: "${reel.title}"',
              'notification_type': 'like',
              'link_url': '/reel/${reel.id}',
              'is_read': false,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }
      } else {
        // Remove from reel_likes
        await supabase
            .from('reel_likes')
            .delete()
            .eq('reel_id', reel.id)
            .eq('user_id', user.id);

        // Recount and update reels table
        final countRes = await supabase
            .from('reel_likes')
            .select('id')
            .eq('reel_id', reel.id);
        final realLikes = (countRes as List).length;
        reel.likesCount = realLikes;
        await supabase
            .from('reels')
            .update({'likes_count': realLikes})
            .eq('id', reel.id);
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error toggling reel like: $e');
    }
  }

  // Bookmark reel for future viewing
  Future<void> _toggleSaveReel(ReelItemData reel) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "save reels");
      return;
    }

    HapticFeedback.lightImpact();
    final previousState = reel.isSavedByMe;
    setState(() {
      reel.isSavedByMe = !previousState;
    });

    try {
      if (previousState) {
        // Remove from saved items
        await supabase
            .from('reel_bookmarks')
            .delete()
            .eq('reel_id', reel.id)
            .eq('user_id', user.id);
        if (mounted) {
          _showReelsToast(context, 'Removed from saved items');
        }
      } else {
        // Add to saved items
        await supabase.from('reel_bookmarks').insert({
          'reel_id': reel.id,
          'user_id': user.id,
        });
        if (mounted) {
          _showReelsToast(context, 'Reel saved to bookmarks 🔖');
        }
      }
    } catch (e) {
      debugPrint('Save reel error: $e');
      if (mounted) {
        setState(() {
          reel.isSavedByMe = previousState;
        });
      }
    }
  }

  // Download reel video and save directly to phone gallery
  Future<void> _downloadReel(ReelItemData reel) async {
    double progress = 0.0;
    StateSetter? setProgressState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          setProgressState = setDialogState;
          return AlertDialog(
            backgroundColor: const Color(0xFF1F2937),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.downloading_rounded, color: primaryPink, size: 28),
                SizedBox(width: 10),
                Text(
                  'Downloading Reel...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reel.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  color: primaryPink,
                  backgroundColor: Colors.white12,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(
                    color: primaryPink,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      // 1. Download to temporary directory
      final tempDir = await getTemporaryDirectory();
      final tempFilePath =
          '${tempDir.path}/raw_reel_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final dio = Dio();
      await dio.download(
        reel.videoUrl,
        tempFilePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && setProgressState != null) {
            setProgressState!(() {
              progress = received / total;
            });
          }
        },
      );

      // 2. Add ZEV watermark to video
      File finalVideoFile = File(tempFilePath);
      try {
        finalVideoFile = await MediaProcessingService.instance
            .addWatermarkToVideoForDownload(inputVideoPath: tempFilePath);
      } catch (watermarkErr) {
        debugPrint('Watermark overlay error: $watermarkErr');
      }

      // Close download progress dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // 3. Save to phone media storage (MediaStore on Android / Photos on iOS)
      try {
        await Gal.putVideo(finalVideoFile.path, album: 'ZEV');
      } catch (galErr) {
        debugPrint('Gal album save fallback: $galErr');
        try {
          await Gal.putVideo(finalVideoFile.path);
        } catch (_) {}
      }

      // Clean up temporary file
      try {
        final tempFile = File(tempFilePath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (finalVideoFile.path != tempFilePath &&
            await finalVideoFile.exists()) {
          await finalVideoFile.delete();
        }
      } catch (_) {}

      // 4. Show clean 2-second success toast
      if (mounted) {
        _showReelsToast(context, 'Video saved to gallery 🎬');
      }
    } catch (e) {
      debugPrint('Error saving reel to gallery: $e');
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showReelsToast(context, 'Failed to save video', isError: true);
      }
    }
  }

  // Open share dialog to send to friends
  void _openShareModal(ReelItemData reel) {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "share reels");
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReelShareBottomSheet(reel: reel),
    );
  }

  // Open comments bottom sheet
  void _openReelComments(ReelItemData reel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReelCommentsBottomSheet(
        reelId: reel.id,
        onCommentAdded: (newCount) {
          setState(() {
            reel.commentsCount = newCount;
          });
        },
      ),
    );
  }

  void _showUploadReelDialog() {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "upload reels");
      return;
    }
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    bool isUploadingFile = false;
    String uploadCategory = 'Explore';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upload Educational Reel 🎬',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  hintText: 'Reel Title',
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Select category
              DropdownButtonFormField<String>(
                initialValue: uploadCategory,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'Explore', child: Text('🌟 Explore')),
                  DropdownMenuItem(
                    value: 'Educational',
                    child: Text('🎓 Educational'),
                  ),
                  DropdownMenuItem(value: 'Trading', child: Text('📊 Trading')),
                  DropdownMenuItem(value: 'Coding', child: Text('💻 Coding')),
                  DropdownMenuItem(
                    value: 'Motivation',
                    child: Text('🔥 Motivation'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setModalState(() => uploadCategory = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: isUploadingFile
                    ? null
                    : () async {
                        final video = await AppMediaPicker.instance.pickVideo();
                        if (video != null) {
                          setModalState(() => isUploadingFile = true);
                          try {
                            // 🎬 Mobile compression + ZEV watermark
                            final processedFile = await MediaProcessingService
                                .instance
                                .processVideoWithWatermark(
                                  inputVideoPath: video.path,
                                );

                            final bytes = await processedFile.readAsBytes();
                            final user = supabase.auth.currentUser;
                            final uId = user?.id ?? 'guest';
                            final fileName =
                                'reel_${DateTime.now().millisecondsSinceEpoch}_$uId.mp4';
                            final publicUrl = await CloudflareStorageService
                                .instance
                                .upload(
                                  bucket: 'safiacademy-media',
                                  path: 'reels/$fileName',
                                  bytes: bytes,
                                  contentType: 'video/mp4',
                                );
                            urlController.text = publicUrl;
                            setModalState(() => isUploadingFile = false);
                          } catch (e) {
                            setModalState(() => isUploadingFile = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Storage Upload Error: $e'),
                                ),
                              );
                            }
                          }
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: primaryPink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primaryPink.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.video_library_rounded,
                        color: primaryPink,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isUploadingFile
                              ? 'Uploading video to Cloudflare... ⏳'
                              : (urlController.text.isNotEmpty
                                    ? 'Video Uploaded! ✅'
                                    : 'Select Video File from Gallery 🎥'),
                          style: const TextStyle(
                            color: primaryPink,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (isUploadingFile)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: primaryPink,
                            strokeWidth: 2,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  hintText: 'Video URL (or Cloudflare media link)',
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPink,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: isUploadingFile
                      ? null
                      : () async {
                          final user = supabase.auth.currentUser;
                          if (user == null ||
                              titleController.text.isEmpty ||
                              urlController.text.isEmpty) {
                            return;
                          }

                          try {
                            await supabase.from('reels').insert({
                              'user_id': user.id,
                              'title': titleController.text.trim(),
                              'video_url': urlController.text.trim(),
                              'category': uploadCategory,
                              'is_published': true,
                              'likes_count': 0,
                              'comments_count': 0,
                              'views_count': 0,
                              'created_at': DateTime.now().toIso8601String(),
                            });

                            if (mounted) {
                              Navigator.pop(context);
                              _fetchReels();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Reel published successfully! 🎉',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error uploading reel: $e'),
                                ),
                              );
                            }
                          }
                        },
                  child: const Text(
                    'PUBLISH REEL',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    return Scaffold(
      backgroundColor: Colors.black,
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryPink))
          : Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Desktop Left/Previous Button
                    if (isDesktop)
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: IconButton(
                          iconSize: 28,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.arrow_upward_rounded),
                          tooltip: "Previous Reel (Up Arrow)",
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                        ),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: isDesktop
                              ? BorderRadius.circular(24)
                              : BorderRadius.zero,
                          border: isDesktop
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  width: 1.5,
                                )
                              : null,
                          boxShadow: isDesktop
                              ? [
                                  BoxShadow(
                                    color: primaryPink.withValues(alpha: 0.2),
                                    blurRadius: 35,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // Display empty state if Friends tab has no content
                            if (selectedTab == 'friends' && reels.isEmpty)
                              _buildEmptyFriendsState()
                            else
                              RefreshIndicator(
                                color: primaryPink,
                                backgroundColor: Colors.black,
                                onRefresh: () async {
                                  await _fetchReels();
                                },
                                child: PageView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  controller: _pageController,
                                  scrollDirection: Axis.vertical,
                                  itemCount: AdService.instance
                                      .calculateTotalCount(
                                        reels.length,
                                        AdService.reelsAdInterval,
                                      ),
                                  onPageChanged: (index) {
                                    setState(() => activeIndex = index);
                                    if (!AdService.instance.isAdPosition(
                                      index,
                                      AdService.reelsAdInterval,
                                    )) {
                                      final rawIndex = AdService.instance
                                          .getRawItemIndex(
                                            index,
                                            AdService.reelsAdInterval,
                                          );
                                      if (rawIndex >= 0 &&
                                          rawIndex < reels.length) {
                                        _recordView(reels[rawIndex]);
                                      }
                                    }
                                  },
                                  itemBuilder: (context, index) {
                                    if (AdService.instance.isAdPosition(
                                      index,
                                      AdService.reelsAdInterval,
                                    )) {
                                      return const ReelsAdCard();
                                    }
                                    final rawIndex = AdService.instance
                                        .getRawItemIndex(
                                          index,
                                          AdService.reelsAdInterval,
                                        );
                                    if (rawIndex >= reels.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final reel = reels[rawIndex];
                                    return _buildReelPage(reel, index);
                                  },
                                ),
                              ),

                            // Top buttons: Friends | For You
                            _buildTopTabBar(),
                          ],
                        ),
                      ),
                    ),
                    // Desktop Right/Next Button
                    if (isDesktop)
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: IconButton(
                          iconSize: 28,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.arrow_downward_rounded),
                          tooltip: "Next Reel (Down Arrow)",
                          onPressed: () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  // Top tab bar
  Widget _buildTopTabBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Friends tab button
              GestureDetector(
                onTap: () {
                  final user = supabase.auth.currentUser;
                  if (user == null) {
                    AuthRequiredModal.show(
                      context,
                      actionName: "view friends' reels",
                    );
                    return;
                  }
                  if (selectedTab != 'friends') {
                    setState(() {
                      selectedTab = 'friends';
                      activeIndex = 0;
                      reels = allFriendsReels;
                    });
                    if (reels.isNotEmpty && widget.isActive) {
                      _recordView(reels.first);
                    }
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Friends',
                      style: TextStyle(
                        color: selectedTab == 'friends'
                            ? Colors.white
                            : Colors.white60,
                        fontSize: 16,
                        fontWeight: selectedTab == 'friends'
                            ? FontWeight.w900
                            : FontWeight.w600,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: selectedTab == 'friends'
                            ? primaryPink
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 14,
                width: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 18),
                color: Colors.white24,
              ),
              // For You (Explore) tab button
              GestureDetector(
                onTap: () {
                  if (selectedTab != 'for_you') {
                    setState(() {
                      selectedTab = 'for_you';
                      activeIndex = 0;
                      reels = allForYouReels;
                    });
                    if (reels.isNotEmpty && widget.isActive) {
                      _recordView(reels.first);
                    }
                  } else {
                    _fetchReels();
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'For You',
                      style: TextStyle(
                        color: selectedTab == 'for_you'
                            ? Colors.white
                            : Colors.white60,
                        fontSize: 16,
                        fontWeight: selectedTab == 'for_you'
                            ? FontWeight.w900
                            : FontWeight.w600,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: selectedTab == 'for_you'
                            ? primaryPink
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Empty state for Friends tab
  Widget _buildEmptyFriendsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryPink.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                color: primaryPink,
                size: 64,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Reels from Friends Yet 🤝',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Videos shared by your confirmed friends will appear in this section.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                setState(() {
                  selectedTab = 'for_you';
                  activeIndex = 0;
                  reels = allForYouReels;
                });
              },
              icon: const Icon(Icons.explore_rounded, size: 18),
              label: const Text(
                'Watch For You (Explore) 🔥',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReelPage(ReelItemData reel, int index) {
    return Stack(
      children: [
        // Video player with double-tap like support
        Positioned.fill(
          child: ReelVideoPlayerWidget(
            videoUrl: reel.videoUrl,
            thumbnailUrl: reel.thumbnailUrl,
            shouldPlay: widget.isActive && (activeIndex == index),
            onDoubleTap: () => _handleDoubleTapReel(reel),
          ),
        ),

        // Gradient shadow for readability
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Pop-up heart animation on double tap
        if (_activeHeartReelId == reel.id)
          Center(
            child: _InstagramHeartOverlay(
              key: ValueKey('heart_${reel.id}_$_heartAnimTrigger'),
              onAnimationComplete: () {
                if (mounted) {
                  setState(() {
                    _activeHeartReelId = null;
                  });
                }
              },
            ),
          ),

        // Author information and caption at bottom left
        Positioned(
          left: 16,
          bottom: 95,
          right: 90,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FastCircleAvatar(
                    imageUrl: reel.authorAvatar,
                    radius: 20,
                    fallbackText: reel.authorName.isNotEmpty
                        ? reel.authorName[0]
                        : 'A',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      reel.authorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _showReelsToast(context, "Following ${reel.authorName}");
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        border: Border.all(color: Colors.white, width: 1.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Follow',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                reel.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (reel.description != null &&
                  reel.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  reel.description!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),

        // Right action buttons (Like, Comment, Repost, Send, Save, Audio Disc)
        Positioned(
          right: 14,
          bottom: 100,
          child: Column(
            children: [
              // 1. Like
              GestureDetector(
                onTap: () => _toggleLikeReel(reel),
                child: Column(
                  children: [
                    Icon(
                      reel.isLikedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: reel.isLikedByMe ? primaryPink : Colors.white,
                      size: 30,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${reel.likesCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Comment
              GestureDetector(
                onTap: () => _openReelComments(reel),
                child: Column(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Colors.white,
                      size: 27,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${reel.commentsCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Repost
              GestureDetector(
                onTap: () {
                  _showReelsToast(context, "Reposted to your profile!");
                },
                child: const Column(
                  children: [
                    Icon(Icons.repeat_rounded, color: Colors.white, size: 28),
                    SizedBox(height: 3),
                    Text(
                      'Repost',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. Send to DM
              GestureDetector(
                onTap: () => _openShareModal(reel),
                child: const Column(
                  children: [
                    Icon(Icons.send_outlined, color: Colors.white, size: 25),
                    SizedBox(height: 3),
                    Text(
                      'Send',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 5. Bookmark / Save
              GestureDetector(
                onTap: () => _toggleSaveReel(reel),
                child: Column(
                  children: [
                    Icon(
                      reel.isSavedByMe
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: reel.isSavedByMe ? primaryPink : Colors.white,
                      size: 27,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Save',
                      style: TextStyle(
                        color: reel.isSavedByMe ? primaryPink : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 6. Download
              GestureDetector(
                onTap: () => _downloadReel(reel),
                child: const Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),

              // 7. Audio vinyl disc cover
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 2),
                  color: Colors.black87,
                  image:
                      (reel.thumbnailUrl != null &&
                          reel.thumbnailUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(reel.thumbnailUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (reel.thumbnailUrl == null || reel.thumbnailUrl!.isEmpty)
                    ? const Icon(
                        Icons.music_note_rounded,
                        color: Colors.white,
                        size: 16,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Share reel and send directly to friends sheet
class _ReelShareBottomSheet extends StatefulWidget {
  final ReelItemData reel;
  const _ReelShareBottomSheet({required this.reel});

  @override
  State<_ReelShareBottomSheet> createState() => _ReelShareBottomSheetState();
}

class _ReelShareBottomSheetState extends State<_ReelShareBottomSheet> {
  final supabase = Supabase.instance.client;
  bool isLoadingFriends = true;
  List<Map<String, dynamic>> friends = [];
  Set<String> sentFriendIds = {};

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  Future<void> _fetchFriends() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => isLoadingFriends = false);
      return;
    }

    try {
      final relations = await supabase
          .from('student_friends')
          .select('sender_id, receiver_id, status')
          .or('sender_id.eq.${user.id},receiver_id.eq.${user.id}')
          .eq('status', 'accepted');

      Set<String> friendIds = {};
      for (var r in (relations as List)) {
        final sId = r['sender_id']?.toString() ?? '';
        final rId = r['receiver_id']?.toString() ?? '';
        if (sId.isNotEmpty && sId != user.id) friendIds.add(sId);
        if (rId.isNotEmpty && rId != user.id) friendIds.add(rId);
      }

      if (friendIds.isNotEmpty) {
        final profs = await supabase
            .from('profiles')
            .select('id, first_name, last_name, avatar_url')
            .inFilter('id', friendIds.toList());
        if (mounted) {
          setState(() {
            friends = List<Map<String, dynamic>>.from(profs as List);
            isLoadingFriends = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoadingFriends = false);
      }
    } catch (e) {
      debugPrint('Error fetching friends for share: $e');
      if (mounted) setState(() => isLoadingFriends = false);
    }
  }

  Future<void> _sendToFriend(Map<String, dynamic> friend) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final friendId = friend['id']?.toString() ?? '';
    if (friendId.isEmpty || sentFriendIds.contains(friendId)) return;

    setState(() {
      sentFriendIds.add(friendId);
    });

    try {
      // Send via direct message
      await supabase.from('direct_messages').insert({
        'sender_id': user.id,
        'receiver_id': friendId,
        'message_text':
            '🎬 [Reel] ${widget.reel.title}\nhttps://zevapp.com/reel/${widget.reel.id}',
        'attachment_url': widget.reel.videoUrl,
        'attachment_type': 'reel',
        'is_delivered': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Send in-app notification to friend
      try {
        final myProfile = await supabase
            .from('profiles')
            .select('first_name, last_name')
            .eq('id', user.id)
            .maybeSingle();
        final myName = (myProfile != null)
            ? '${myProfile['first_name'] ?? 'Friend'} ${myProfile['last_name'] ?? ''}'
                  .trim()
            : 'A friend';

        await supabase.from('user_notifications').insert({
          'user_id': friendId,
          'sender_id': user.id,
          'title': '🎬 New Reel Shared',
          'message': '$myName shared a reel with you: "${widget.reel.title}"',
          'notification_type': 'direct_message',
          'link_url': '/chat/${user.id}',
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      if (mounted) {
        _showReelsToast(context, 'Video sent to friend 🚀');
      }
    } catch (e) {
      debugPrint('Error sending reel to friend: $e');
      if (mounted) {
        setState(() {
          sentFriendIds.remove(friendId);
        });
        _showReelsToast(context, 'Failed to send video', isError: true);
      }
    }
  }

  void _copyReelLink() {
    // Clean video URL:
    final pureLink = 'https://zevapp.com/reel/${widget.reel.id}';
    Clipboard.setData(ClipboardData(text: pureLink));
    Navigator.pop(context);
    _showReelsToast(context, 'Link copied to clipboard 📋');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Share Reel 🚀',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Share video or send directly to friends on ZEV Messenger',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),

          // Copy video link button
          GestureDetector(
            onTap: _copyReelLink,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: lightPinkBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primaryPink.withValues(alpha: 0.3),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: primaryPink,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Copy Reel Link',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'https://zevapp.com/reel/...',
                          style: TextStyle(
                            color: primaryPink,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.copy_rounded, color: primaryPink, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            'Send to Friends 💬',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),

          // Friends list
          SizedBox(
            height: 190,
            child: isLoadingFriends
                ? const Center(
                    child: CircularProgressIndicator(color: primaryPink),
                  )
                : friends.isEmpty
                ? Center(
                    child: Text(
                      'You haven\'t added any friends yet.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      final friendId = friend['id']?.toString() ?? '';
                      final isSent = sentFriendIds.contains(friendId);
                      final name =
                          '${friend['first_name'] ?? ''} ${friend['last_name'] ?? ''}'
                              .trim();
                      final avatar = friend['avatar_url'] ?? '';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: FastCircleAvatar(
                          imageUrl: avatar,
                          radius: 20,
                          fallbackText: name.isNotEmpty ? name[0] : 'F',
                        ),
                        title: Text(
                          name.isNotEmpty ? name : 'ZEV User',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSent
                                ? Colors.green
                                : primaryPink,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: isSent
                              ? null
                              : () => _sendToFriend(friend),
                          child: Text(
                            isSent ? 'Sent ✅' : 'Send',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// Reel comments with reel_comments table sync
class _ReelCommentsBottomSheet extends StatefulWidget {
  final String reelId;
  final ValueChanged<int>? onCommentAdded;

  const _ReelCommentsBottomSheet({required this.reelId, this.onCommentAdded});

  @override
  State<_ReelCommentsBottomSheet> createState() =>
      _ReelCommentsBottomSheetState();
}

class _ReelCommentsBottomSheetState extends State<_ReelCommentsBottomSheet> {
  final supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Map<String, dynamic>> comments = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchComments() async {
    try {
      final res = await supabase
          .from('reel_comments')
          .select('*, profiles:user_id(first_name, last_name, avatar_url)')
          .eq('reel_id', widget.reelId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          comments = List<Map<String, dynamic>>.from(res as List);
          isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _addComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "comment on reels");
      return;
    }

    _controller.clear();

    try {
      // 1. Record comment in reel_comments table
      await supabase.from('reel_comments').insert({
        'reel_id': widget.reelId,
        'user_id': user.id,
        'comment_text': text,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. Recount comments and update reels table
      final countRes = await supabase
          .from('reel_comments')
          .select('id')
          .eq('reel_id', widget.reelId);
      final realCommentsCount = (countRes as List).length;

      await supabase
          .from('reels')
          .update({'comments_count': realCommentsCount})
          .eq('id', widget.reelId);

      widget.onCommentAdded?.call(realCommentsCount);

      // 3. Send reel comment notification
      try {
        final reelData = await supabase
            .from('reels')
            .select('user_id, title')
            .eq('id', widget.reelId)
            .maybeSingle();

        if (reelData != null) {
          final authorId = reelData['user_id']?.toString() ?? '';
          final reelTitle = reelData['title'] ?? 'your reel';
          if (authorId.isNotEmpty && authorId != user.id) {
            final senderProfile = await supabase
                .from('profiles')
                .select('first_name, last_name')
                .eq('id', user.id)
                .maybeSingle();
            final String senderName = (senderProfile != null)
                ? '${senderProfile['first_name'] ?? 'Someone'} ${senderProfile['last_name'] ?? ''}'
                      .trim()
                : 'Someone';

            await supabase.from('user_notifications').insert({
              'user_id': authorId,
              'sender_id': user.id,
              'title': '💬 Comment on your Reel',
              'message': '$senderName commented on "$reelTitle": "$text"',
              'notification_type': 'comment',
              'link_url': '/reel/${widget.reelId}',
              'is_read': false,
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        }
      } catch (_) {}

      _fetchComments();
    } catch (_) {}
  }

  void _replyToUser(String username) {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "reply to comments");
      return;
    }
    setState(() {
      _controller.text = '@$username ${_controller.text}';
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Comments 💬',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const Divider(),
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFC466B),
                      ),
                    )
                  : comments.isEmpty
                  ? const Center(
                      child: Text(
                        'Be the first to comment!',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final c = comments[index];
                        final profile = c['profiles'];
                        final String authorName = (profile != null)
                            ? '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
                                  .trim()
                            : 'ZEV User';
                        final String avatarUrl = (profile != null)
                            ? (profile['avatar_url'] ?? '')
                            : '';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFFFAF4F6),
                            backgroundImage: avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    authorName.isNotEmpty ? authorName[0] : 'S',
                                    style: const TextStyle(
                                      color: Color(0xFFFC466B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            authorName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              c['comment_text'] ?? '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                          trailing: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _replyToUser(authorName),
                            child: const Text(
                              'Reply',
                              style: TextStyle(
                                color: Color(0xFFFC466B),
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Write a comment...',
                        hintStyle: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Color(0xFFFC466B),
                    ),
                    onPressed: _addComment,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Local video cache manager in temporary directory
class ReelCacheManager {
  static final ReelCacheManager instance = ReelCacheManager._internal();
  ReelCacheManager._internal();

  final Dio _dio = Dio();
  final Set<String> _inProgressDownloads = {};
  Directory? _cacheDir;

  Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/reels_session_cache');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  String _getCacheFilename(String url) {
    final uri = Uri.tryParse(url);
    final lastSegment = uri?.pathSegments.lastOrNull ?? 'video';
    final cleanSegment = lastSegment.replaceAll(
      RegExp(r'[^a-zA-Z0-9_\-\.]'),
      '',
    );
    final urlHash = url.codeUnits
        .fold<int>(0, (prev, elem) => ((prev << 5) - prev + elem) & 0xFFFFFFFF)
        .abs()
        .toString();
    return 'reel_${urlHash}_$cleanSegment';
  }

  Future<File?> getCachedFile(String url) async {
    if (kIsWeb) return null;
    try {
      final dir = await _getCacheDirectory();
      final filename = _getCacheFilename(url);
      final file = File('${dir.path}/$filename');
      if (await file.exists() && (await file.length()) > 50000) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  void cacheVideoInBackground(String url) {
    if (kIsWeb) return;
    if (_inProgressDownloads.contains(url)) return;
    _inProgressDownloads.add(url);

    Future.microtask(() async {
      try {
        final dir = await _getCacheDirectory();
        final filename = _getCacheFilename(url);
        final targetFile = File('${dir.path}/$filename');
        if (await targetFile.exists() && (await targetFile.length()) > 50000) {
          _inProgressDownloads.remove(url);
          return;
        }

        final partFile = File('${dir.path}/$filename.part');
        await _dio.download(
          url,
          partFile.path,
          options: Options(
            receiveTimeout: const Duration(seconds: 45),
            sendTimeout: const Duration(seconds: 20),
          ),
        );

        if (await partFile.exists() && (await partFile.length()) > 50000) {
          await partFile.rename(targetFile.path);
          debugPrint(
            "Successfully cached reel video to temp: ${targetFile.path}",
          );
        } else if (await partFile.exists()) {
          await partFile.delete();
        }
      } catch (e) {
        debugPrint("Background reel cache download error: $e");
      } finally {
        _inProgressDownloads.remove(url);
      }
    });
  }
}

class ReelVideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final bool shouldPlay;
  final VoidCallback? onDoubleTap;

  const ReelVideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.shouldPlay,
    this.onDoubleTap,
  });

  @override
  State<ReelVideoPlayerWidget> createState() => _ReelVideoPlayerWidgetState();
}

class _ReelVideoPlayerWidgetState extends State<ReelVideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showPlayPauseIcon = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final cachedFile = await ReelCacheManager.instance.getCachedFile(
        widget.videoUrl,
      );
      if (cachedFile != null) {
        debugPrint("Playing reel from local cache: ${cachedFile.path}");
        _controller = VideoPlayerController.file(cachedFile);
      } else {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
        ReelCacheManager.instance.cacheVideoInBackground(widget.videoUrl);
      }

      await _controller.initialize();
      _controller.setLooping(true);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        if (widget.shouldPlay) {
          _controller.play();
          setState(() {
            _isPlaying = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
    }
  }

  @override
  void didUpdateWidget(covariant ReelVideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isInitialized) return;
    if (widget.shouldPlay != oldWidget.shouldPlay) {
      if (widget.shouldPlay) {
        _controller.play();
        setState(() {
          _isPlaying = true;
        });
      } else {
        _controller.pause();
        _controller.seekTo(Duration.zero);
        setState(() {
          _isPlaying = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
      _showPlayPauseIcon = true;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showPlayPauseIcon = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
              Positioned.fill(
                child: Image.network(
                  widget.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              ),
            const CircularProgressIndicator(
              color: Color(0xFFFC466B),
              strokeWidth: 3,
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlayPause,
      onDoubleTap: widget.onDoubleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Ambient background layer: fills screen with subtle darkened video backdrop
                  Positioned.fill(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller.value.size.width,
                        height: _controller.value.size.height,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.75),
                    ),
                  ),
                  // Foreground player: 100% visible, never zoomed or cropped at the edges
                  Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _controller.value.size.width,
                        height: _controller.value.size.height,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showPlayPauseIcon)
            AnimatedOpacity(
              opacity: _showPlayPauseIcon ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
