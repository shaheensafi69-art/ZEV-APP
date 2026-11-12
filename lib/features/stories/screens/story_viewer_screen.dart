import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/services/zev_ads_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_native_ad_story_unit.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../../feed/models/feed_post_item.dart';
import '../../profile/models/story_highlight_model.dart';
import '../../profile/screens/profile_screen.dart';
import '../../profile/services/story_highlight_service.dart';
import '../widgets/close_friends_sheet.dart';

/// Full-Featured Instagram-Grade Story Viewer for ZEV.
/// Supports:
/// - 24h photo/video stories + Close Friends audience badges
/// - Idempotent server view tracking (`record_story_view`)
/// - Owner Story Insights & Viewers sheet (`get_story_insights_and_viewers`: viewers, reactions, replies)
/// - Save to Story Highlights (`StoryHighlightService`) & Soft-Delete (`deleted_at`)
/// - Viewer quick emoji reactions (`story_reactions`), story likes (`story_likes`), direct replies (`story_replies`)
/// - Safety controls (`story_mutes`, `SocialGraphService.showReportSheet`)
/// - Native sponsored story ad units cleanly integrated
class StoryViewerScreen extends StatefulWidget {
  final ActiveFriendStory friendStory;
  final List<ActiveFriendStory>? allFriendStories;
  final int initialFriendIndex;
  final String? initialStoryId;

  const StoryViewerScreen({
    super.key,
    required this.friendStory,
    this.allFriendStories,
    this.initialFriendIndex = 0,
    this.initialStoryId,
  });

