import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../profile/screens/profile_screen.dart';

/// Desktop Right Sidebar for wide screens (width >= 1080px).
/// Fills the wide canvas next to the feed with:
/// 1. Current User Profile Tile
/// 2. Suggested Creators ("Suggested for you")
/// 3. Live Trending Hashtags with real usage counts from `public.hashtags`
/// 4. Clean Footer Links & ZEV Copyright
class FeedDesktopRightSidebar extends StatefulWidget {
  final String myAvatarUrl;
  final String myUsername;
  final String myFullName;
  final bool isMyVerified;
  final List<Map<String, dynamic>> suggestedUsers;
  final Function(String userId)? onFollowToggled;

  const FeedDesktopRightSidebar({
    super.key,
    required this.myAvatarUrl,
    required this.myUsername,
    required this.myFullName,
    this.isMyVerified = false,
    this.suggestedUsers = const [],
    this.onFollowToggled,
  });

  @override
  State<FeedDesktopRightSidebar> createState() =>
      _FeedDesktopRightSidebarState();
}

class _FeedDesktopRightSidebarState extends State<FeedDesktopRightSidebar> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trendingHashtags = [];
  final Set<String> _followingIds = {};
  bool _isLoadingHashtags = true;

  @override
  void initState() {
    super.initState();
    _fetchTrendingHashtags();
  }

  Future<void> _fetchTrendingHashtags() async {
    try {
      final res = await _supabase
          .from('hashtags')
          .select('tag, posts_count, reels_count')
          .order('posts_count', ascending: false)
          .limit(8);

      if (mounted) {
        setState(() {
          _trendingHashtags = List<Map<String, dynamic>>.from(res as List);
          _isLoadingHashtags = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingHashtags = false);
      }
    }
  }

  Future<void> _toggleFollow(String targetUserId) async {
    HapticFeedback.lightImpact();
    setState(() {
      if (_followingIds.contains(targetUserId)) {
        _followingIds.remove(targetUserId);
      } else {
        _followingIds.add(targetUserId);
      }
    });

    try {
      await SocialGraphService.instance.toggleFollow(targetUserId);
      widget.onFollowToggled?.call(targetUserId);
    } catch (_) {
      // Revert if error
      if (mounted) {
        setState(() {
          if (_followingIds.contains(targetUserId)) {
            _followingIds.remove(targetUserId);
          } else {
            _followingIds.add(targetUserId);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final myUsername = widget.myUsername.isNotEmpty ? widget.myUsername : 'you';
    final myName = widget.myFullName.isNotEmpty ? widget.myFullName : myUsername;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 24, bottom: 40, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Current User Profile Card
          GestureDetector(
            onTap: () {
              if (currentUserId != null) {
                ProfileScreen.open(context, userId: currentUserId);
              }
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFE2E8F0),
                  backgroundImage: widget.myAvatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(widget.myAvatarUrl)
                      : null,
                  child: widget.myAvatarUrl.isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          size: 26,
                          color: ZevColors.textMuted,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              myUsername,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                          ),
                          if (widget.isMyVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: ZevColors.primaryBlue,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        myName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ZevColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (currentUserId != null) {
                      ProfileScreen.open(context, userId: currentUserId);
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 2. Suggested for you
          if (widget.suggestedUsers.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Suggested for you',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                  ),
                ),
                Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.deepNavy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...widget.suggestedUsers.take(4).map((user) {
              final uid = user['id']?.toString() ?? '';
              final uname = user['username']?.toString() ?? 'user';
              final name = user['name']?.toString() ?? uname;
              final avatar = user['avatar_url']?.toString() ?? '';
              final isVer = user['is_verified'] == true;
              final isFollowing = _followingIds.contains(uid);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => ProfileScreen.open(context, userId: uid),
                      child: CircleAvatar(
                        radius: 19,
                        backgroundColor: const Color(0xFFF1F5F9),
                        backgroundImage: avatar.isNotEmpty
                            ? CachedNetworkImageProvider(avatar)
                            : null,
                        child: avatar.isEmpty
                            ? const Icon(
                                Icons.person_rounded,
                                size: 20,
                                color: ZevColors.textMuted,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => ProfileScreen.open(context, userId: uid),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    uname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: ZevColors.deepNavy,
                                    ),
                                  ),
                                ),
                                if (isVer) ...[
                                  const SizedBox(width: 3),
                                  const Icon(
                                    Icons.verified_rounded,
                                    size: 13,
                                    color: ZevColors.primaryBlue,
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _toggleFollow(uid),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isFollowing
                              ? const Color(0xFFF1F5F9)
                              : const Color(0xFF0284C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isFollowing ? 'Following' : 'Follow',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isFollowing
                                ? const Color(0xFF64748B)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 18),
          ],

          // 3. Trending Topics in ZEV (Real live counts from database)
          if (!_isLoadingHashtags && _trendingHashtags.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.trending_up_rounded,
                        size: 18,
                        color: Color(0xFF0284C7),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Trending in ZEV',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._trendingHashtags.map((item) {
                    final rawTag = (item['tag'] ?? '').toString();
                    final cleanTag = rawTag.startsWith('#') ? rawTag : '#$rawTag';
                    final posts = (item['posts_count'] as num?)?.toInt() ?? 0;
                    final reels = (item['reels_count'] as num?)?.toInt() ?? 0;
                    final total = posts + reels;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            cleanTag,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              total > 0 ? '$total posts' : 'Trending',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 4. Clean Footer Links (Connected to official ZEV web pages)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: const [
              _FooterLink(text: 'About', url: 'https://zevapp.com/about'),
              _FooterDot(),
              _FooterLink(text: 'Help', url: 'https://zevapp.com/support'),
              _FooterDot(),
              _FooterLink(text: 'Press', url: 'https://zevapp.com/press'),
              _FooterDot(),
              _FooterLink(text: 'API', url: 'https://zevapp.com/api-info'),
              _FooterDot(),
              _FooterLink(text: 'Jobs', url: 'https://zevapp.com/jobs'),
              _FooterDot(),
              _FooterLink(text: 'Privacy', url: 'https://zevapp.com/privacy'),
              _FooterDot(),
              _FooterLink(text: 'Terms', url: 'https://zevapp.com/terms'),
              _FooterDot(),
              _FooterLink(text: 'Locations', url: 'https://zevapp.com/locations'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '© 2026 ZEV FROM SAHIB GROUP',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatefulWidget {
  final String text;
  final String url;
  const _FooterLink({required this.text, required this.url});

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _isHovered = false;

  Future<void> _openUrl() async {
    final uri = Uri.parse(widget.url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[FooterLink] Failed to launch ${widget.url}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _openUrl,
        child: Text(
          widget.text,
          style: TextStyle(
            fontSize: 11,
            color: _isHovered ? ZevColors.primaryBlue : const Color(0xFF94A3B8),
            fontWeight: _isHovered ? FontWeight.w700 : FontWeight.w500,
            decoration: _isHovered ? TextDecoration.underline : TextDecoration.none,
            decorationColor: ZevColors.primaryBlue,
          ),
        ),
      ),
    );
  }
}

class _FooterDot extends StatelessWidget {
  const _FooterDot();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '•',
      style: TextStyle(
        fontSize: 10,
        color: Color(0xFFCBD5E1),
      ),
    );
  }
}
