import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/content_deletion_service.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../feed/models/feed_post_item.dart';
import '../../feed/screens/create_post_screen.dart';
import '../../feed/screens/drafts_scheduled_screen.dart';
import '../../feed/screens/post_detail_screen.dart';
import '../../ads/screens/ads_manager_screen.dart';
import '../../live/screens/live_rooms_screen.dart';
import '../../reels/models/reel_item.dart';
import '../../reels/screens/create_reel_screen.dart';
import '../../reels/widgets/reel_player_item.dart';
import '../../stories/screens/create_story_screen.dart';
import '../../stories/screens/story_viewer_screen.dart';
import '../models/story_highlight_model.dart';
import '../services/story_highlight_service.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../widgets/appeal_restriction_sheet.dart';
import '../widgets/create_highlight_sheet.dart';
import '../widgets/highlight_viewer_screen.dart';
import 'user_follows_screen.dart';
import '../widgets/video_cover_thumbnail.dart';
import '../../chat/screens/chat_conversation_screen.dart';
import '../../discover/screens/discover_screen.dart';
import 'edit_profile_screen.dart';
import 'creator_insights_screen.dart';
import 'profile_settings_screen.dart';
import 'share_profile_screen.dart';

/// Next-Generation Claymorphic Profile Screen for ZEV Social Network.
/// Engineered with tactile 3D elevated clay surfaces, multi-layer shadows,
/// live real-time Supabase telemetry, zero demo/mock data, and full highlights integration.
class ProfileScreen extends StatefulWidget {
  final String? userId;
  final VoidCallback? onExit;

  const ProfileScreen({super.key, this.userId, this.onExit});

  static Future<void> open(BuildContext context, {required String userId}) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProfileScreen(userId: userId),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  Map<String, dynamic> _profile = {};

  // Real Database Lists
  List<FeedPostItem> _userPosts = [];
  List<ReelItem> _userReels = [];
  List<FeedPostItem> _userReposts = [];
  List<FeedPostItem> _userSavedPosts = [];
  List<ReelItem> _userSavedReels = [];
  List<Map<String, dynamic>> _userLinks = [];

  int _followersCount = 0;
  int _followingCount = 0;
  int _pendingRequestsCount = 0;
  bool _isFollowing = false;
  bool _followRequested = false;
  bool _isFollowLoading = false;

  // Visitor privacy & safety policy
  Map<String, dynamic>? _interactionPolicy;
  bool _isBlockedView = false;
  bool _blockedByMe = false;
  bool _canViewContent = true;

  // Active Story
  bool _hasActiveStory = false;
  ActiveFriendStory? _activeStory;

  // Suggested creators
  bool _showSuggestedCreators = false;
  List<Map<String, dynamic>> _suggestedCreators = [];
  final Set<String> _followedSuggestedIds = {};
  final Set<String> _requestedSuggestedIds = {};

  // Real User Highlights
  List<StoryHighlight> _highlights = [];
  bool _isLoadingHighlights = true;

  // Tabs: 0: Posts, 1: Reels, 2: Reposts, 3: Saved (Owner only)
  late final TabController _tabCtrl;

  String get _targetUserId =>
      widget.userId ?? supabase.auth.currentUser?.id ?? '';
  bool get _isMyProfile {
    final currentId = supabase.auth.currentUser?.id;
    return currentId != null && currentId == _targetUserId;
  }