  static Future<void> open(
    BuildContext context, {
    required ActiveFriendStory friendStory,
    List<ActiveFriendStory>? allFriendStories,
    int initialFriendIndex = 0,
    String? initialStoryId,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            StoryViewerScreen(
              friendStory: friendStory,
              allFriendStories: allFriendStories,
              initialFriendIndex: initialFriendIndex,
              initialStoryId: initialStoryId,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Opens a story directly by its UUID (used by notifications & deep links).
  static Future<void> openByStoryId(
    BuildContext context, {
    required String storyId,
    String? fallbackUserId,
  }) async {
    final supabase = Supabase.instance.client;
    final cleanStoryId = storyId.trim();
    if (cleanStoryId.isEmpty) {
      if (fallbackUserId != null && fallbackUserId.isNotEmpty) {
        await ProfileScreen.open(context, userId: fallbackUserId);
      }
      return;
    }

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final row = await supabase
          .from('user_stories')
          .select('id, user_id, deleted_at, expires_at')
          .eq('id', cleanStoryId)
          .isFilter('deleted_at', null)
          .gt('expires_at', nowStr)
          .maybeSingle();

      if (row != null) {
        final ownerId = row['user_id']?.toString() ?? '';
        String username = 'user';
        String avatarUrl = '';
        if (ownerId.isNotEmpty) {
          final prof = await supabase
              .from('profiles')
              .select('username, avatar_url')
              .eq('id', ownerId)
              .maybeSingle();
          if (prof != null) {
            username = (prof['username'] ?? 'user').toString();
            avatarUrl = (prof['avatar_url'] ?? '').toString();
          }
        }
        if (!context.mounted) return;
        await open(
          context,
          friendStory: ActiveFriendStory(
            userId: ownerId,
            username: username,
            avatarUrl: avatarUrl,
            storiesCount: 1,
            isMe: ownerId == supabase.auth.currentUser?.id,
          ),
          initialStoryId: cleanStoryId,
        );
        return;
      }
    } catch (e) {
      debugPrint('openByStoryId notice: $e');
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('This story has expired or is no longer available.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final currentUserId = supabase.auth.currentUser?.id;
    if (fallbackUserId != null &&
        fallbackUserId.isNotEmpty &&
        fallbackUserId != currentUserId) {
      await ProfileScreen.open(context, userId: fallbackUserId);
    }
  }

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;

  late int _currentFriendIndex;
  late ActiveFriendStory _currentFriendStory;
  String? _pendingInitialStoryId;

  String _ownerUsername = '';
  String _ownerAvatarUrl = '';
  bool _ownerIsVerified = false;

  List<Map<String, dynamic>> _stories = [];
  bool _isLoading = true;
  int _currentIndex = 0;

  late final AnimationController _progressAnimCtrl;
  bool _isPaused = false;
  DateTime? _pointerDownTime;
  final TextEditingController _replyCtrl = TextEditingController();
  final FocusNode _replyFocus = FocusNode();

  final Set<String> _recordedViewIds = <String>{};
  final Set<String> _likedStoryIds = <String>{};
  final Map<String, String> _myReactionByStoryId = <String, String>{};
  bool _isSendingReply = false;

  VideoPlayerController? _videoPlayerCtrl;
  bool _isVideoInitialized = false;
  ZevSponsoredAd? _currentSponsoredStoryAd;

  static const List<String> _quickEmojis = ['❤️', '🔥', '😂', '😮', '😢', '👏'];

  String? get _currentUserId => supabase.auth.currentUser?.id;
  bool get _isOwner =>
      _currentUserId != null && _currentUserId == _currentFriendStory.userId;

  @override
  void initState() {
    super.initState();
    _currentFriendIndex = widget.initialFriendIndex;
    _currentFriendStory = widget.friendStory;
    _pendingInitialStoryId = widget.initialStoryId;
    _ownerUsername = _currentFriendStory.username;
    _ownerAvatarUrl = _currentFriendStory.avatarUrl;

    _progressAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _progressAnimCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onStoryFinished();
      }
    });

    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) {
        _pauseStory();
      }
    });

    _fetchUserStories();
  }

  @override
  void dispose() {
    _progressAnimCtrl.dispose();
    _videoPlayerCtrl?.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchOwnerProfile() async {
    try {
      final prof = await supabase
          .from('profiles')
          .select('username, avatar_url, is_verified')
          .eq('id', _currentFriendStory.userId)
          .maybeSingle();
      if (prof != null && mounted) {
        setState(() {
          final uname = (prof['username'] ?? '').toString();
          final av = (prof['avatar_url'] ?? '').toString();
          if (uname.isNotEmpty) _ownerUsername = uname;
          if (av.isNotEmpty) _ownerAvatarUrl = av;
          _ownerIsVerified = prof['is_verified'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchUserStories() async {
    _ownerUsername = _currentFriendStory.username;
    _ownerAvatarUrl = _currentFriendStory.avatarUrl;
    _ownerIsVerified = false;
    unawaited(_fetchOwnerProfile());

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final res = await supabase
          .from('user_stories')
          .select(
            'id, media_url, media_type, caption, visibility, views_count, likes_count, replies_count, created_at, expires_at',
          )
          .eq('user_id', _currentFriendStory.userId)
          .isFilter('deleted_at', null)
          .gt('expires_at', nowStr)
          .order('created_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(res as List);
      if (!mounted) return;

      // Native Ad Insertion Rules (In-Stream Story Monetization)
      if (!_isOwner) {
        if (list.length >= 3) {
          list.insert(2, {
            'id': 'ad_story_${_currentFriendStory.userId}',
            'is_ad': true,
            'media_type': 'ad',
            'caption': '',
          });
        } else if (widget.allFriendStories != null &&
            widget.allFriendStories!.length > 1 &&
            _currentFriendIndex % 2 == 1 &&
            list.isNotEmpty) {
          list.add({
            'id': 'ad_between_${_currentFriendStory.userId}',
            'is_ad': true,
            'media_type': 'ad',
            'caption': '',
          });
        }
      }

      int startIdx = 0;
      if (_pendingInitialStoryId != null && _pendingInitialStoryId!.isNotEmpty) {
        final matchIdx = list.indexWhere(
          (s) => s['id']?.toString() == _pendingInitialStoryId,
        );
        if (matchIdx != -1) startIdx = matchIdx;
        _pendingInitialStoryId = null;
      }

      setState(() {
        _stories = list;
        _currentIndex = startIdx;
        _isLoading = false;
      });

      if (list.isNotEmpty) {
        _setupCurrentStory();
      } else {
        _advanceToNextFriendOrClose();
      }
    } catch (e) {
      debugPrint('Fetch stories error: $e');
      if (mounted) _advanceToNextFriendOrClose();
    }
  }

  void _setupCurrentStory() {
    if (_stories.isEmpty || _currentIndex >= _stories.length) return;

    _videoPlayerCtrl?.pause();
    _videoPlayerCtrl?.dispose();
    _videoPlayerCtrl = null;
    _isVideoInitialized = false;
    _currentSponsoredStoryAd = null;

    final currentStory = _stories[_currentIndex];
    final isAd = currentStory['is_ad'] == true;

    if (isAd) {
      _progressAnimCtrl.duration = const Duration(seconds: 5);
      _progressAnimCtrl.forward(from: 0.0);
      return;
    }

    final storyId = currentStory['id']?.toString() ?? '';
    if (storyId.isNotEmpty) {
      if (_currentUserId != null && !_isOwner) {
        unawaited(_recordView(storyId));
        unawaited(_loadViewerInteractionState(storyId));
      }
    }

    final mediaUrl = currentStory['media_url'] as String? ?? '';
    final mediaType = currentStory['media_type'] as String? ?? 'image';

    final isVideo =
        mediaType == 'video' ||
        mediaUrl.toLowerCase().contains('.mp4') ||
        mediaUrl.toLowerCase().contains('.mov') ||
        mediaUrl.toLowerCase().contains('.webm');

    if (isVideo && mediaUrl.isNotEmpty) {
      _progressAnimCtrl.stop();
      _videoPlayerCtrl = VideoPlayerController.networkUrl(Uri.parse(mediaUrl))
        ..initialize()
            .then((_) {
              if (!mounted) return;
              final videoDuration = _videoPlayerCtrl!.value.duration;
              setState(() {
                _isVideoInitialized = true;
                _progressAnimCtrl.duration = videoDuration > Duration.zero
                    ? videoDuration
                    : const Duration(seconds: 5);
              });
              if (!_isPaused) {
                _videoPlayerCtrl!.play();
                _progressAnimCtrl.forward(from: 0.0);
              }
            })
            .catchError((err) {
              debugPrint('Story video playback error: $err');
              if (!mounted) return;
              _progressAnimCtrl.duration = const Duration(seconds: 5);
              _progressAnimCtrl.forward(from: 0.0);
            });
    } else {
      _progressAnimCtrl.duration = const Duration(seconds: 5);
      _progressAnimCtrl.forward(from: 0.0);
    }
  }

  Future<void> _recordView(String storyId) async {
    if (_recordedViewIds.contains(storyId)) return;
    _recordedViewIds.add(storyId);
    try {
      await supabase.rpc('record_story_view', params: {'p_story_id': storyId});
    } catch (e) {
      debugPrint('record_story_view notice: $e');
    }
  }

  Future<void> _loadViewerInteractionState(String storyId) async {
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      final results = await Future.wait<dynamic>([
        supabase
            .from('story_likes')
            .select('id')
            .eq('story_id', storyId)
            .eq('user_id', uid)
            .maybeSingle(),
        supabase
            .from('story_reactions')
            .select('emoji')
            .eq('story_id', storyId)
            .eq('user_id', uid)
            .maybeSingle(),
      ]);

      if (!mounted) return;
      final likeRow = results[0] as Map<String, dynamic>?;
      final reactionRow = results[1] as Map<String, dynamic>?;
      setState(() {
        if (likeRow != null) {
          _likedStoryIds.add(storyId);
        } else {
          _likedStoryIds.remove(storyId);
        }
        final emoji = reactionRow?['emoji']?.toString();
        if (emoji != null && emoji.isNotEmpty) {
          _myReactionByStoryId[storyId] = emoji;
        }
      });
    } catch (_) {}
  }

  void _onStoryFinished() {
    if (_currentIndex < _stories.length - 1) {
      setState(() => _currentIndex++);
      _setupCurrentStory();
    } else {
      _advanceToNextFriendOrClose();
    }
  }

  void _nextStory() {
    HapticFeedback.lightImpact();
    if (_currentIndex < _stories.length - 1) {
      setState(() => _currentIndex++);
      _setupCurrentStory();
    } else {
      _advanceToNextFriendOrClose();
    }
  }

  void _previousStory() {
    HapticFeedback.lightImpact();
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _setupCurrentStory();
    } else {
      _retreatToPreviousFriendOrRestart();
    }
  }

  void _advanceToNextFriendOrClose() {
    if (widget.allFriendStories != null &&
        _currentFriendIndex < widget.allFriendStories!.length - 1) {
      setState(() {
        _currentFriendIndex++;
        _currentFriendStory = widget.allFriendStories![_currentFriendIndex];
        _currentIndex = 0;
        _isLoading = true;
      });
      _fetchUserStories();
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  void _retreatToPreviousFriendOrRestart() {
    if (widget.allFriendStories != null && _currentFriendIndex > 0) {
      setState(() {
        _currentFriendIndex--;
        _currentFriendStory = widget.allFriendStories![_currentFriendIndex];
        _currentIndex = 0;
        _isLoading = true;
      });
      _fetchUserStories();
    } else {
      _setupCurrentStory();
    }
  }

  void _pauseStory() {
    if (!_isPaused) {
      _isPaused = true;
      _progressAnimCtrl.stop();
      _videoPlayerCtrl?.pause();
    }
  }

  void _resumeStory() {
    if (_isPaused) {
      _isPaused = false;
      _progressAnimCtrl.forward();
      _videoPlayerCtrl?.play();
    }
  }

  Future<void> _toggleLikeStory(String storyId) async {
    final uid = _currentUserId;
    if (uid == null) {
      _showNotice('Please sign in to like stories.');
      return;
    }

    HapticFeedback.lightImpact();
    final wasLiked = _likedStoryIds.contains(storyId);
    setState(() {
      if (wasLiked) {
        _likedStoryIds.remove(storyId);
      } else {
        _likedStoryIds.add(storyId);
      }
    });

    try {
      if (wasLiked) {
        await supabase
            .from('story_likes')
            .delete()
            .eq('story_id', storyId)
            .eq('user_id', uid);
      } else {
        await supabase.from('story_likes').upsert(
          {'story_id': storyId, 'user_id': uid},
          onConflict: 'story_id,user_id',
        );
        if (!_isOwner) {
          unawaited(
            NotificationService().dispatchPushNotification(
              recipientUserId: _currentFriendStory.userId,
              title: 'Story Liked',
              body: 'liked your story on ZEV.',
              notificationType: 'story_like',
              deepLink: '/story/$storyId',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Story like error: $e');
      if (mounted) {
        setState(() {
          if (wasLiked) {
            _likedStoryIds.add(storyId);
          } else {
            _likedStoryIds.remove(storyId);
          }
        });
      }
    }
  }

  Future<void> _sendEmojiReaction(String storyId, String emoji) async {
    final uid = _currentUserId;
    if (uid == null) {
      _showNotice('Please sign in to react to stories.');
      return;
    }

    HapticFeedback.mediumImpact();
    final prev = _myReactionByStoryId[storyId];
    setState(() => _myReactionByStoryId[storyId] = emoji);

    try {
      await supabase.from('story_reactions').upsert(
        {'story_id': storyId, 'user_id': uid, 'emoji': emoji},
        onConflict: 'story_id,user_id',
      );
      if (!_isOwner) {
        unawaited(
          NotificationService().dispatchPushNotification(
            recipientUserId: _currentFriendStory.userId,
            title: 'Story Reaction',
            body: 'reacted $emoji to your story.',
            notificationType: 'story_reaction',
            deepLink: '/story/$storyId',
          ),
        );
      }
      _showNotice('Sent $emoji reaction');
    } catch (e) {
      debugPrint('Story reaction error: $e');
      if (mounted) {
        setState(() {
          if (prev != null) {
            _myReactionByStoryId[storyId] = prev;
          } else {
            _myReactionByStoryId.remove(storyId);
          }
        });
      }
    }
  }

  Future<void> _sendReply(String storyId) async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _isSendingReply) return;

    final uid = _currentUserId;
    if (uid == null) {
      _showNotice('Please sign in to reply to stories.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isSendingReply = true);
    _replyCtrl.clear();
    FocusScope.of(context).unfocus();

    try {
      await supabase.from('story_replies').insert({
        'story_id': storyId,
        'sender_id': uid,
        'reply_text': text,
      });

      if (!_isOwner) {
        unawaited(
          NotificationService().dispatchPushNotification(
            recipientUserId: _currentFriendStory.userId,
            title: 'Story Reply',
            body: 'replied to your story: "$text"',
            notificationType: 'story_reply',
            deepLink: '/story/$storyId',
          ),
        );
      }
      _showNotice('Reply sent to @$_ownerUsername');
    } catch (e) {
      debugPrint('Story reply error: $e');
      _showNotice('Could not send reply right now.');
    } finally {
      if (mounted) {
        setState(() => _isSendingReply = false);
        _resumeStory();
      }
    }
  }

  Future<void> _muteUserStories() async {
    final uid = _currentUserId;
    if (uid == null || _isOwner) return;
    try {
      await supabase.from('story_mutes').upsert(
        {'user_id': uid, 'muted_user_id': _currentFriendStory.userId},
        onConflict: 'user_id,muted_user_id',
      );
      _showNotice('Muted stories from @$_ownerUsername');
      _advanceToNextFriendOrClose();
    } catch (e) {
      debugPrint('Mute story error: $e');
      _showNotice('Could not mute stories.');
    }
  }

  Future<void> _deleteCurrentStory(String storyId) async {
    final uid = _currentUserId;
    if (uid == null || !_isOwner) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Story?',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: ZevColors.deepNavy,
          ),
        ),
        content: const Text(
          'This story will be removed from your active stories.',
          style: TextStyle(color: ZevColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: ZevColors.errorRed,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await supabase
          .from('user_stories')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', storyId)
          .eq('user_id', uid);

      if (!mounted) return;
      _showNotice('Story deleted.');
      setState(() {
        _stories.removeWhere((s) => s['id']?.toString() == storyId);
        if (_stories.isEmpty) {
          _currentIndex = 0;
        } else if (_currentIndex >= _stories.length) {
          _currentIndex = _stories.length - 1;
        }
      });

      if (_stories.isEmpty) {
        Navigator.pop(context);
      } else {
        _setupCurrentStory();
      }
    } catch (e) {
      debugPrint('Delete story error: $e');
      _showNotice('Could not delete story.');
    }
  }

  Future<void> _openInsightsSheet(String storyId) async {
    _pauseStory();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryInsightsSheet(
        storyId: storyId,
        supabase: supabase,
      ),
    );
    if (mounted) _resumeStory();
  }

  Future<void> _openSaveToHighlightSheet(Map<String, dynamic> story) async {
    final uid = _currentUserId;
    if (uid == null) return;
    _pauseStory();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _SaveStoryToHighlightSheet(
        userId: uid,
        story: story,
        onSaved: (title) => _showNotice('Saved to "$title" highlight'),
      ),
    );
    if (mounted) _resumeStory();
  }

  Future<void> _openOptionsMenu(Map<String, dynamic> story) async {
    final storyId = story['id']?.toString() ?? '';
    if (storyId.isEmpty) return;

    _pauseStory();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        decoration: const BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ZevColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              if (_isOwner) ...[
                _buildOptionTile(
                  icon: Icons.visibility_outlined,
                  title: 'Story Insights & Viewers',
                  color: ZevColors.deepNavy,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openInsightsSheet(storyId);
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.bookmark_add_outlined,
                  title: 'Save to Highlight',
                  color: ZevColors.deepNavy,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openSaveToHighlightSheet(story);
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.star_outline_rounded,
                  title: 'Manage Close Friends',
                  color: ZevColors.successGreen,
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await CloseFriendsSheet.show(context);
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete Story',
                  color: ZevColors.errorRed,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _deleteCurrentStory(storyId);
                  },
                ),
              ] else ...[
                _buildOptionTile(
                  icon: Icons.person_outline_rounded,
                  title: 'View @$_ownerUsername\'s Profile',
                  color: ZevColors.deepNavy,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    ProfileScreen.open(
                      context,
                      userId: _currentFriendStory.userId,
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.volume_off_outlined,
                  title: 'Mute @$_ownerUsername\'s Stories',
                  color: ZevColors.deepNavy,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _muteUserStories();
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.flag_outlined,
                  title: 'Report Story',
                  color: ZevColors.errorRed,
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await SocialGraphService.instance.showReportSheet(
                      context,
                      targetType: 'story',
                      targetId: storyId,
                      reportedUserId: _currentFriendStory.userId,
                      targetLabel: 'Story',
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (mounted) _resumeStory();
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: ZevColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  void _showNotice(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: ZevColors.primaryBlue,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_stories.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No active stories',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      );
    }

    final currentStory = _stories[_currentIndex];
    final storyId = currentStory['id']?.toString() ?? '';
    final isAd = currentStory['is_ad'] == true;
    final mediaUrl = currentStory['media_url'] as String? ?? '';
    final mediaType = currentStory['media_type'] as String? ?? 'image';
    final caption = currentStory['caption'] as String? ?? '';
    final isCloseFriends =
        !isAd && currentStory['visibility']?.toString() == 'close_friends';
    final viewsCount = (currentStory['views_count'] as num?)?.toInt() ?? 0;
    final likesCount = (currentStory['likes_count'] as num?)?.toInt() ?? 0;
    final repliesCount = (currentStory['replies_count'] as num?)?.toInt() ?? 0;
    final createdAtStr = currentStory['created_at'] as String?;
    final timeStr = createdAtStr != null
        ? TimeAgo.format(DateTime.tryParse(createdAtStr) ?? DateTime.now())
        : 'Just now';

    final isVideo =
        !isAd &&
        (mediaType == 'video' ||
            mediaUrl.toLowerCase().contains('.mp4') ||
            mediaUrl.toLowerCase().contains('.mov') ||
            mediaUrl.toLowerCase().contains('.webm'));

    final isRtl = TextDirectionHelper.isRtl(caption);
    final isLiked = _likedStoryIds.contains(storyId);
    final myEmoji = _myReactionByStoryId[storyId];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Story Media Canvas
            Center(
              child: isAd
                  ? ZevNativeAdStoryUnit(
                      key: ValueKey('story_ad_$storyId'),
                      slotKey: 'story_$storyId',
                      onSponsoredAdLoaded: (ad) {
                        if (!mounted) return;
                        setState(() => _currentSponsoredStoryAd = ad);
                      },
                      onAdFailed: () {
                        if (mounted) _nextStory();
                      },
                    )
                  : (isVideo
                        ? (_isVideoInitialized && _videoPlayerCtrl != null
                              ? SizedBox.expand(
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                      width: _videoPlayerCtrl!.value.size.width,
                                      height:
                                          _videoPlayerCtrl!.value.size.height,
                                      child: VideoPlayer(_videoPlayerCtrl!),
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: CircularProgressIndicator(
                                    color: ZevColors.primaryBlue,
                                    strokeWidth: 2,
                                  ),
                                ))
                        : (mediaUrl.isNotEmpty
                              ? ZevCachedImage(
                                  imageUrl: mediaUrl,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  height: double.infinity,
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: Colors.white24,
                                    size: 48,
                                  ),
                                ))),
            ),

            // 2. Tap-to-skip & Hold-to-pause Gesture Overlay
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  _pointerDownTime = DateTime.now();
                  _pauseStory();
                },
                onPointerUp: (e) {
                  final downTime = _pointerDownTime;
                  _resumeStory();
                  if (downTime != null) {
                    final elapsed =
                        DateTime.now().difference(downTime).inMilliseconds;
                    if (elapsed < 250) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      if (e.position.dx < screenWidth * 0.3) {
                        _previousStory();
                      } else {
                        _nextStory();
                      }
                    }
                  }
                },
                onPointerCancel: (_) => _resumeStory(),
                child: const SizedBox.expand(),
              ),
            ),

            // 3. Top Gradient Shadow
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),

            // 4. Segmented Progress Bars
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(_stories.length, (index) {
                  final isItemAd = _stories[index]['is_ad'] == true;
                  final isCf =
                      !isItemAd &&
                      _stories[index]['visibility'] == 'close_friends';
                  final activeColor = isItemAd
                      ? const Color(0xFF00D4FF)
                      : (isCf ? const Color(0xFF10B981) : Colors.white);

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 2.5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: index < _currentIndex
                            ? Container(color: activeColor)
                            : index == _currentIndex
                            ? AnimatedBuilder(
                                animation: _progressAnimCtrl,
                                builder: (context, _) {
                                  return LinearProgressIndicator(
                                    value: _progressAnimCtrl.value,
                                    backgroundColor: Colors.white30,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      activeColor,
                                    ),
                                  );
                                },
                              )
                            : Container(color: Colors.white30),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // 5. Header
            Positioned(
              top: 22,
              left: 14,
              right: 10,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: isAd
                        ? null
                        : () => ProfileScreen.open(
                            context,
                            userId: _currentFriendStory.userId,
                          ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isAd)
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF00D4FF), Color(0xFF0072FF)],
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.campaign_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                          )
                        else if (_ownerAvatarUrl.isNotEmpty)
                          ZevCachedImage.avatar(
                            imageUrl: _ownerAvatarUrl,
                            size: 34,
                          )
                        else
                          const CircleAvatar(
                            radius: 17,
                            backgroundColor: Colors.white24,
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    isAd
                                        ? (_currentSponsoredStoryAd
                                                  ?.businessName ??
                                              'Sponsored')
                                        : _ownerUsername,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (isAd || _ownerIsVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.verified_rounded,
                                    size: 14,
                                    color: Color(0xFF00D4FF),
                                  ),
                                ],
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isAd ? 'Advertisement' : timeStr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                                if (isCloseFriends) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ZevColors.successGreen,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.star_rounded,
                                          size: 10,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 2),
                                        Text(
                                          'Close Friends',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (!isAd)
                    IconButton(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => _openOptionsMenu(currentStory),
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 6. Caption Overlay
            if (!isAd && caption.isNotEmpty)
              Positioned(
                bottom: _isOwner ? 92 : 122,
                left: 20,
                right: 20,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      caption,
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                      textDirection:
                          isRtl ? TextDirection.rtl : TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),

            // 7. Bottom Controls (Sponsored CTA / Owner Insights+Highlight / Viewer Reactions+Reply)
            Positioned(
              bottom: 12,
              left: 14,
              right: 14,
              child: isAd
                  ? _buildAdCta(storyId)
                  : (_isOwner
                        ? _buildOwnerBottomBar(
                            currentStory: currentStory,
                            storyId: storyId,
                            viewsCount: viewsCount,
                            likesCount: likesCount,
                            repliesCount: repliesCount,
                          )
                        : _buildViewerBottomBar(
                            storyId: storyId,
                            isLiked: isLiked,
                            myEmoji: myEmoji,
                          )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdCta(String storyId) {
    final sponsored = _currentSponsoredStoryAd;
    if (sponsored != null) {
      return Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _pauseStory();
                ZevAdsService.instance.openAdDestination(
                  slotKey: 'story_$storyId',
                  ad: sponsored,
                );
              },
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: ZevColors.brandGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        sponsored.ctaLabel.isNotEmpty
                            ? sponsored.ctaLabel
                            : 'Learn More',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.open_in_new_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _nextStory();
            },
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: ZevColors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ZevColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Continue',
                    style: TextStyle(
                      color: ZevColors.deepNavy,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: ZevColors.deepNavy,
                    size: 12,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _nextStory();
      },
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D4FF), Color(0xFF0072FF)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Learn More & Continue',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerBottomBar({
    required Map<String, dynamic> currentStory,
    required String storyId,
    required int viewsCount,
    required int likesCount,
    required int repliesCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _openInsightsSheet(storyId),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white30),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Seen by $viewsCount${likesCount > 0 ? '  •  $likesCount ❤️' : ''}${repliesCount > 0 ? '  •  $repliesCount 💬' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _openSaveToHighlightSheet(currentStory),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: ZevColors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bookmark_add_outlined,
                  color: ZevColors.deepNavy,
                  size: 18,
                ),
                SizedBox(width: 5),
                Text(
                  'Highlight',
                  style: TextStyle(
                    color: ZevColors.deepNavy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewerBottomBar({
    required String storyId,
    required bool isLiked,
    required String? myEmoji,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quick Emoji Reaction Strip
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _quickEmojis.map((emoji) {
              final selected = myEmoji == emoji;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => _sendEmojiReaction(storyId, emoji),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? ZevColors.primaryBlue.withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected ? ZevColors.primaryBlue : Colors.white24,
                      ),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 16)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white30, width: 1.0),
                ),
                child: TextField(
                  controller: _replyCtrl,
                  focusNode: _replyFocus,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onTap: _pauseStory,
                  onSubmitted: (_) => _sendReply(storyId),
                  decoration: InputDecoration(
                    hintText: 'Reply to @$_ownerUsername...',
                    hintStyle: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _toggleLikeStory(storyId),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.16),
                  border: Border.all(
                    color: isLiked ? Colors.redAccent : Colors.white30,
                  ),
                ),
                child: Center(
                  child: Icon(
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isLiked ? Colors.redAccent : Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _sendReply(storyId),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: ZevColors.brandGradient,
                ),
                child: Center(
                  child: _isSendingReply
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Light Clearmorphic Story Insights & Viewers sheet for story owners.
class _StoryInsightsSheet extends StatefulWidget {
  final String storyId;
  final SupabaseClient supabase;

  const _StoryInsightsSheet({
    required this.storyId,
    required this.supabase,
  });

  @override
  State<_StoryInsightsSheet> createState() => _StoryInsightsSheetState();
}

class _StoryInsightsSheetState extends State<_StoryInsightsSheet> {
  bool _loading = true;
  int _tab = 0; // 0: Viewers, 1: Reactions, 2: Replies
  int _viewsCount = 0;
  int _likesCount = 0;
  int _repliesCount = 0;
  List<Map<String, dynamic>> _viewers = [];
  List<Map<String, dynamic>> _reactions = [];
  List<Map<String, dynamic>> _replies = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.supabase.rpc(
        'get_story_insights_and_viewers',
        params: {'p_story_id': widget.storyId},
      );
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _viewsCount = (map['views_count'] as num?)?.toInt() ?? 0;
        _likesCount = (map['likes_count'] as num?)?.toInt() ?? 0;
        _repliesCount = (map['replies_count'] as num?)?.toInt() ?? 0;
        _viewers = (map['viewers'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _reactions = (map['reactions'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _replies = (map['replies'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Story insights load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: ZevColors.softSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ZevColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  const Text(
                    'Story Activity',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const Spacer(),
                  _statPill(Icons.visibility_outlined, '$_viewsCount'),
                  const SizedBox(width: 6),
                  _statPill(Icons.favorite_rounded, '$_likesCount'),
                  const SizedBox(width: 6),
                  _statPill(Icons.chat_bubble_outline_rounded, '$_repliesCount'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  _tabButton(0, 'Viewers (${_viewers.length})'),
                  const SizedBox(width: 8),
                  _tabButton(1, 'Reactions (${_reactions.length})'),
                  const SizedBox(width: 8),
                  _tabButton(2, 'Replies (${_replies.length})'),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: 5,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, _) => const ZevSkeleton(
                        width: double.infinity,
                        height: 58,
                      ),
                    )
                  : _tab == 0
                  ? _buildViewersList()
                  : _tab == 1
                  ? _buildReactionsList()
                  : _buildRepliesList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statPill(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZevColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ZevColors.secondaryBlue),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int idx, String label) {
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? ZevColors.primaryBlue : ZevColors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: active ? ZevColors.primaryBlue : ZevColors.border,
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active ? ZevColors.deepNavy : ZevColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewersList() {
    if (_viewers.isEmpty) {
      return _emptyText('No viewers yet.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: _viewers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final v = _viewers[idx];
        final uid = v['viewer_id']?.toString() ?? '';
        final username = (v['username'] ?? 'user').toString();
        final full = (v['full_name'] ?? '').toString();
        final avatar = (v['avatar_url'] ?? '').toString();
        final hasLiked = v['has_liked'] == true;
        final emoji = v['reaction_emoji']?.toString();
        final viewedAt = DateTime.tryParse(v['viewed_at']?.toString() ?? '');

        return _personTile(
          userId: uid,
          avatarUrl: avatar,
          username: username,
          subtitle: full.isNotEmpty
              ? '$full • ${viewedAt != null ? TimeAgo.format(viewedAt) : ''}'
              : (viewedAt != null ? TimeAgo.format(viewedAt) : ''),
          isVerified: v['is_verified'] == true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null && emoji.isNotEmpty)
                Text(emoji, style: const TextStyle(fontSize: 18)),
              if (hasLiked) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.favorite_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildReactionsList() {
    if (_reactions.isEmpty) {
      return _emptyText('No emoji reactions yet.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: _reactions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final r = _reactions[idx];
        final uid = r['user_id']?.toString() ?? '';
        final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
        return _personTile(
          userId: uid,
          avatarUrl: (r['avatar_url'] ?? '').toString(),
          username: (r['username'] ?? 'user').toString(),
          subtitle: dt != null ? TimeAgo.format(dt) : '',
          isVerified: r['is_verified'] == true,
          trailing: Text(
            (r['emoji'] ?? '❤️').toString(),
            style: const TextStyle(fontSize: 22),
          ),
        );
      },
    );
  }

  Widget _buildRepliesList() {
    if (_replies.isEmpty) {
      return _emptyText('No replies yet.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: _replies.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final r = _replies[idx];
        final uid = r['sender_id']?.toString() ?? '';
        final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
        return _personTile(
          userId: uid,
          avatarUrl: (r['avatar_url'] ?? '').toString(),
          username: (r['username'] ?? 'user').toString(),
          subtitle: '${r['reply_text'] ?? ''}${dt != null ? ' • ${TimeAgo.format(dt)}' : ''}',
          isVerified: false,
        );
      },
    );
  }

  Widget _personTile({
    required String userId,
    required String avatarUrl,
    required String username,
    required String subtitle,
    required bool isVerified,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: userId.isEmpty
          ? null
          : () => ProfileScreen.open(context, userId: userId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border),
        ),
        child: Row(
          children: [
            avatarUrl.isNotEmpty
                ? ZevCachedImage.avatar(imageUrl: avatarUrl, size: 40)
                : Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: ZevColors.softSurface,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: ZevColors.textMuted,
                      size: 20,
                    ),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 13,
                          color: ZevColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyText(String msg) {
    return Center(
      child: Text(
        msg,
        style: const TextStyle(
          fontSize: 13.5,
          color: ZevColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Light Clearmorphic picker to add the current story into an existing or new Highlight.
class _SaveStoryToHighlightSheet extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> story;
  final ValueChanged<String> onSaved;

  const _SaveStoryToHighlightSheet({
    required this.userId,
    required this.story,
    required this.onSaved,
  });

  @override
  State<_SaveStoryToHighlightSheet> createState() =>
      _SaveStoryToHighlightSheetState();
}

class _SaveStoryToHighlightSheetState
    extends State<_SaveStoryToHighlightSheet> {
  final StoryHighlightService _service = StoryHighlightService();
  final TextEditingController _titleCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<StoryHighlight> _highlights = [];

  @override
  void initState() {
    super.initState();
    _loadHighlights();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHighlights() async {
    final list = await _service.loadHighlights(widget.userId);
    if (mounted) {
      setState(() {
        _highlights = list;
        _loading = false;
      });
    }
  }

  StoryHighlightItem _buildItemFromStory() {
    final storyId = widget.story['id']?.toString();
    final mediaUrl = (widget.story['media_url'] ?? '').toString();
    final mediaType = (widget.story['media_type'] ?? 'image').toString();
    final caption = (widget.story['caption'] ?? '').toString();
    final createdAt =
        DateTime.tryParse(widget.story['created_at']?.toString() ?? '') ??
        DateTime.now();

    return StoryHighlightItem(
      id: generateUuidV4(),
      storyId: storyId,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      caption: caption,
      createdAt: createdAt,
    );
  }

  Future<void> _addToExisting(StoryHighlight existing) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final newItem = _buildItemFromStory();
      final alreadyExists =
          newItem.storyId != null &&
          existing.items.any((i) => i.storyId == newItem.storyId);
      final updatedItems = alreadyExists
          ? existing.items
          : [...existing.items, newItem];

      final cover = existing.coverUrl.isNotEmpty
          ? existing.coverUrl
          : newItem.mediaUrl;

      await _service.saveHighlight(
        widget.userId,
        StoryHighlight(
          id: existing.id,
          userId: widget.userId,
          title: existing.title,
          coverUrl: cover,
          createdAt: existing.createdAt,
          items: updatedItems,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved(existing.title);
    } catch (e) {
      debugPrint('Add to existing highlight error: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createNewHighlight() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final newItem = _buildItemFromStory();
      await _service.saveHighlight(
        widget.userId,
        StoryHighlight(
          id: generateUuidV4(),
          userId: widget.userId,
          title: title,
          coverUrl: newItem.mediaUrl,
          createdAt: DateTime.now(),
          items: [newItem],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved(title);
    } catch (e) {
      debugPrint('Create highlight error: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: ZevColors.softSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ZevColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Save to Highlight',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: ZevColors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        hintText: 'New highlight title...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _createNewHighlight,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(76, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const ZevSkeleton(width: double.infinity, height: 60)
            else if (_highlights.isNotEmpty) ...[
              const Text(
                'Or add to existing',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _highlights.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, idx) {
                    final h = _highlights[idx];
                    return GestureDetector(
                      onTap: () => _addToExisting(h),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: ZevColors.primaryBlue,
                                  width: 1.5,
                                ),
                                color: ZevColors.white,
                              ),
                              child: h.coverUrl.isNotEmpty
                                  ? ZevCachedImage.avatar(
                                      imageUrl: h.coverUrl,
                                      size: 56,
                                    )
                                  : const Icon(
                                      Icons.auto_awesome_rounded,
                                      color: ZevColors.primaryBlue,
                                    ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              h.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
