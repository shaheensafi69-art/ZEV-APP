import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/widgets/new_chat_sheet.dart';
import '../models/feed_post_item.dart';

/// Serene, Instagram-Grade Share Sheet for ZEV.
/// Modeled 1:1 from the official Instagram share sheet:
/// - Disclaimer telemetry notice at top
/// - Rounded pill search bar with Create Group icon
/// - Large circular friend avatars with direct send feedback
/// - Signature circular app pills (Add to story, Copy link, WhatsApp, Share, WhatsApp Status, More)
class FeedShareSheet extends StatefulWidget {
  final FeedPostItem post;
  final bool isReel;

  const FeedShareSheet({
    super.key,
    required this.post,
    this.isReel = false,
  });

  static void show(
    BuildContext context, {
    required FeedPostItem post,
    bool isReel = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedShareSheet(post: post, isReel: isReel),
    );
  }

  @override
  State<FeedShareSheet> createState() => _FeedShareSheetState();
}

class _FeedShareSheetState extends State<FeedShareSheet> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _allFriends = [];
  List<Map<String, dynamic>> _filteredFriends = [];
  final Set<String> _sentFriendIds = {};
  final Set<String> _sendingFriendIds = {};
  bool _isLoadingFriends = true;

  @override
  void initState() {
    super.initState();
    _fetchFriends();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredFriends = List.from(_allFriends);
      } else {
        _filteredFriends = _allFriends.where((f) {
          final u = (f['username'] ?? '').toString().toLowerCase();
          final n = (f['name'] ?? '').toString().toLowerCase();
          return u.contains(query) || n.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _fetchFriends() async {
    final user = supabase.auth.currentUser;
    try {
      final results = await Future.wait<dynamic>([
        SocialGraphService.instance.fetchSafetyFilters(),
        supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .neq('id', user?.id ?? '')
            .limit(30),
      ]);

      final filters = results[0] as UserSafetyFilters;
      final res = results[1] as List;

      final list = res
          .where((p) => !filters.blockedUserIds.contains(p['id']?.toString() ?? ''))
          .map((p) {
            final fn = p['first_name'] ?? '';
            final ln = p['last_name'] ?? '';
            final full = "$fn $ln".trim();
            return {
              'id': p['id'].toString(),
              'username': p['username'] ?? (full.isNotEmpty ? full : 'user'),
              'name': full.isNotEmpty ? full : (p['username'] ?? 'User'),
              'avatar_url': p['avatar_url'] ?? '',
              'is_verified': p['is_verified'] == true,
            };
          })
          .toList();

      if (mounted) {
        setState(() {
          _allFriends = list;
          _filteredFriends = list;
          _isLoadingFriends = false;
        });
      }
    } catch (e) {
      debugPrint("Share sheet friends query warning: $e");
      if (mounted) setState(() => _isLoadingFriends = false);
    }
  }

  Future<void> _sendToFriend(String friendId, String friendName) async {
    if (_sendingFriendIds.contains(friendId) || _sentFriendIds.contains(friendId)) {
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _sendingFriendIds.add(friendId);
      _sentFriendIds.add(friendId);
    });

    final preview = widget.post.title.isNotEmpty
        ? widget.post.title
        : widget.post.content;

    final ok = await ChatService.instance.sendSharedContentToUser(
      peerId: friendId,
      contentId: widget.post.id,
      isReel: widget.isReel,
      authorUsername: widget.post.authorUsername,
      previewText: preview,
      thumbnailUrl:
          widget.post.imageUrl.isNotEmpty ? widget.post.imageUrl : null,
    );

    if (!mounted) return;
    setState(() {
      _sendingFriendIds.remove(friendId);
      if (!ok) _sentFriendIds.remove(friendId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Sent to @$friendName'
              : 'Could not send to @$friendName. You may be restricted or blocked.',
        ),
        backgroundColor: ok ? ZevColors.deepNavy : ZevColors.errorRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openCreateGroupAndShare() {
    HapticFeedback.lightImpact();
    final preview = widget.post.title.isNotEmpty
        ? widget.post.title
        : widget.post.content;

    NewChatSheet.show(
      context,
      initialGroupMode: true,
      onSelectUser: (userId, username, avatarUrl, fullName, isVerified) {
        _sendToFriend(userId, username);
      },
      onCreateGroup: (conversationId, title) async {
        final ok = await ChatService.instance.sendSharedContentToConversation(
          conversationId: conversationId,
          isGroup: true,
          contentId: widget.post.id,
          isReel: widget.isReel,
          authorUsername: widget.post.authorUsername,
          previewText: preview,
          thumbnailUrl:
              widget.post.imageUrl.isNotEmpty ? widget.post.imageUrl : null,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Shared to group "$title"'
                  : 'Group "$title" created, but share failed.',
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }

  String get _postUrl {
    final type = widget.isReel ? "reel" : "post";
    return "https://www.zevapp.com/$type/${widget.post.id}";
  }

  String get _shareText {
    final title = widget.post.title.isNotEmpty ? "${widget.post.title}\n" : "";
    final content =
        widget.post.content.isNotEmpty ? "${widget.post.content}\n\n" : "";
    final mediaType = widget.isReel ? "reel" : "post";
    return "Check out @${widget.post.authorUsername}'s $mediaType on ZEV:\n$title$content$_postUrl";
  }

  Future<void> _launchExternalApp(String urlScheme, String webFallback) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(urlScheme);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final webUri = Uri.parse(webFallback);
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      final webUri = Uri.parse(webFallback);
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  void _shareViaWhatsApp() {
    final text = Uri.encodeComponent(_shareText);
    _launchExternalApp(
      "whatsapp://send?text=$text",
      "https://api.whatsapp.com/send?text=$text",
    );
  }

  void _copyPostLink() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _postUrl));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isReel
              ? "Reel link copied to clipboard"
              : "Post link copied to clipboard",
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openSystemNativeShare() async {
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
    await Share.share(_shareText, subject: widget.post.title);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.72,
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
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
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

          // 1. Instagram Disclaimer Notice (Light Mode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  color: ZevColors.textSecondary,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text:
                        "Links you share are unique to you and may be used to improve suggestions and ads you see. ",
                  ),
                  TextSpan(
                    text: "Learn more",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ZevColors.secondaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Clay Search Bar + Create Group Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(
                        fontSize: 14,
                        color: ZevColors.deepNavy,
                      ),
                      decoration: const InputDecoration(
                        hintText: "Search",
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: ZevColors.textMuted,
                          fontWeight: FontWeight.w400,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: ZevColors.textMuted,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.group_add_outlined,
                      color: ZevColors.deepNavy,
                      size: 22,
                    ),
                    onPressed: _openCreateGroupAndShare,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 3. Friends Avatars Grid (Light Mode)
          Expanded(
            child: _isLoadingFriends
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ZevColors.primaryBlue,
                    ),
                  )
                : _filteredFriends.isEmpty
                    ? const Center(
                        child: Text(
                          "No accounts found",
                          style: TextStyle(
                            fontSize: 13,
                            color: ZevColors.textMuted,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _filteredFriends.length,
                        itemBuilder: (context, index) {
                          final friend = _filteredFriends[index];
                          final id = friend['id'] as String;
                          final username = friend['username'] as String;
                          final avatar = friend['avatar_url'] as String;
                          final isVerified = friend['is_verified'] == true;
                          final isSent = _sentFriendIds.contains(id);

                          return GestureDetector(
                            onTap: () => _sendToFriend(id, username),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: ZevColors.border,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: avatar.isNotEmpty
                                          ? ZevCachedImage.avatar(
                                              imageUrl: avatar,
                                              size: 72,
                                            )
                                          : const CircleAvatar(
                                              radius: 36,
                                              backgroundColor:
                                                  ZevColors.softSurface,
                                              child: Icon(
                                                Icons.person_rounded,
                                                size: 36,
                                                color: ZevColors.textMuted,
                                              ),
                                            ),
                                    ),
                                    if (isSent)
                                      Positioned.fill(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.4),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            color: Color(0xFF10B981),
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        username,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: ZevColors.deepNavy,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
                                const SizedBox(height: 2),
                                Text(
                                  isSent ? "Sent" : "Send",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isSent
                                        ? const Color(0xFF10B981)
                                        : ZevColors.secondaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          const Divider(height: 1, thickness: 0.8, color: ZevColors.border),

          // 4. Bottom Circular Action Pills (Light Mode)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Add to Story
                  _buildCircleAction(
                    icon: Icons.add_circle_outline_rounded,
                    label: "Add to story",
                    bgColor: ZevColors.softSurface,
                    iconColor: ZevColors.deepNavy,
                    hasBorder: true,
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Added to story preview.")),
                      );
                    },
                  ),
                  const SizedBox(width: 16),

                  // Copy Link
                  _buildCircleAction(
                    icon: Icons.link_rounded,
                    label: "Copy link",
                    bgColor: ZevColors.softSurface,
                    iconColor: ZevColors.deepNavy,
                    hasBorder: true,
                    onTap: _copyPostLink,
                  ),
                  const SizedBox(width: 16),

                  // WhatsApp
                  _buildCircleAction(
                    icon: Icons.chat_rounded,
                    label: "WhatsApp",
                    bgColor: const Color(0xFF25D366),
                    iconColor: Colors.white,
                    onTap: _shareViaWhatsApp,
                  ),
                  const SizedBox(width: 16),

                  // Share (System)
                  _buildCircleAction(
                    icon: Icons.share_rounded,
                    label: "Share",
                    bgColor: ZevColors.softSurface,
                    iconColor: ZevColors.deepNavy,
                    hasBorder: true,
                    onTap: _openSystemNativeShare,
                  ),
                  const SizedBox(width: 16),

                  // WhatsApp Status
                  _buildCircleAction(
                    icon: Icons.adjust_rounded,
                    label: "WhatsApp Status",
                    bgColor: const Color(0xFF25D366),
                    iconColor: Colors.white,
                    onTap: _shareViaWhatsApp,
                  ),
                  const SizedBox(width: 16),

                  // More (Native Device Installed Apps)
                  _buildCircleAction(
                    icon: Icons.more_horiz_rounded,
                    label: "More",
                    bgColor: ZevColors.softSurface,
                    iconColor: ZevColors.deepNavy,
                    hasBorder: true,
                    onTap: _openSystemNativeShare,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleAction({
    required IconData icon,
    required String label,
    required Color bgColor,
    Color iconColor = Colors.white,
    bool hasBorder = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: hasBorder
                    ? Border.all(
                        color: ZevColors.border,
                        width: 1.0,
                      )
                    : null,
              ),
              child: Center(
                child: Icon(icon, color: iconColor, size: 24),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: ZevColors.deepNavy,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
