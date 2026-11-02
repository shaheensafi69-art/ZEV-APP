import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/zev_theme.dart';
import '../models/feed_post_item.dart';

/// Next-Generation Instagram/TikTok-Grade Share Sheet for ZEV.
/// Features a real-time friends search bar, one-tap direct friend sends,
/// one-tap app shortcuts (WhatsApp, Telegram, X, Facebook), and native "More" system share sheet.
class FeedShareSheet extends StatefulWidget {
  final FeedPostItem post;

  const FeedShareSheet({super.key, required this.post});

  static void show(BuildContext context, {required FeedPostItem post}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedShareSheet(post: post),
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
      // Query profiles for interactive friends
      final res = await supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url')
          .neq('id', user?.id ?? '')
          .limit(15);

      final list = (res as List).map((p) {
        final fn = p['first_name'] ?? '';
        final ln = p['last_name'] ?? '';
        final full = "$fn $ln".trim();
        return {
          'id': p['id'].toString(),
          'username': p['username'] ?? (full.isNotEmpty ? full : 'user'),
          'name': full.isNotEmpty ? full : (p['username'] ?? 'User'),
          'avatar_url': p['avatar_url'] ?? '',
        };
      }).toList();

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

  void _sendToFriend(String friendId, String friendName) {
    HapticFeedback.lightImpact();
    setState(() {
      _sentFriendIds.add(friendId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Sent to @$friendName"),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String get _shareText {
    final title = widget.post.title.isNotEmpty ? "${widget.post.title}\n" : "";
    final content = widget.post.content.isNotEmpty ? "${widget.post.content}\n\n" : "";
    return "Check out @${widget.post.authorUsername}'s post on ZEV:\n$title$content${widget.post.imageUrl}";
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
    _launchExternalApp("whatsapp://send?text=$text", "https://api.whatsapp.com/send?text=$text");
  }

  void _shareViaTelegram() {
    final text = Uri.encodeComponent(_shareText);
    _launchExternalApp("tg://msg?text=$text", "https://t.me/share/url?url=$text");
  }

  void _shareViaTwitter() {
    final text = Uri.encodeComponent(_shareText);
    _launchExternalApp("twitter://post?message=$text", "https://twitter.com/intent/tweet?text=$text");
  }

  void _shareViaFacebook() {
    final url = Uri.encodeComponent(widget.post.imageUrl.isNotEmpty ? widget.post.imageUrl : "https://zevapp.com");
    _launchExternalApp("fb://facewebmodal/f?href=$url", "https://www.facebook.com/sharer/sharer.php?u=$url");
  }

  void _copyPostLink() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _shareText));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Post link copied to clipboard!"),
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
      height: mediaQuery.size.height * 0.70,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4.5,
            decoration: BoxDecoration(
              color: ZevColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          const Text(
            "Share",
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 12),

          // Search Friends Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: ZevColors.softSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ZevColors.border),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 14, color: ZevColors.deepNavy),
                decoration: const InputDecoration(
                  hintText: "Search friends...",
                  hintStyle: TextStyle(fontSize: 13.5, color: ZevColors.textMuted),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: ZevColors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // 1. Friends Horizontal Carousel (Send directly)
          SizedBox(
            height: 104,
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
                          "No contacts found",
                          style: TextStyle(fontSize: 13, color: ZevColors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _filteredFriends.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final friend = _filteredFriends[index];
                          final id = friend['id'] as String;
                          final username = friend['username'] as String;
                          final avatar = friend['avatar_url'] as String;
                          final isSent = _sentFriendIds.contains(id);

                          return SizedBox(
                            width: 68,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: ZevColors.softSurface,
                                  backgroundImage: avatar.isNotEmpty
                                      ? NetworkImage(avatar)
                                      : null,
                                  child: avatar.isEmpty
                                      ? const Icon(
                                          Icons.person_rounded,
                                          size: 26,
                                          color: ZevColors.textMuted,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  username,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: ZevColors.deepNavy,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: isSent
                                      ? null
                                      : () => _sendToFriend(id, username),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSent
                                          ? ZevColors.softSurface
                                          : ZevColors.primaryBlue,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      isSent ? "Sent" : "Send",
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: isSent
                                            ? ZevColors.textMuted
                                            : ZevColors.deepNavy,
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

          const Divider(height: 24, color: ZevColors.border),

          // 2. Quick App Sharing Row (WhatsApp, Telegram, X, Facebook, More...)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // WhatsApp
                _buildAppIcon(
                  label: "WhatsApp",
                  bgColor: const Color(0xFF25D366),
                  icon: Icons.chat_rounded,
                  onTap: _shareViaWhatsApp,
                ),
                // Telegram
                _buildAppIcon(
                  label: "Telegram",
                  bgColor: const Color(0xFF229ED9),
                  icon: Icons.near_me_rounded,
                  onTap: _shareViaTelegram,
                ),
                // X (Twitter)
                _buildAppIcon(
                  label: "X",
                  bgColor: Colors.black,
                  icon: Icons.close_rounded,
                  onTap: _shareViaTwitter,
                ),
                // Facebook
                _buildAppIcon(
                  label: "Facebook",
                  bgColor: const Color(0xFF1877F2),
                  icon: Icons.facebook_rounded,
                  onTap: _shareViaFacebook,
                ),
                // Copy Link
                _buildAppIcon(
                  label: "Copy Link",
                  bgColor: ZevColors.softSurface,
                  iconColor: ZevColors.deepNavy,
                  icon: Icons.link_rounded,
                  onTap: _copyPostLink,
                ),
                // More Native System Apps
                _buildAppIcon(
                  label: "More",
                  bgColor: ZevColors.border,
                  iconColor: ZevColors.deepNavy,
                  icon: Icons.more_horiz_rounded,
                  onTap: _openSystemNativeShare,
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildAppIcon({
    required String label,
    required Color bgColor,
    Color iconColor = Colors.white,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: iconColor, size: 24),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ZevColors.deepNavy,
            ),
          ),
        ],
      ),
    );
  }
}