  bool _hasActiveRestrictionStanding() {
    if (_profile['is_restricted'] != true) return false;
    final untilRaw = _profile['restricted_until']?.toString();
    if (untilRaw != null && untilRaw.trim().isNotEmpty) {
      final dt = DateTime.tryParse(untilRaw)?.toUtc();
      if (dt != null && !dt.isAfter(DateTime.now().toUtc())) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _isMyProfile ? 4 : 3, vsync: this);
    _loadAllProfileData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllProfileData() async {
    if (_targetUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      await _fetchProfile();

      if (!_isMyProfile) {
        final policy = await SocialGraphService.instance.getInteractionPolicy(
          _targetUserId,
        );
        final isBlocked = policy['is_blocked'] == true;
        final canView = policy['can_view_content'] != false && !isBlocked;
        bool blockedByMe = false;
        if (isBlocked) {
          final me = supabase.auth.currentUser?.id;
          if (me != null) {
            try {
              final row = await supabase
                  .from('user_blocks')
                  .select('blocked_id')
                  .eq('blocker_id', me)
                  .eq('blocked_id', _targetUserId)
                  .maybeSingle();
              blockedByMe = row != null;
            } catch (_) {}
          }
        }
        if (mounted) {
          setState(() {
            _interactionPolicy = policy;
            _isBlockedView = isBlocked;
            _blockedByMe = blockedByMe;
            _canViewContent = canView;
            _isFollowing = policy['is_following'] == true;
            _followRequested = policy['is_pending_request'] == true;
          });
        }
        if (isBlocked) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      } else {
        if (mounted) {
          setState(() {
            _interactionPolicy = null;
            _isBlockedView = false;
            _blockedByMe = false;
            _canViewContent = true;
            _isFollowing = false;
            _followRequested = false;
          });
        }
      }

      await Future.wait([
        _fetchFollowCounts(),
        _fetchUserLinks(),
        if (_isMyProfile) _fetchPendingRequestCount(),
        if (_isMyProfile || _canViewContent) ...[
          _fetchPosts(),
          _fetchReels(),
          _fetchActiveStory(),
          _loadHighlights(),
          _fetchReposts(),
        ],
        if (_isMyProfile) ...[
          _fetchSavedPosts(),
          _fetchSuggestedCreators(),
        ],
      ]);

      if (!_isMyProfile && !_canViewContent && mounted) {
        setState(() {
          _userPosts = [];
          _userReels = [];
          _userReposts = [];
          _hasActiveStory = false;
          _activeStory = null;
          _highlights = [];
          _isLoadingHighlights = false;
        });
      }
    } catch (e) {
      debugPrint("Profile load warning: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPendingRequestCount() async {
    final cnt = await SocialGraphService.instance.fetchPendingRequestCount();
    if (mounted) setState(() => _pendingRequestsCount = cnt);
  }

  Future<void> _fetchUserLinks() async {
    try {
      final res = await supabase
          .from('user_links')
          .select('id, title, url, sort_order')
          .eq('user_id', _targetUserId)
          .order('sort_order', ascending: true);
      if (mounted) {
        setState(() {
          _userLinks = List<Map<String, dynamic>>.from(res as List);
        });
      }
    } catch (e) {
      debugPrint("Fetch user links error: $e");
    }
  }

  Future<void> _launchExternalLink(String rawUrl) async {
    var trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Launch external link notice: $e");
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final res = await supabase
          .from('profiles')
          .select()
          .eq('id', _targetUserId)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() => _profile = Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint("Fetch profile error: $e");
    }
  }

  Future<void> _fetchFollowCounts() async {
    final currentUserId = supabase.auth.currentUser?.id;
    try {
      final followersRes = await supabase
          .from('user_follows')
          .select('follower_id')
          .eq('following_id', _targetUserId);

      final followingRes = await supabase
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', _targetUserId);

      final followersList = followersRes as List;
      final followingList = followingRes as List;

      bool isFollowingMe = false;
      if (currentUserId != null && !_isMyProfile) {
        isFollowingMe = followersList.any(
          (r) => r['follower_id']?.toString() == currentUserId,
        );
      }

      if (mounted) {
        setState(() {
          _followersCount = followersList.length;
          _followingCount = followingList.length;
          _isFollowing = isFollowingMe;
        });
      }
    } catch (e) {
      debugPrint("Follow counts error: $e");
    }
  }

  Future<void> _fetchActiveStory() async {
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final res = await supabase
          .from('user_stories')
          .select('id, user_id, media_url, media_type, caption, expires_at')
          .eq('user_id', _targetUserId)
          .isFilter('deleted_at', null)
          .gt('expires_at', nowStr)
          .order('created_at', ascending: false);

      final list = res as List;
      if (mounted) {
        setState(() {
          _hasActiveStory = list.isNotEmpty;
          if (_hasActiveStory) {
            _activeStory = ActiveFriendStory(
              userId: _targetUserId,
              username: _profile['username'] ?? 'user',
              avatarUrl: _profile['avatar_url'] ?? '',
              storiesCount: list.length,
            );
          } else {
            _activeStory = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Fetch active story error: $e");
    }
  }

  Future<void> _loadHighlights() async {
    if (_targetUserId.isEmpty) return;
    try {
      final list = await StoryHighlightService().loadHighlights(_targetUserId);
      if (mounted) {
        setState(() {
          _highlights = list;
          _isLoadingHighlights = false;
        });
      }
    } catch (e) {
      debugPrint("Load highlights error: $e");
      if (mounted) setState(() => _isLoadingHighlights = false);
    }
  }

  Future<Map<String, List<FeedPostMediaItem>>> _fetchPostMediaMap(
    Iterable<String> postIds,
  ) async {
    final ids = postIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final res = await supabase
          .from('post_media')
          .select()
          .inFilter('post_id', ids)
          .order('sort_order', ascending: true);
      final map = <String, List<FeedPostMediaItem>>{};
      for (final row in (res as List)) {
        if (row is Map) {
          final m = Map<String, dynamic>.from(row);
          final pid = m['post_id']?.toString() ?? '';
          final item = FeedPostMediaItem.fromMap(m);
          if (pid.isNotEmpty && item.mediaUrl.trim().isNotEmpty) {
            map.putIfAbsent(pid, () => []).add(item);
          }
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _fetchPosts() async {
    final currentUserId = supabase.auth.currentUser?.id;
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final res = await supabase
          .from('discussion_posts')
          .select()
          .eq('student_id', _targetUserId)
          .isFilter('deleted_at', null)
          .eq('is_draft', false)
          .or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
          .order('created_at', ascending: false);

      final postRows = List<Map<String, dynamic>>.from(res as List);
      final postIds = postRows.map((p) => p['id'].toString()).toList();
      final bookmarkedIds = <String>{};
      final likedIds = <String>{};
      final repostedIds = <String>{};
      final mediaMap = await _fetchPostMediaMap(postIds);

      if (currentUserId != null && postIds.isNotEmpty) {
        try {
          final [bmRes, lkRes, rpRes] = await Future.wait([
            supabase
                .from('discussion_bookmarks')
                .select('post_id')
                .eq('user_id', currentUserId)
                .inFilter('post_id', postIds),
            supabase
                .from('discussion_likes')
                .select('post_id')
                .eq('student_id', currentUserId)
                .inFilter('post_id', postIds),
            supabase
                .from('post_reposts')
                .select('post_id')
                .eq('user_id', currentUserId)
                .inFilter('post_id', postIds),
          ]);
          for (final row in (bmRes as List)) {
            bookmarkedIds.add(row['post_id'].toString());
          }
          for (final row in (lkRes as List)) {
            likedIds.add(row['post_id'].toString());
          }
          for (final row in (rpRes as List)) {
            repostedIds.add(row['post_id'].toString());
          }
        } catch (_) {}
      }

      final list = postRows.map((p) {
        final id = p['id'].toString();
        final title = (p['title'] ?? '').toString();
        String catTag = 'Explore';
        if (title.contains('[') && title.contains(']')) {
          final start = title.indexOf('[');
          final end = title.indexOf(']');
          if (end > start) {
            catTag = title.substring(start + 1, end).trim();
          }
        }
        final items = mediaMap[id] ?? const <FeedPostMediaItem>[];
        var primaryUrl = (p['image_url'] ?? '').toString();
        if (primaryUrl.isEmpty && items.isNotEmpty) {
          primaryUrl = items.first.mediaUrl;
        }
        return FeedPostItem(
          id: id,
          authorId: _targetUserId,
          authorUsername: _profile['username'] ?? 'user',
          authorFullName:
              "${_profile['first_name'] ?? ''} ${_profile['last_name'] ?? ''}"
                  .trim(),
          authorAvatar: _profile['avatar_url'] ?? '',
          isVerified: _profile['is_verified'] == true,
          title: title,
          content: p['content'] ?? '',
          imageUrl: primaryUrl,
          mediaItems: items,
          location: (p['location'] ?? '').toString(),
          editedAt: p['edited_at'] != null
              ? DateTime.tryParse(p['edited_at'].toString())
              : null,
          createdAt:
              DateTime.tryParse(p['created_at'].toString()) ?? DateTime.now(),
          categoryTag: catTag,
          likesCount: (p['likes_count'] as num?)?.toInt() ?? 0,
          isLikedByMe: likedIds.contains(id),
          commentsCount: (p['comments_count'] as num?)?.toInt() ?? 0,
          repostsCount: (p['reposts_count'] as num?)?.toInt() ?? 0,
          isRepostedByMe: repostedIds.contains(id),
          isBookmarkedByMe: bookmarkedIds.contains(id),
        );
      }).toList();

      if (mounted) setState(() => _userPosts = list);
    } catch (e) {
      debugPrint("Fetch user posts error: $e");
    }
  }

  Future<void> _fetchReels() async {
    final currentUserId = supabase.auth.currentUser?.id;
    try {
      final res = await supabase
          .from('reels')
          .select()
          .eq('user_id', _targetUserId)
          .isFilter('deleted_at', null)
          .eq('is_published', true)
          .order('created_at', ascending: false);

      final reelRows = List<Map<String, dynamic>>.from(res as List);
      final reelIds = reelRows.map((r) => r['id'].toString()).toList();
      final likedIds = <String>{};
      final bookmarkedIds = <String>{};

      if (currentUserId != null && reelIds.isNotEmpty) {
        try {
          final [lkRes, bmRes] = await Future.wait([
            supabase
                .from('reel_likes')
                .select('reel_id')
                .eq('user_id', currentUserId)
                .inFilter('reel_id', reelIds),
            supabase
                .from('reel_bookmarks')
                .select('reel_id')
                .eq('user_id', currentUserId)
                .inFilter('reel_id', reelIds),
          ]);
          for (final row in (lkRes as List)) {
            likedIds.add(row['reel_id'].toString());
          }
          for (final row in (bmRes as List)) {
            bookmarkedIds.add(row['reel_id'].toString());
          }
        } catch (_) {}
      }

      final list = reelRows.map((r) {
        final id = r['id'].toString();
        return ReelItem(
          id: id,
          userId: _targetUserId,
          authorUsername: _profile['username'] ?? 'user',
          authorFullName:
              "${_profile['first_name'] ?? ''} ${_profile['last_name'] ?? ''}"
                  .trim(),
          authorAvatar: _profile['avatar_url'] ?? '',
          isVerified: _profile['is_verified'] == true,
          videoUrl: r['video_url'] ?? '',
          thumbnailUrl: r['thumbnail_url'],
          title: r['title'] ?? '',
          description: r['description'] ?? '',
          category: r['category'] ?? 'Social',
          durationSeconds: (r['duration_seconds'] as num?)?.toInt() ?? 15,
          viewsCount: (r['views_count'] as num?)?.toInt() ?? 0,
          likesCount: (r['likes_count'] as num?)?.toInt() ?? 0,
          isLikedByMe: likedIds.contains(id),
          commentsCount: (r['comments_count'] as num?)?.toInt() ?? 0,
          isBookmarkedByMe: bookmarkedIds.contains(id),
          isAuthorFollowed: _isFollowing,
          createdAt:
              DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now(),
        );
      }).toList();

      if (mounted) setState(() => _userReels = list);
    } catch (e) {
      debugPrint("Fetch user reels error: $e");
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfilesMap(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final res = await supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .inFilter('id', ids);
      final map = <String, Map<String, dynamic>>{};
      for (final p in (res as List)) {
        final m = Map<String, dynamic>.from(p as Map);
        map[m['id'].toString()] = m;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _fetchReposts() async {
    try {
      final res = await supabase
          .from('post_reposts')
          .select('post_id')
          .eq('user_id', _targetUserId);

      final postIds = (res as List)
          .map((r) => r['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (postIds.isEmpty) {
        if (mounted) setState(() => _userReposts = []);
        return;
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final postsRes = await supabase
          .from('discussion_posts')
          .select()
          .inFilter('id', postIds)
          .isFilter('deleted_at', null)
          .eq('is_draft', false)
          .or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(postsRes as List);
      final profilesMap = await _fetchProfilesMap(
        rows.map((p) => p['student_id']?.toString() ?? ''),
      );
      final mediaMap = await _fetchPostMediaMap(
        rows.map((p) => p['id'].toString()),
      );

      final list = rows.map((p) {
        final id = p['id'].toString();
        final authorId = p['student_id']?.toString() ?? '';
        final prof = profilesMap[authorId] ?? const <String, dynamic>{};
        final fn = (prof['first_name'] ?? '').toString().trim();
        final ln = (prof['last_name'] ?? '').toString().trim();
        final full = "$fn $ln".trim();
        final uname = (prof['username'] ?? 'user').toString();
        final items = mediaMap[id] ?? const <FeedPostMediaItem>[];
        var primaryUrl = (p['image_url'] ?? '').toString();
        if (primaryUrl.isEmpty && items.isNotEmpty) {
          primaryUrl = items.first.mediaUrl;
        }

        return FeedPostItem(
          id: id,
          authorId: authorId,
          authorUsername: uname,
          authorFullName: full.isNotEmpty ? full : '@$uname',
          authorAvatar: (prof['avatar_url'] ?? '').toString(),
          isVerified: prof['is_verified'] == true,
          title: p['title'] ?? '',
          content: p['content'] ?? '',
          imageUrl: primaryUrl,
          mediaItems: items,
          location: (p['location'] ?? '').toString(),
          editedAt: p['edited_at'] != null
              ? DateTime.tryParse(p['edited_at'].toString())
              : null,
          createdAt:
              DateTime.tryParse(p['created_at'].toString()) ?? DateTime.now(),
          likesCount: (p['likes_count'] as num?)?.toInt() ?? 0,
          isLikedByMe: false,
          commentsCount: (p['comments_count'] as num?)?.toInt() ?? 0,
          repostsCount: (p['reposts_count'] as num?)?.toInt() ?? 0,
          isRepostedByMe: true,
        );
      }).toList();

      if (mounted) setState(() => _userReposts = list);
    } catch (e) {
      debugPrint("Fetch reposts error: $e");
    }
  }

  Future<void> _fetchSavedPosts() async {
    try {
      final [postBmRes, reelBmRes] = await Future.wait([
        supabase
            .from('discussion_bookmarks')
            .select('post_id')
            .eq('user_id', _targetUserId)
            .order('created_at', ascending: false),
        supabase
            .from('reel_bookmarks')
            .select('reel_id')
            .eq('user_id', _targetUserId)
            .order('created_at', ascending: false),
      ]);

      final postIds = (postBmRes as List)
          .map((r) => r['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final reelIds = (reelBmRes as List)
          .map((r) => r['reel_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      List<FeedPostItem> savedPosts = [];
      if (postIds.isNotEmpty) {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final postsRes = await supabase
            .from('discussion_posts')
            .select()
            .inFilter('id', postIds)
            .isFilter('deleted_at', null)
            .eq('is_draft', false)
            .or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
            .order('created_at', ascending: false);

        final pRows = List<Map<String, dynamic>>.from(postsRes as List);
        final pProfiles = await _fetchProfilesMap(
          pRows.map((p) => p['student_id']?.toString() ?? ''),
        );
        final pMedia = await _fetchPostMediaMap(
          pRows.map((p) => p['id'].toString()),
        );

        savedPosts = pRows.map((p) {
          final id = p['id'].toString();
          final authorId = p['student_id']?.toString() ?? '';
          final prof = pProfiles[authorId] ?? const <String, dynamic>{};
          final fn = (prof['first_name'] ?? '').toString().trim();
          final ln = (prof['last_name'] ?? '').toString().trim();
          final full = "$fn $ln".trim();
          final uname = (prof['username'] ?? 'user').toString();
          final items = pMedia[id] ?? const <FeedPostMediaItem>[];
          var primaryUrl = (p['image_url'] ?? '').toString();
          if (primaryUrl.isEmpty && items.isNotEmpty) {
            primaryUrl = items.first.mediaUrl;
          }

          return FeedPostItem(
            id: id,
            authorId: authorId,
            authorUsername: uname,
            authorFullName: full.isNotEmpty ? full : '@$uname',
            authorAvatar: (prof['avatar_url'] ?? '').toString(),
            isVerified: prof['is_verified'] == true,
            title: p['title'] ?? '',
            content: p['content'] ?? '',
            imageUrl: primaryUrl,
            mediaItems: items,
            location: (p['location'] ?? '').toString(),
            editedAt: p['edited_at'] != null
                ? DateTime.tryParse(p['edited_at'].toString())
                : null,
            createdAt:
                DateTime.tryParse(p['created_at'].toString()) ?? DateTime.now(),
            likesCount: (p['likes_count'] as num?)?.toInt() ?? 0,
            isLikedByMe: false,
            commentsCount: (p['comments_count'] as num?)?.toInt() ?? 0,
            repostsCount: (p['reposts_count'] as num?)?.toInt() ?? 0,
            isBookmarkedByMe: true,
          );
        }).toList();
      }

      List<ReelItem> savedReels = [];
      if (reelIds.isNotEmpty) {
        final reelsRes = await supabase
            .from('reels')
            .select()
            .inFilter('id', reelIds)
            .isFilter('deleted_at', null)
            .eq('is_published', true)
            .order('created_at', ascending: false);

        final rRows = List<Map<String, dynamic>>.from(reelsRes as List);
        final rProfiles = await _fetchProfilesMap(
          rRows.map((r) => r['user_id']?.toString() ?? ''),
        );

        savedReels = rRows.map((r) {
          final authorId = r['user_id']?.toString() ?? '';
          final prof = rProfiles[authorId] ?? const <String, dynamic>{};
          final fn = (prof['first_name'] ?? '').toString().trim();
          final ln = (prof['last_name'] ?? '').toString().trim();
          final full = "$fn $ln".trim();
          final uname = (prof['username'] ?? 'user').toString();

          return ReelItem(
            id: r['id'].toString(),
            userId: authorId,
            authorUsername: uname,
            authorFullName: full.isNotEmpty ? full : '@$uname',
            authorAvatar: (prof['avatar_url'] ?? '').toString(),
            isVerified: prof['is_verified'] == true,
            videoUrl: r['video_url'] ?? '',
            thumbnailUrl: r['thumbnail_url'],
            title: r['title'] ?? '',
            description: r['description'] ?? '',
            category: r['category'] ?? 'Social',
            durationSeconds: (r['duration_seconds'] as num?)?.toInt() ?? 15,
            viewsCount: (r['views_count'] as num?)?.toInt() ?? 0,
            likesCount: (r['likes_count'] as num?)?.toInt() ?? 0,
            isLikedByMe: false,
            commentsCount: (r['comments_count'] as num?)?.toInt() ?? 0,
            isBookmarkedByMe: true,
            createdAt:
                DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now(),
          );
        }).toList();
      }

      if (mounted) {
        setState(() {
          _userSavedPosts = savedPosts;
          _userSavedReels = savedReels;
        });
      }
    } catch (e) {
      debugPrint("Fetch saved posts/reels error: $e");
    }
  }

  Future<void> _fetchSuggestedCreators() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    try {
      final [filters, followingRows, reqRows, res] = await Future.wait<dynamic>([
        SocialGraphService.instance.fetchSafetyFilters(),
        supabase
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', currentUserId),
        supabase
            .from('follow_requests')
            .select('target_id')
            .eq('requester_id', currentUserId)
            .eq('status', 'pending'),
        supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified',
            )
            .neq('id', currentUserId)
            .limit(20),
      ]);

      final safety = filters as UserSafetyFilters;
      final alreadyFollowed = (followingRows as List)
          .map((r) => r['following_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final pendingReq = (reqRows as List)
          .map((r) => r['target_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final list = (res as List)
          .where((p) {
            final id = p['id'].toString();
            return id != currentUserId &&
                !alreadyFollowed.contains(id) &&
                !safety.blockedUserIds.contains(id);
          })
          .take(8)
          .map((p) {
            final fn = p['first_name'] ?? '';
            final ln = p['last_name'] ?? '';
            final full = "$fn $ln".trim();
            return {
              'id': p['id'].toString(),
              'username': p['username'] ?? 'user',
              'name': full.isNotEmpty ? full : (p['username'] ?? 'User'),
              'avatar_url': p['avatar_url'] ?? '',
              'is_verified': p['is_verified'] == true,
            };
          })
          .toList();

      if (mounted) {
        setState(() {
          _followedSuggestedIds
            ..clear()
            ..addAll(alreadyFollowed);
          _requestedSuggestedIds
            ..clear()
            ..addAll(pendingReq);
          _suggestedCreators = list;
        });
      }
    } catch (e) {
      debugPrint("Suggested creators error: $e");
    }
  }

  Future<void> _toggleFollow() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || _isFollowLoading || _isBlockedView) return;

    HapticFeedback.lightImpact();
    setState(() => _isFollowLoading = true);

    final status = await SocialGraphService.instance.toggleFollow(_targetUserId);
    if (!mounted) return;

    switch (status) {
      case FollowToggleStatus.following:
        setState(() {
          _isFollowing = true;
          _followRequested = false;
          _followersCount += 1;
          _isFollowLoading = false;
        });
        await _loadAllProfileData();
        break;
      case FollowToggleStatus.unfollowed:
        setState(() {
          _isFollowing = false;
          _followRequested = false;
          _followersCount = _followersCount > 0 ? _followersCount - 1 : 0;
          _isFollowLoading = false;
        });
        await _loadAllProfileData();
        break;
      case FollowToggleStatus.requested:
        setState(() {
          _isFollowing = false;
          _followRequested = true;
          _isFollowLoading = false;
        });
        break;
      case FollowToggleStatus.cancelled:
        setState(() {
          _isFollowing = false;
          _followRequested = false;
          _isFollowLoading = false;
        });
        break;
      case FollowToggleStatus.blocked:
        setState(() => _isFollowLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unable to follow this user.")),
        );
        break;
      case FollowToggleStatus.error:
        setState(() => _isFollowLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not update follow status.")),
        );
        break;
    }
  }

  // Navigation & Bottom Sheets
  void _openCreateMenu() {
    HapticFeedback.lightImpact();
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = MediaQuery.of(context).size.width < 380;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.95),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              isCompact ? 16 : 20,
              14,
              isCompact ? 16 : 20,
              20 + bottomPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 3D Clay Drag Handle
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.white,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Title Header with Clay Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Create",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                        letterSpacing: -0.4,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      behavior: HitTestBehavior.opaque,
                      child: _buildClayCard(
                        borderRadius: 12,
                        depth: 2.5,
                        padding: const EdgeInsets.all(6),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: ZevColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 1. Post Option Tile
                _buildClayCreateTile(
                  icon: Icons.grid_on_rounded,
                  iconGradient: const LinearGradient(
                    colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  title: "Post",
                  subtitle: "Share photo or thought to feed",
                  isCompact: isCompact,
                  onTap: () {
                    Navigator.pop(ctx);
                    CreatePostScreen.open(
                      context,
                      onPostCreated: _loadAllProfileData,
                    );
                  },
                ),
                SizedBox(height: isCompact ? 8 : 10),

                // 2. Reel Option Tile
                _buildClayCreateTile(
                  icon: Icons.video_collection_rounded,
                  iconGradient: const LinearGradient(
                    colors: [Color(0xFFFF0080), Color(0xFF7928CA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  title: "Reel",
                  subtitle: "Record or upload short video",
                  isCompact: isCompact,
                  onTap: () {
                    Navigator.pop(ctx);
                    CreateReelScreen.open(
                      context,
                      onReelCreated: _loadAllProfileData,
                    );
                  },
                ),
                SizedBox(height: isCompact ? 8 : 10),

                // 3. Story Option Tile
                _buildClayCreateTile(
                  icon: Icons.flash_on_rounded,
                  iconGradient: const LinearGradient(
                    colors: [Color(0xFFFBAA47), Color(0xFFD91A46)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  title: "Story",
                  subtitle: "24-hour disappearing moment",
                  isCompact: isCompact,
                  onTap: () {
                    Navigator.pop(ctx);
                    CreateStoryScreen.open(
                      context,
                      onStoryCreated: _loadAllProfileData,
                    );
                  },
                ),
                SizedBox(height: isCompact ? 8 : 10),

                // 4. Story Highlight Option Tile
                _buildClayCreateTile(
                  icon: Icons.auto_awesome_rounded,
                  iconGradient: const LinearGradient(
                    colors: [Color(0xFF536DFE), Color(0xFF00D4FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  title: "Story Highlight",
                  subtitle: "Pin past stories or new media to profile",
                  isCompact: isCompact,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openCreateHighlightSheet();
                  },
                ),
                SizedBox(height: isCompact ? 8 : 10),

                // 5. Drafts & Scheduled Posts Tile
                _buildClayCreateTile(
                  icon: Icons.schedule_send_rounded,
                  iconGradient: const LinearGradient(
                    colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  title: "Drafts & Scheduled",
                  subtitle: "Review saved drafts or upcoming scheduled posts",
                  isCompact: isCompact,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await DraftsScheduledScreen.open(
                      context,
                      onPostPublished: _loadAllProfileData,
                    );
                    if (mounted) _loadAllProfileData();
                  },
                ),
                SizedBox(height: isCompact ? 8 : 10),

                // 6. Interactive Live Room Tile
                _buildClayCreateTile(
                  icon: Icons.podcasts_rounded,
                  iconGradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFF59E0B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  title: "Live Room",
                  subtitle: "Host or join interactive Realtime ZEV chat rooms",
                  isCompact: isCompact,
                  onTap: () {
                    Navigator.pop(ctx);
                    LiveRoomsScreen.open(context);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClayCreateTile({
    required IconData icon,
    required Gradient iconGradient,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isCompact = false,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: _buildClayCard(
        borderRadius: isCompact ? 16 : 18,
        depth: 3.2,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 14,
          vertical: isCompact ? 10 : 12,
        ),
        child: Row(
          children: [
            // 3D Illuminated Glossy Gradient Icon Badge
            Container(
              width: isCompact ? 40 : 44,
              height: isCompact ? 40 : 44,
              decoration: BoxDecoration(
                gradient: iconGradient,
                borderRadius: BorderRadius.circular(isCompact ? 12 : 14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: isCompact ? 20 : 22),
            ),
            SizedBox(width: isCompact ? 12 : 14),

            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isCompact ? 14 : 15,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isCompact ? 11.5 : 12,
                      color: ZevColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Chevron Right
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFFCBD5E1),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettingsMenu() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSettingsScreen(
          profile: _profile,
          onOpenSaved: () {
            if (_isMyProfile && _tabCtrl.length >= 4) {
              _tabCtrl.animateTo(3);
            }
          },
          onProfileUpdated: (updated) {
            setState(() => _profile = updated);
          },
        ),
      ),
    ).then((_) => _loadAllProfileData());
  }

  void _openEditProfile() async {
    HapticFeedback.lightImpact();
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          initialProfile: _profile,
        ),
      ),
    );
    if (updated != null) {
      setState(() => _profile = updated);
      _loadAllProfileData();
    }
  }

  void _openShareProfile() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareProfileScreen(
          userId: _targetUserId,
          username: _profile['username'] ?? 'user',
          fullName:
              "${_profile['first_name'] ?? ''} ${_profile['last_name'] ?? ''}"
                  .trim(),
          avatarUrl: _profile['avatar_url'] ?? '',
        ),
      ),
    );
  }

  void _openFollowersSheet(int tabIndex) {
    if (!_isMyProfile && !_canViewContent) return;
    HapticFeedback.lightImpact();
    UserFollowsScreen.open(
      context,
      userId: _targetUserId,
      username: _profile['username'] ?? 'user',
      initialTabIndex: tabIndex,
    ).then((_) => _loadAllProfileData());
  }

  void _onAvatarTapped() {
    HapticFeedback.lightImpact();
    if (_hasActiveStory &&
        _activeStory != null &&
        (_isMyProfile || _canViewContent)) {
      StoryViewerScreen.open(context, friendStory: _activeStory!)
          .then((_) => _loadAllProfileData());
    } else if (_isMyProfile) {
      CreateStoryScreen.open(context, onStoryCreated: _loadAllProfileData);
    }
  }

  void _openPostDetail(FeedPostItem post) {
    HapticFeedback.lightImpact();
    PostDetailScreen.open(
      context,
      postId: post.id,
      initialPost: post,
    ).then((_) => _loadAllProfileData());
  }

  void _openReelDetail(ReelItem reel) {
    HapticFeedback.lightImpact();
    bool isMuted = false;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (navCtx, setPlayerState) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: const BackButton(color: Colors.white),
            ),
            body: ReelPlayerItem(
              reel: reel,
              isActive: true,
              isGlobalMuted: isMuted,
              onToggleMute: () => setPlayerState(() => isMuted = !isMuted),
              onReelDeleted: () {
                Navigator.of(navCtx).pop();
                _loadAllProfileData();
              },
              onHideOrMute: () {
                Navigator.of(navCtx).pop();
                _loadAllProfileData();
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showVisitorMenuSheet() async {
    if (_isMyProfile || _targetUserId.isEmpty) return;
    HapticFeedback.lightImpact();
    final username = (_profile['username'] ?? 'user').toString();
    final me = supabase.auth.currentUser?.id;

    bool isMuted = false;
    if (me != null) {
      try {
        final muteRow = await supabase
            .from('user_mutes')
            .select('id')
            .eq('muter_id', me)
            .eq('muted_id', _targetUserId)
            .maybeSingle();
        isMuted = muteRow != null;
      } catch (_) {}
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                _buildProfileManageTile(
                  icon: Icons.share_outlined,
                  title: "Share Profile",
                  color: ZevColors.deepNavy,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openShareProfile();
                  },
                ),
                const SizedBox(height: 10),
                _buildProfileManageTile(
                  icon: Icons.link_rounded,
                  title: "Copy Profile Link",
                  color: ZevColors.deepNavy,
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: 'https://zevapp.com/@$username'),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied @$username\'s profile link'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: ZevColors.deepNavy,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                _buildProfileManageTile(
                  icon: isMuted
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  title: isMuted
                      ? "Unmute Posts & Stories"
                      : "Mute Posts & Stories",
                  color: ZevColors.secondaryBlue,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = isMuted
                        ? await SocialGraphService.instance
                            .unmuteUser(_targetUserId)
                        : await SocialGraphService.instance.muteUser(
                            _targetUserId,
                            mutePosts: true,
                            muteStories: true,
                          );
                    if (ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isMuted
                                ? 'Unmuted @$username'
                                : 'Muted posts & stories from @$username',
                          ),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: ZevColors.deepNavy,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                _buildProfileManageTile(
                  icon: Icons.block_rounded,
                  title: _blockedByMe
                      ? "Unblock @$username"
                      : "Block @$username",
                  color: ZevColors.errorRed,
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (_blockedByMe) {
                      final ok = await SocialGraphService.instance
                          .unblockUser(_targetUserId);
                      if (ok) await _loadAllProfileData();
                    } else {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          backgroundColor: ZevColors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          title: Text(
                            'Block @$username?',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          content: Text(
                            '@$username will no longer be able to view your profile, posts, or message you, and any follow connection will be removed.',
                            style: const TextStyle(
                              color: ZevColors.textSecondary,
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(dCtx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ZevColors.errorRed,
                                foregroundColor: Colors.white,
                                elevation: 0,
                              ),
                              child: const Text('Block'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        final ok = await SocialGraphService.instance
                            .blockUser(_targetUserId);
                        if (ok) await _loadAllProfileData();
                      }
                    }
                  },
                ),
                const SizedBox(height: 10),
                _buildProfileManageTile(
                  icon: Icons.flag_outlined,
                  title: "Report Account",
                  color: ZevColors.errorRed,
                  onTap: () {
                    Navigator.pop(ctx);
                    SocialGraphService.instance.showReportSheet(
                      context,
                      targetType: 'user',
                      targetId: _targetUserId,
                      reportedUserId: _targetUserId,
                      targetLabel: '@$username',
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPostManageSheet(FeedPostItem post) {
    if (!_isMyProfile) return;
    HapticFeedback.lightImpact();
    final bool canDelete = ContentDeletionService.canDeletePost(post);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),
                _buildProfileManageTile(
                  icon: Icons.fullscreen_rounded,
                  title: "View Post",
                  color: ZevColors.deepNavy,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openPostDetail(post);
                  },
                ),
                if (canDelete) ...[
                  const SizedBox(height: 10),
                  _buildProfileManageTile(
                    icon: Icons.campaign_rounded,
                    title: "Advertise Post",
                    color: const Color(0xFF0284C7),
                    onTap: () {
                      Navigator.pop(ctx);
                      AdsManagerScreen.openForPost(context, post: post);
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildProfileManageTile(
                    icon: Icons.edit_outlined,
                    title: "Edit Post",
                    color: ZevColors.deepNavy,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ContentDeletionService.showEditPostDialog(
                        context,
                        post: post,
                        onUpdated: (_) => _loadAllProfileData(),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildProfileManageTile(
                    icon: Icons.archive_outlined,
                    title: "Move to Archive",
                    color: ZevColors.secondaryBlue,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ContentDeletionService.setPostArchived(
                        context,
                        post: post,
                        archived: true,
                        onUpdated: _loadAllProfileData,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildProfileManageTile(
                    icon: Icons.recycling_rounded,
                    title: "Move to Recently Deleted",
                    color: const Color(0xFFD97706),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ContentDeletionService.movePostToTrash(
                        context,
                        post: post,
                        onTrashed: _loadAllProfileData,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildProfileManageTile(
                    icon: Icons.delete_outline_rounded,
                    title: "Delete Permanently",
                    color: ZevColors.errorRed,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ContentDeletionService.confirmAndDeletePost(
                        context,
                        post: post,
                        onDeleted: _loadAllProfileData,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReelManageSheet(ReelItem reel) {
    if (!_isMyProfile) return;
    HapticFeedback.lightImpact();
    final bool canDelete = ContentDeletionService.canDeleteReel(reel);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),
                _buildProfileManageTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: "Play Reel",
                  color: ZevColors.deepNavy,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openReelDetail(reel);
                  },
                ),
                const SizedBox(height: 10),
                _buildProfileManageTile(
                  icon: Icons.remove_red_eye_outlined,
                  title: "Quick Preview",
                  color: ZevColors.secondaryBlue,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showQuickReelPreview(reel);
                  },
                ),
                if (canDelete) ...[
                  const SizedBox(height: 10),
                  _buildProfileManageTile(
                    icon: Icons.recycling_rounded,
                    title: "Move to Recently Deleted",
                    color: const Color(0xFFD97706),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ContentDeletionService.moveReelToTrash(
                        context,
                        reel: reel,
                        onTrashed: _loadAllProfileData,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildProfileManageTile(
                    icon: Icons.delete_outline_rounded,
                    title: "Delete Permanently",
                    color: ZevColors.errorRed,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ContentDeletionService.confirmAndDeleteReel(
                        context,
                        reel: reel,
                        onDeleted: _loadAllProfileData,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileManageTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right_rounded,
              color: ZevColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// Quick Peek preview dialog for Reels in Light Clearmorphism / cinema framing
  void _showQuickReelPreview(ReelItem reel) {
    HapticFeedback.heavyImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Reel Preview",
      barrierColor: ZevColors.deepNavy.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: ZevColors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.deepNavy.withValues(alpha: 0.25),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: ZevColors.softSurface,
                            ),
                            child: ClipOval(
                              child: reel.authorAvatar.isNotEmpty
                                  ? ZevCachedImage.avatar(
                                      imageUrl: reel.authorAvatar,
                                      size: 36,
                                    )
                                  : const Icon(
                                      Icons.person,
                                      color: ZevColors.textMuted,
                                      size: 18,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      "@${reel.authorUsername}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: ZevColors.deepNavy,
                                      ),
                                    ),
                                    if (reel.isVerified) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.verified_rounded,
                                        size: 14,
                                        color: ZevColors.primaryBlue,
                                      ),
                                    ],
                                  ],
                                ),
                                if (reel.title.isNotEmpty)
                                  Text(
                                    reel.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: ZevColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AspectRatio(
                      aspectRatio: 9 / 14,
                      child: ZevVideoThumbnail(
                        videoUrl: reel.videoUrl,
                        thumbnailUrl: reel.thumbnailUrl,
                        autoPlay: true,
                        initialMuted: false,
                        showMuteToggle: true,
                        showPlayBadge: false,
                        showViews: false,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      color: ZevColors.softSurface,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _openReelDetail(reel);
                            },
                            icon: const Icon(
                              Icons.play_circle_fill_rounded,
                              color: ZevColors.primaryBlue,
                              size: 20,
                            ),
                            label: const Text(
                              "Watch Full Reel",
                              style: TextStyle(
                                color: ZevColors.deepNavy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openCreateHighlightSheet() {
    HapticFeedback.lightImpact();
    CreateHighlightSheet.show(
      context,
      userId: _targetUserId,
      onHighlightCreated: (newHighlight) {
        setState(() => _highlights.insert(0, newHighlight));
      },
    );
  }

  void _openHighlightViewer(StoryHighlight highlight) {
    HapticFeedback.lightImpact();
    HighlightViewerScreen.open(
      context,
      highlight: highlight,
      isOwner: _isMyProfile,
      onDelete: () async {
        await StoryHighlightService().deleteHighlight(
          _targetUserId,
          highlight.id,
        );
        if (mounted) {
          setState(() {
            _highlights.removeWhere((h) => h.id == highlight.id);
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Highlight removed")));
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Claymorphic Design Helpers
  // ---------------------------------------------------------------------------
  Widget _buildClayCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 24,
    Color color = Colors.white,
    double depth = 6.0,
    Border? border,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
        border:
            border ??
            Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
        boxShadow: [
          // Darker soft drop shadow (bottom-right)
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: depth * 2.5,
            offset: Offset(depth * 0.6, depth * 0.8),
          ),
          // Crisp ambient white highlight (top-left)
          BoxShadow(
            color: Colors.white,
            blurRadius: depth * 1.5,
            offset: Offset(-depth * 0.5, -depth * 0.5),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _profile.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F5F9),
        body: Center(
          child: CircularProgressIndicator(color: ZevColors.primaryBlue),
        ),
      );
    }

    final username = _profile['username'] ?? 'user';
    final fn = _profile['first_name'] ?? '';
    final ln = _profile['last_name'] ?? '';
    final full = "$fn $ln".trim();
    final fullName = full.isNotEmpty ? full : username;
    final avatarUrl = _profile['avatar_url'] as String? ?? '';
    final isVerified = _profile['is_verified'] == true;
    final bio = _profile['bio'] as String? ?? '';
    final isBioRtl = TextDirectionHelper.isRtl(bio);

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 720;
    final isCompact = screenWidth < 380;
    final horizontalPadding = isCompact ? 12.0 : (isDesktop ? 24.0 : 16.0);

    if (!_isMyProfile && _isBlockedView) {
      return Scaffold(
        backgroundColor: ZevColors.softSurface,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(username, isVerified, isCompact),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildClayCard(
                      borderRadius: 24,
                      depth: 5.0,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ZevColors.errorRed.withValues(alpha: 0.1),
                            ),
                            child: const Icon(
                              Icons.block_rounded,
                              size: 32,
                              color: ZevColors.errorRed,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _blockedByMe
                                ? "You blocked @$username"
                                : "Profile Unavailable",
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _blockedByMe
                                ? "Unblock @$username if you want to view their posts, reels, and stories again."
                                : "This user's content is not accessible.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: ZevColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          if (_blockedByMe) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () async {
                                final ok = await SocialGraphService.instance
                                    .unblockUser(_targetUserId);
                                if (ok) await _loadAllProfileData();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ZevColors.primaryBlue,
                                foregroundColor: ZevColors.deepNavy,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                "Unblock Account",
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isMyProfile && !_canViewContent) {
      return Scaffold(
        backgroundColor: ZevColors.softSurface,
        body: SafeArea(
          child: RefreshIndicator(
            color: ZevColors.primaryBlue,
            onRefresh: _loadAllProfileData,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                _buildTopBar(username, isVerified, isCompact),
                const SizedBox(height: 6),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: _buildProfileHeader(
                    avatarUrl: avatarUrl,
                    fullName: fullName,
                    username: username,
                    bio: bio,
                    isBioRtl: isBioRtl,
                    isVerified: isVerified,
                    isCompact: isCompact,
                  ),
                ),
                SizedBox(height: isCompact ? 10 : 14),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: _buildActionRow(isCompact),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: _buildClayCard(
                    borderRadius: 24,
                    depth: 4.5,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 28,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ZevColors.secondaryBlue.withValues(alpha: 0.12),
                          ),
                          child: const Icon(
                            Icons.lock_outline_rounded,
                            size: 28,
                            color: ZevColors.secondaryBlue,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "This Account is Private",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Follow @$username to see their posts, reels, and stories once approved.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: ZevColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Luxurious Clearmorphic ZEV Profile Canvas
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 960 : double.infinity,
            ),
            child: RefreshIndicator(
              color: ZevColors.primaryBlue,
              onRefresh: _loadAllProfileData,
              child: NestedScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Sleek Clearmorphic Top Bar
                          _buildTopBar(username, isVerified, isCompact),
                      const SizedBox(height: 6),

                      // Owner Pending Follow Requests Notice Banner
                      if (_isMyProfile && _pendingRequestsCount > 0) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: GestureDetector(
                            onTap: () => _openFollowersSheet(2),
                            child: _buildClayCard(
                              borderRadius: 16,
                              depth: 3.0,
                              color: ZevColors.primaryBlue.withValues(alpha: 0.1),
                              border: Border.all(
                                color: ZevColors.primaryBlue.withValues(
                                  alpha: 0.35,
                                ),
                                width: 1.2,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person_add_alt_1_rounded,
                                    color: ZevColors.secondaryBlue,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "$_pendingRequestsCount Pending Follow Request${_pendingRequestsCount > 1 ? 's' : ''}",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: ZevColors.deepNavy,
                                      ),
                                    ),
                                  ),
                                  const Text(
                                    "Review",
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: ZevColors.secondaryBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: ZevColors.secondaryBlue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Owner Account Restriction Standing Notice Banner
                      if (_isMyProfile && _hasActiveRestrictionStanding()) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: _buildClayCard(
                            borderRadius: 16,
                            depth: 3.0,
                            color: const Color(0xFFFFFBEB),
                            border: Border.all(
                              color: const Color(0xFFFDE68A),
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFD97706),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Account Standing Notice",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF92400E),
                                        ),
                                      ),
                                      Text(
                                        (_profile['restriction_reason'] ?? '')
                                                .toString()
                                                .trim()
                                                .isNotEmpty
                                            ? _profile['restriction_reason']
                                                .toString()
                                            : "A temporary policy notice is active on your profile.",
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFFB45309),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    AppealRestrictionSheet.show(
                                      context,
                                      initialReason:
                                          _profile['restriction_reason']
                                              ?.toString(),
                                    ).then((_) => _loadAllProfileData());
                                  },
                                  style: TextButton.styleFrom(
                                    backgroundColor: const Color(0xFFD97706),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    "Appeal",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // 2. Profile Info Header (3D Avatar + 3 Clay Stats + Name + Bio + Links)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: _buildProfileHeader(
                          avatarUrl: avatarUrl,
                          fullName: fullName,
                          username: username,
                          bio: bio,
                          isBioRtl: isBioRtl,
                          isVerified: isVerified,
                          isCompact: isCompact,
                        ),
                      ),
                      SizedBox(height: isCompact ? 10 : 14),

                      // 3. Tactile Clay Action Buttons Row
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: _buildActionRow(isCompact),
                      ),

                      // 4. Suggested Creators Expandable Section
                      if (_showSuggestedCreators) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: _buildSuggestedCreatorsCarousel(),
                        ),
                      ],

                      // 5. Authentic Story Highlights
                      if (_isMyProfile || _highlights.isNotEmpty) ...[
                        SizedBox(height: isCompact ? 12 : 16),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: _buildStoryHighlights(),
                        ),
                      ],

                      SizedBox(height: isCompact ? 8 : 12),
                    ],
                  ),
                ),

                // 6. Sticky Pinned Clearmorphic Tab Bar Dock
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ProfileTabBarDelegate(tabBar: _buildTabBar()),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabCtrl,
              children: [
                // 1. Posts Grid
                _buildPostsGrid(),
                // 2. Reels Grid
                _buildReelsGrid(),
                // 3. Reposts Grid
                _buildRepostsGrid(),
                // 4. Saved Grid (Owner Only)
                if (_isMyProfile) _buildSavedGrid(),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
}

  // ---------------------------------------------------------------------------
  // Sleek Clearmorphic Top Bar
  // ---------------------------------------------------------------------------
  Widget _buildTopBar(
    String username,
    bool isVerified, [
    bool isCompact = false,
  ]) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 16,
        vertical: 6,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                if (widget.onExit != null || !_isMyProfile) ...[
                  GestureDetector(
                    onTap: widget.onExit ?? () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: _buildClayCard(
                      borderRadius: 12,
                      depth: 3.0,
                      padding: const EdgeInsets.all(7),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: ZevColors.deepNavy,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: GestureDetector(
                    onTap: _isMyProfile
                        ? () => MultiAccountService.showAccountSwitcherSheet(
                            context,
                          )
                        : null,
                    behavior: HitTestBehavior.opaque,
                    child: _buildClayCard(
                      borderRadius: 14,
                      depth: 3.0,
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 10 : 12,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              "@$username",
                              style: TextStyle(
                                fontSize: isCompact ? 15.5 : 17,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: ZevColors.primaryBlue,
                            ),
                          ],
                          if (_isMyProfile) ...[
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 19,
                              color: ZevColors.deepNavy,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isMyProfile) ...[
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    CreatorInsightsScreen.open(
                      context,
                      userProfile: _profile,
                    ).then((_) => _loadAllProfileData());
                  },
                  behavior: HitTestBehavior.opaque,
                  child: _buildClayCard(
                    borderRadius: 12,
                    depth: 3.0,
                    padding: const EdgeInsets.all(7),
                    child: const Icon(
                      Icons.insights_rounded,
                      color: ZevColors.secondaryBlue,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _openCreateMenu,
                  behavior: HitTestBehavior.opaque,
                  child: _buildClayCard(
                    borderRadius: 12,
                    depth: 3.0,
                    padding: const EdgeInsets.all(7),
                    child: const Icon(
                      Icons.add_box_outlined,
                      color: ZevColors.deepNavy,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _openSettingsMenu,
                  behavior: HitTestBehavior.opaque,
                  child: _buildClayCard(
                    borderRadius: 12,
                    depth: 3.0,
                    padding: const EdgeInsets.all(7),
                    child: const Icon(
                      Icons.menu_rounded,
                      color: ZevColors.deepNavy,
                      size: 21,
                    ),
                  ),
                ),
              ] else ...[
                GestureDetector(
                  onTap: _openShareProfile,
                  behavior: HitTestBehavior.opaque,
                  child: _buildClayCard(
                    borderRadius: 12,
                    depth: 3.0,
                    padding: const EdgeInsets.all(7),
                    child: const Icon(
                      Icons.share_outlined,
                      color: ZevColors.deepNavy,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _showVisitorMenuSheet,
                  behavior: HitTestBehavior.opaque,
                  child: _buildClayCard(
                    borderRadius: 12,
                    depth: 3.0,
                    padding: const EdgeInsets.all(7),
                    child: const Icon(
                      Icons.more_vert_rounded,
                      color: ZevColors.deepNavy,
                      size: 21,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Master Profile Header (3D Clay Avatar, 3 Clay Stat Tiles, Name, Bio, Links)
  // ---------------------------------------------------------------------------
  Widget _buildProfileHeader({
    required String avatarUrl,
    required String fullName,
    required String username,
    required String bio,
    required bool isBioRtl,
    required bool isVerified,
    bool isCompact = false,
  }) {
    final avatarSize = isCompact ? 72.0 : 84.0;
    final showStoryRing = _hasActiveStory && (_isMyProfile || _canViewContent);
    final allowStatsTap = _isMyProfile || _canViewContent;
    final location = (_profile['location'] ?? '').toString().trim();
    final website = (_profile['website'] ?? '').toString().trim();
    final showCategory = _profile['show_category_on_profile'] == true;
    final category = (_profile['category'] ?? '').toString().trim();
    final pronouns = (_profile['pronouns'] ?? '').toString().trim();

    final seenLinkUrls = <String>{};
    final externalLinks = <({String title, String url})>[];
    if (website.isNotEmpty) {
      final norm = website.toLowerCase();
      seenLinkUrls.add(norm);
      externalLinks.add((
        title: website.replaceFirst(RegExp(r'^https?://(www\.)?'), ''),
        url: website,
      ));
    }
    for (final link in _userLinks) {
      final url = (link['url'] ?? '').toString().trim();
      final title = (link['title'] ?? '').toString().trim();
      if (url.isEmpty || seenLinkUrls.contains(url.toLowerCase())) continue;
      seenLinkUrls.add(url.toLowerCase());
      externalLinks.add((
        title: title.isNotEmpty
            ? title
            : url.replaceFirst(RegExp(r'^https?://(www\.)?'), ''),
        url: url,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row: Avatar + Stats (Posts, Followers, Following)
        Row(
          children: [
            GestureDetector(
              onTap: _onAvatarTapped,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: showStoryRing
                          ? const LinearGradient(
                              colors: [
                                Color(0xFFFBAA47),
                                Color(0xFFD91A46),
                                Color(0xFFA60F93),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      border: showStoryRing
                          ? null
                          : Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(2, 4),
                        ),
                        const BoxShadow(
                          color: Colors.white,
                          blurRadius: 10,
                          offset: Offset(-2, -2),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(showStoryRing ? 3.0 : 0.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      padding: const EdgeInsets.all(2.0),
                      child: ClipOval(
                        child: avatarUrl.isNotEmpty
                            ? ZevCachedImage.avatar(
                                imageUrl: avatarUrl,
                                size: avatarSize,
                              )
                            : Container(
                                color: const Color(0xFFF1F5F9),
                                child: Icon(
                                  Icons.person,
                                  color: ZevColors.textMuted,
                                  size: isCompact ? 36 : 42,
                                ),
                              ),
                      ),
                    ),
                  ),
                  if (_isMyProfile && !showStoryRing)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: ZevColors.primaryBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.2),
                          boxShadow: [
                            BoxShadow(
                              color: ZevColors.primaryBlue.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: ZevColors.deepNavy,
                          size: isCompact ? 12 : 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: isCompact ? 12 : 18),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      label: "Posts",
                      count: _userPosts.length + _userReels.length,
                      isCompact: isCompact,
                    ),
                  ),
                  SizedBox(width: isCompact ? 6 : 8),
                  Expanded(
                    child: _buildStatItem(
                      label: "Followers",
                      count: _followersCount,
                      onTap: allowStatsTap ? () => _openFollowersSheet(0) : null,
                      isCompact: isCompact,
                    ),
                  ),
                  SizedBox(width: isCompact ? 6 : 8),
                  Expanded(
                    child: _buildStatItem(
                      label: "Following",
                      count: _followingCount,
                      onTap: allowStatsTap ? () => _openFollowersSheet(1) : null,
                      isCompact: isCompact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // User Full Name, Verified Badge & Optional Pronouns
        Row(
          children: [
            Flexible(
              child: Text(
                fullName,
                style: TextStyle(
                  fontSize: isCompact ? 14.5 : 16,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isVerified) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.verified_rounded,
                size: 15,
                color: ZevColors.primaryBlue,
              ),
            ],
            if (pronouns.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ZevColors.border),
                ),
                child: Text(
                  pronouns,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),

        if ((showCategory && category.isNotEmpty) || location.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (showCategory && category.isNotEmpty)
                Text(
                  category,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
              if (location.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 13.5,
                      color: ZevColors.textMuted,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      location,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],

        // Bio in a subtle Clearmorphic Pill
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildClayCard(
            borderRadius: 14,
            depth: 2.5,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              bio,
              textDirection: isBioRtl ? TextDirection.rtl : TextDirection.ltr,
              textAlign: isBioRtl ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 13,
                color: ZevColors.deepNavy,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],

        // External Links (website + normalized user_links)
        if (externalLinks.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: externalLinks.map((lnk) {
              return GestureDetector(
                onTap: () => _launchExternalLink(lnk.url),
                child: _buildClayCard(
                  borderRadius: 12,
                  depth: 2.0,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.link_rounded,
                        size: 14,
                        color: ZevColors.secondaryBlue,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          lnk.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.secondaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Claymorphic Stat Item (Posts, Followers, Following)
  // ---------------------------------------------------------------------------
  Widget _buildStatItem({
    required String label,
    required int count,
    VoidCallback? onTap,
    bool isCompact = false,
  }) {
    final countStr = count > 9999
        ? "${(count / 1000).toStringAsFixed(1)}K"
        : count.toString();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _buildClayCard(
        borderRadius: isCompact ? 14 : 16,
        depth: 3.2,
        padding: EdgeInsets.symmetric(
          vertical: isCompact ? 8 : 10,
          horizontal: 4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                countStr,
                style: TextStyle(
                  fontSize: isCompact ? 16 : 17.5,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: ZevColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tactile Clay Action Buttons Row
  // ---------------------------------------------------------------------------
  Widget _buildActionRow([bool isCompact = false]) {
    if (_isMyProfile) {
      return Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _openEditProfile,
              child: _buildClayCard(
                borderRadius: 14,
                depth: 3.2,
                padding: EdgeInsets.symmetric(
                  vertical: isCompact ? 9 : 11,
                  horizontal: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: isCompact ? 14 : 15,
                      color: ZevColors.deepNavy,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "Edit Profile",
                          style: TextStyle(
                            fontSize: isCompact ? 12.5 : 13.5,
                            fontWeight: FontWeight.w800,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: isCompact ? 6 : 8),
          Expanded(
            child: GestureDetector(
              onTap: _openShareProfile,
              child: _buildClayCard(
                borderRadius: 14,
                depth: 3.2,
                padding: EdgeInsets.symmetric(
                  vertical: isCompact ? 9 : 11,
                  horizontal: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.share_outlined,
                      size: isCompact ? 14 : 15,
                      color: ZevColors.deepNavy,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "Share Profile",
                          style: TextStyle(
                            fontSize: isCompact ? 12.5 : 13.5,
                            fontWeight: FontWeight.w800,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: isCompact ? 6 : 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showSuggestedCreators = !_showSuggestedCreators);
            },
            child: _buildClayCard(
              borderRadius: 14,
              depth: 3.2,
              padding: EdgeInsets.all(isCompact ? 9 : 11),
              color: _showSuggestedCreators
                  ? ZevColors.primaryBlue
                  : Colors.white,
              child: Icon(
                _showSuggestedCreators
                    ? Icons.person_remove_outlined
                    : Icons.person_add_outlined,
                size: isCompact ? 17 : 19,
                color: ZevColors.deepNavy,
              ),
            ),
          ),
        ],
      );
    }

    // Visitor Action Buttons (Follow / Requested / Message)
    final followLabel = _isFollowing
        ? "Following"
        : (_followRequested ? "Requested" : "Follow");
    final followBg = (_isFollowing || _followRequested)
        ? Colors.white
        : ZevColors.secondaryBlue;
    final followFg =
        (_isFollowing || _followRequested) ? ZevColors.deepNavy : Colors.white;
    final canMessage = _interactionPolicy?['can_message'] != false;
    final peerFullName =
        "${_profile['first_name'] ?? ''} ${_profile['last_name'] ?? ''}".trim();

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _toggleFollow,
            child: _buildClayCard(
              borderRadius: 14,
              depth: 3.2,
              color: followBg,
              padding: EdgeInsets.symmetric(
                vertical: isCompact ? 9 : 11,
                horizontal: 4,
              ),
              child: Center(
                child: _isFollowLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: followFg,
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          followLabel,
                          style: TextStyle(
                            fontSize: isCompact ? 13 : 13.5,
                            fontWeight: FontWeight.w800,
                            color: followFg,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        SizedBox(width: isCompact ? 6 : 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (!canMessage) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "@${_profile['username'] ?? 'User'} restricts direct messages.",
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: ZevColors.deepNavy,
                  ),
                );
                return;
              }
              ChatConversationScreen.open(
                context,
                peerId: _targetUserId,
                peerUsername: _profile['username'] ?? 'User',
                peerFullName: peerFullName.isNotEmpty
                    ? peerFullName
                    : (_profile['username'] ?? 'User').toString(),
                peerAvatar: _profile['avatar_url'] ?? '',
                isPeerVerified: _profile['is_verified'] == true,
              );
            },
            child: _buildClayCard(
              borderRadius: 14,
              depth: 3.2,
              padding: EdgeInsets.symmetric(
                vertical: isCompact ? 9 : 11,
                horizontal: 4,
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      canMessage
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.lock_outline_rounded,
                      size: isCompact ? 14 : 15,
                      color: canMessage
                          ? ZevColors.deepNavy
                          : ZevColors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "Message",
                          style: TextStyle(
                            fontSize: isCompact ? 13 : 13.5,
                            fontWeight: FontWeight.w800,
                            color: canMessage
                                ? ZevColors.deepNavy
                                : ZevColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Authentic Claymorphic Story Highlights
  // ---------------------------------------------------------------------------
  Widget _buildStoryHighlights() {
    if (_isLoadingHighlights) {
      return const SizedBox(
        height: 84,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ZevColors.primaryBlue,
          ),
        ),
      );
    }

    final totalCount = _highlights.length + (_isMyProfile ? 1 : 0);

    // If visitor and no highlights, omit cleanly
    if (!_isMyProfile && _highlights.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: totalCount,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          // Plus button for new highlight (only for profile owner)
          if (_isMyProfile && index == 0) {
            return GestureDetector(
              onTap: _openCreateHighlightSheet,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildClayCard(
                    borderRadius: 32,
                    depth: 3.5,
                    padding: const EdgeInsets.all(3.5),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF8FAFC),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.add_rounded,
                          color: ZevColors.deepNavy,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "New",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ],
              ),
            );
          }

          final h = _highlights[_isMyProfile ? index - 1 : index];
          return GestureDetector(
            onTap: () => _openHighlightViewer(h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildClayCard(
                  borderRadius: 32,
                  depth: 3.5,
                  padding: const EdgeInsets.all(3.5),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: ClipOval(
                      child: h.coverUrl.isNotEmpty
                          ? (h.coverUrl.toLowerCase().contains('.mp4') ||
                                    h.coverUrl.toLowerCase().contains('.mov') ||
                                    h.coverUrl.toLowerCase().contains('.webm')
                                ? VideoCoverThumbnail(videoUrl: h.coverUrl)
                                : ZevCachedImage.avatar(
                                    imageUrl: h.coverUrl,
                                    size: 56,
                                  ))
                          : (h.items.isNotEmpty &&
                                    h.items.first.mediaType == 'video'
                                ? VideoCoverThumbnail(
                                    videoUrl: h.items.first.mediaUrl,
                                  )
                                : const Icon(
                                    Icons.star_rounded,
                                    color: ZevColors.primaryBlue,
                                    size: 28,
                                  )),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: 64,
                  child: Text(
                    h.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Clean Claymorphic Tab Bar
  // ---------------------------------------------------------------------------
  TabBar _buildTabBar() {
    return TabBar(
      controller: _tabCtrl,
      indicator: BoxDecoration(
        color: ZevColors.deepNavy,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelColor: Colors.white,
      unselectedLabelColor: ZevColors.textMuted,
      tabs: [
        const Tab(icon: Icon(Icons.grid_on_rounded, size: 20)),
        const Tab(icon: Icon(Icons.video_collection_outlined, size: 20)),
        const Tab(icon: Icon(Icons.repeat_rounded, size: 20)),
        if (_isMyProfile)
          const Tab(icon: Icon(Icons.bookmark_border_rounded, size: 20)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Expandable Suggested Creators Carousel
  // ---------------------------------------------------------------------------
  Widget _buildSuggestedCreatorsCarousel() {
    if (_suggestedCreators.isEmpty) return const SizedBox.shrink();

    return _buildClayCard(
      borderRadius: 22,
      depth: 5.0,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => DiscoverScreen.open(context),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Discover people",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: ZevColors.textMuted,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => DiscoverScreen.open(context),
                    child: const Text(
                      "See all",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => setState(() => _showSuggestedCreators = false),
                    child: const Text(
                      "Hide",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.secondaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _suggestedCreators.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final u = _suggestedCreators[i];
                final id = u['id'] as String;
                final isFollowed = _followedSuggestedIds.contains(id);
                final isRequested = _requestedSuggestedIds.contains(id);
                final avatar = u['avatar_url'] as String? ?? '';
                final name = u['name'] as String? ?? 'User';
                final username = u['username'] as String? ?? '';
                final isVerified = u['is_verified'] == true;
                final isActiveState = isFollowed || isRequested;

                return Container(
                  width: 138,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ZevColors.softSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ZevColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => ProfileScreen.open(context, userId: id),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ZevCachedImage.avatar(
                              imageUrl: avatar,
                              size: 52,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: ZevColors.deepNavy,
                                    ),
                                  ),
                                ),
                                if (isVerified) ...[
                                  const SizedBox(width: 3),
                                  const Icon(
                                    Icons.verified_rounded,
                                    size: 13,
                                    color: ZevColors.primaryBlue,
                                  ),
                                ],
                              ],
                            ),
                            if (username.isNotEmpty)
                              Text(
                                '@$username',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: ZevColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 29,
                        child: ElevatedButton(
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            try {
                              final status = await SocialGraphService.instance
                                  .toggleFollow(id);
                              if (!mounted) return;
                              setState(() {
                                if (status == FollowToggleStatus.following) {
                                  _followedSuggestedIds.add(id);
                                  _requestedSuggestedIds.remove(id);
                                } else if (status ==
                                    FollowToggleStatus.requested) {
                                  _requestedSuggestedIds.add(id);
                                  _followedSuggestedIds.remove(id);
                                } else {
                                  _followedSuggestedIds.remove(id);
                                  _requestedSuggestedIds.remove(id);
                                }
                              });
                              _fetchFollowCounts();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not update follow: $e'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: ZevColors.errorRed,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isActiveState
                                ? ZevColors.white
                                : ZevColors.secondaryBlue,
                            foregroundColor: isActiveState
                                ? ZevColors.deepNavy
                                : ZevColors.white,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                              side: isActiveState
                                  ? const BorderSide(color: ZevColors.border)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Text(
                            isFollowed
                                ? "Following"
                                : (isRequested ? "Requested" : "Follow"),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Authentic Claymorphic Content Grids (Posts, Reels, Reposts, Saved)
  // ---------------------------------------------------------------------------
  Widget _buildPostsGrid() {
    if (_userPosts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.camera_alt_outlined,
        title: "No Posts Yet",
        subtitle: _isMyProfile
            ? "When you share photos, they will appear on your profile."
            : "No posts shared yet by @${_profile['username'] ?? 'user'}.",
        actionLabel: _isMyProfile ? "Share your first photo" : null,
        onAction: () =>
            CreatePostScreen.open(context, onPostCreated: _loadAllProfileData),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: _userPosts.length,
      itemBuilder: (context, index) {
        final post = _userPosts[index];
        final hasCarousel = post.effectiveMediaUrls.length > 1;
        return GestureDetector(
          onTap: () => _openPostDetail(post),
          onLongPress: _isMyProfile ? () => _showPostManageSheet(post) : null,
          child: _buildClayCard(
            borderRadius: 12,
            depth: 2.5,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  post.imageUrl.isNotEmpty
                      ? ((ZevVideoThumbnail.isVideoUrl(post.imageUrl) ||
                                (post.mediaItems.isNotEmpty &&
                                    post.mediaItems.first.mediaType
                                            .toLowerCase() ==
                                        'video'))
                            ? ZevVideoThumbnail(
                                videoUrl: post.imageUrl,
                                thumbnailUrl: post.mediaItems.isNotEmpty
                                    ? post.mediaItems.first.thumbnailUrl
                                    : null,
                                durationSeconds: post.mediaItems.isNotEmpty
                                    ? post.mediaItems.first.durationSeconds
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              )
                            : ZevCachedImage.grid(imageUrl: post.imageUrl))
                      : Container(
                          padding: const EdgeInsets.all(8),
                          color: const Color(0xFFF8FAFC),
                          child: Center(
                            child: Text(
                              post.content.isNotEmpty ? post.content : post.title,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                          ),
                        ),
                  if (hasCarousel)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: ZevColors.deepNavy.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.collections_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReelsGrid() {
    if (_userReels.isEmpty) {
      return _buildEmptyState(
        icon: Icons.play_circle_outline_rounded,
        title: "No Reels Yet",
        subtitle: _isMyProfile
            ? "Record and share short immersive videos with your community."
            : "No reels published by @${_profile['username'] ?? 'user'}.",
        actionLabel: _isMyProfile ? "Create your first Reel" : null,
        onAction: () =>
            CreateReelScreen.open(context, onReelCreated: _loadAllProfileData),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _userReels.length,
      itemBuilder: (context, index) {
        final reel = _userReels[index];

        return GestureDetector(
          onTap: () => _openReelDetail(reel),
          onLongPress: () => _isMyProfile
              ? _showReelManageSheet(reel)
              : _showQuickReelPreview(reel),
          child: _buildClayCard(
            borderRadius: 14,
            depth: 2.8,
            padding: EdgeInsets.zero,
            color: const Color(0xFF0F172A),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ZevVideoThumbnail(
                videoUrl: reel.videoUrl,
                thumbnailUrl: reel.thumbnailUrl,
                viewsCount: reel.viewsCount,
                showPlayBadge: false,
                showViews: true,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRepostsGrid() {
    if (_userReposts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.repeat_rounded,
        title: "No Reposts Yet",
        subtitle: "Posts you repost to your profile will be collected here.",
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: _userReposts.length,
      itemBuilder: (context, index) {
        final post = _userReposts[index];
        final isVideo =
            ZevVideoThumbnail.isVideoUrl(post.imageUrl) ||
            (post.mediaItems.isNotEmpty &&
                post.mediaItems.first.mediaType.toLowerCase() == 'video');
        return GestureDetector(
          onTap: () => _openPostDetail(post),
          onLongPress: _isMyProfile ? () => _showPostManageSheet(post) : null,
          child: _buildClayCard(
            borderRadius: 12,
            depth: 2.5,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  post.imageUrl.isNotEmpty
                      ? (isVideo
                            ? ZevVideoThumbnail(
                                videoUrl: post.imageUrl,
                                thumbnailUrl: post.mediaItems.isNotEmpty
                                    ? post.mediaItems.first.thumbnailUrl
                                    : null,
                                durationSeconds: post.mediaItems.isNotEmpty
                                    ? post.mediaItems.first.durationSeconds
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              )
                            : ZevCachedImage.grid(imageUrl: post.imageUrl))
                      : Container(
                          padding: const EdgeInsets.all(8),
                          color: ZevColors.softSurface,
                          child: Center(
                            child: Text(
                              post.content.isNotEmpty
                                  ? post.content
                                  : post.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                          ),
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: ZevColors.deepNavy.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.repeat_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSavedGrid() {
    if (_userSavedPosts.isEmpty && _userSavedReels.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bookmark_border_rounded,
        title: "Save Posts and Reels",
        subtitle:
            "Save photos and videos that you want to revisit. Only you can see what you've saved.",
      );
    }

    final savedItems = <({DateTime createdAt, FeedPostItem? post, ReelItem? reel})>[
      for (final p in _userSavedPosts)
        (createdAt: p.createdAt, post: p, reel: null),
      for (final r in _userSavedReels)
        (createdAt: r.createdAt, post: null, reel: r),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: savedItems.length,
      itemBuilder: (context, index) {
        final item = savedItems[index];
        final reel = item.reel;
        if (reel != null) {
          return GestureDetector(
            onTap: () => _openReelDetail(reel),
            onLongPress:
                _isMyProfile ? () => _showQuickReelPreview(reel) : null,
            child: _buildClayCard(
              borderRadius: 12,
              depth: 2.5,
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ZevVideoThumbnail(
                      videoUrl: reel.videoUrl,
                      thumbnailUrl: reel.thumbnailUrl,
                      viewsCount: reel.viewsCount,
                      showPlayBadge: true,
                      showViews: false,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: ZevColors.deepNavy.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final post = item.post!;
        final isVideo =
            ZevVideoThumbnail.isVideoUrl(post.imageUrl) ||
            (post.mediaItems.isNotEmpty &&
                post.mediaItems.first.mediaType.toLowerCase() == 'video');
        return GestureDetector(
          onTap: () => _openPostDetail(post),
          onLongPress: _isMyProfile ? () => _showPostManageSheet(post) : null,
          child: _buildClayCard(
            borderRadius: 12,
            depth: 2.5,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: post.imageUrl.isNotEmpty
                  ? (isVideo
                        ? ZevVideoThumbnail(
                            videoUrl: post.imageUrl,
                            thumbnailUrl: post.mediaItems.isNotEmpty
                                ? post.mediaItems.first.thumbnailUrl
                                : null,
                            durationSeconds: post.mediaItems.isNotEmpty
                                ? post.mediaItems.first.durationSeconds
                                : null,
                            borderRadius: BorderRadius.circular(12),
                          )
                        : ZevCachedImage.grid(imageUrl: post.imageUrl))
                  : Container(
                      padding: const EdgeInsets.all(8),
                      color: ZevColors.softSurface,
                      child: Center(
                        child: Text(
                          post.content.isNotEmpty ? post.content : post.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: _buildClayCard(
          borderRadius: 24,
          depth: 5.0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFF1F5F9),
                ),
                child: Icon(icon, size: 28, color: ZevColors.deepNavy),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: ZevColors.textSecondary,
                  height: 1.35,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ZevColors.primaryBlue,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Sticky delegate for the profile navigation tab bar (pinned at top when scrolling)
class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _ProfileTabBarDelegate({required this.tabBar});

  @override
  double get minExtent => 52.0;

  @override
  double get maxExtent => 52.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Container(
        height: 46.0,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
            const BoxShadow(
              color: Colors.white,
              blurRadius: 8,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) {
    return false;
  }
}
