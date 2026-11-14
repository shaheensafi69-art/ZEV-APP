import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/content_deletion_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../models/feed_post_item.dart';
import 'post_detail_screen.dart';

/// Light Clearmorphic Drafts & Scheduled Posts Manager for ZEV Creators.
/// Backed by PostgreSQL `get_my_drafts_and_scheduled_posts()` and
/// `publish_post_now(p_post_id)` RPCs, plus permanent R2-safe delete.
class DraftsScheduledScreen extends StatefulWidget {
  final VoidCallback? onPostPublished;

  const DraftsScheduledScreen({super.key, this.onPostPublished});

  static Future<bool?> open(
    BuildContext context, {
    VoidCallback? onPostPublished,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            DraftsScheduledScreen(onPostPublished: onPostPublished),
      ),
    );
  }

  @override
  State<DraftsScheduledScreen> createState() => _DraftsScheduledScreenState();
}

class _DraftsScheduledScreenState extends State<DraftsScheduledScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMsg;
  String _filter = 'all'; // 'all' | 'drafts' | 'scheduled'
  final Set<String> _busyIds = {};
  List<FeedPostItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Please sign in to manage drafts and scheduled posts.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _supabase.rpc('get_my_drafts_and_scheduled_posts'),
        _supabase
            .from('profiles')
            .select(
              'username, first_name, last_name, avatar_url, is_verified',
            )
            .eq('id', user.id)
            .maybeSingle(),
      ]);

      final rows = (results[0] is List)
          ? (results[0] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      final prof = results[1] is Map
          ? Map<String, dynamic>.from(results[1] as Map)
          : const <String, dynamic>{};

      final parsed = rows.map((r) {
        final merged = <String, dynamic>{
          ...r,
          'author_username': prof['username'] ?? 'me',
          'author_first_name': prof['first_name'] ?? '',
          'author_last_name': prof['last_name'] ?? '',
          'author_avatar_url': prof['avatar_url'] ?? '',
          'author_is_verified': prof['is_verified'] == true,
        };
        return FeedPostItem.fromRpcMap(merged);
      }).toList();

      if (!mounted) return;
      setState(() {
        _items = parsed;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('DraftsScheduledScreen load error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMsg = 'Could not load drafts & scheduled posts.';
      });
    }
  }

  Future<void> _publishNow(FeedPostItem post) async {
    if (_busyIds.contains(post.id)) return;
    HapticFeedback.mediumImpact();
    setState(() => _busyIds.add(post.id));

    try {
      await _supabase.rpc(
        'publish_post_now',
        params: {'p_post_id': post.id},
      );
      widget.onPostPublished?.call();
      if (!mounted) return;
      setState(() {
        _busyIds.remove(post.id);
        _items.removeWhere((p) => p.id == post.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Post published to your feed!',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: ZevColors.deepNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Publish now error: $e');
      if (!mounted) return;
      setState(() => _busyIds.remove(post.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to publish: $e'),
          backgroundColor: ZevColors.errorRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  Future<void> _deleteItem(FeedPostItem post) async {
    if (_busyIds.contains(post.id)) return;
    setState(() => _busyIds.add(post.id));
    final deleted = await ContentDeletionService.confirmAndDeletePost(
      context,
      post: post,
      onDeleted: () {
        if (mounted) {
          setState(() => _items.removeWhere((p) => p.id == post.id));
        }
      },
    );
    if (mounted) {
      setState(() {
        _busyIds.remove(post.id);
        if (deleted) _items.removeWhere((p) => p.id == post.id);
      });
    }
  }

  List<FeedPostItem> get _filteredItems {
    if (_filter == 'drafts') {
      return _items.where((p) => p.isDraft).toList();
    }
    if (_filter == 'scheduled') {
      return _items
          .where((p) => !p.isDraft && p.scheduledAt != null)
          .toList();
    }
    return _items;
  }

  String _formatScheduleDate(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = months[(local.month - 1).clamp(0, 11)];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$m ${local.day}, ${local.year} • $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final draftsCount = _items.where((p) => p.isDraft).length;
    final scheduledCount =
        _items.where((p) => !p.isDraft && p.scheduledAt != null).length;
    final visible = _filteredItems;
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ZevColors.deepNavy,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'Drafts & Scheduled',
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(
              Icons.refresh_rounded,
              color: ZevColors.deepNavy,
            ),
            onPressed: _loadItems,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 680 : double.infinity,
            ),
            child: Column(
              children: [
                if (isDesktop) const SizedBox(height: 12),
                // Filter Pills Bar
                Container(
                  margin: isDesktop
                      ? const EdgeInsets.symmetric(horizontal: 16)
                      : EdgeInsets.zero,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  decoration: BoxDecoration(
                    color: ZevColors.white,
                    borderRadius: isDesktop
                        ? BorderRadius.circular(16)
                        : BorderRadius.zero,
                    border: isDesktop
                        ? Border.all(color: ZevColors.border)
                        : null,
                    boxShadow: isDesktop
                        ? [
                            BoxShadow(
                              color: ZevColors.deepNavy.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      _buildFilterChip(
                        keyId: 'all',
                        label: 'All (${_items.length})',
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        keyId: 'drafts',
                        label: 'Drafts ($draftsCount)',
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        keyId: 'scheduled',
                        label: 'Scheduled ($scheduledCount)',
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: _isLoading
                      ? ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: 3,
                          itemBuilder: (_, _) => const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: ZevFeedCardSkeleton(),
                          ),
                        )
                      : _errorMsg != null
                          ? _buildErrorState()
                          : visible.isEmpty
                              ? _buildEmptyState()
                              : RefreshIndicator(
                                  color: ZevColors.primaryBlue,
                                  onRefresh: _loadItems,
                                  child: ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(
                                      parent: BouncingScrollPhysics(),
                                    ),
                                    padding:
                                        const EdgeInsets.fromLTRB(16, 14, 16, 36),
                                    itemCount: visible.length,
                                    itemBuilder: (context, idx) =>
                                        _buildPostCard(visible[idx]),
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

  Widget _buildFilterChip({required String keyId, required String label}) {
    final selected = _filter == keyId;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filter = keyId);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: selected ? ZevColors.brandGradient : null,
          color: selected ? null : ZevColors.softSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Colors.transparent : ZevColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : ZevColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(FeedPostItem post) {
    final urls = post.effectiveMediaUrls;
    final thumbUrl = urls.isNotEmpty ? urls.first : '';
    final isBusy = _busyIds.contains(post.id);
    final isScheduled = !post.isDraft && post.scheduledAt != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isScheduled
                      ? ZevColors.primaryBlue.withValues(alpha: 0.14)
                      : ZevColors.warningAmber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isScheduled
                          ? Icons.schedule_rounded
                          : Icons.edit_note_rounded,
                      size: 14,
                      color: isScheduled
                          ? ZevColors.secondaryBlue
                          : ZevColors.warningAmber,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isScheduled ? 'SCHEDULED' : 'DRAFT',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: isScheduled
                            ? ZevColors.secondaryBlue
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (urls.length > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ZevColors.softSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ZevColors.border),
                  ),
                  child: Text(
                    '${urls.length} slides',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.textSecondary,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                TimeAgo.format(post.createdAt),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: ZevColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (isScheduled && post.scheduledAt != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  size: 14,
                  color: ZevColors.secondaryBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  'Scheduled for ${_formatScheduleDate(post.scheduledAt!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumbUrl.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => PostDetailScreen.open(
                    context,
                    postId: post.id,
                    initialPost: post,
                  ).then((_) => _loadItems()),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 78,
                      height: 78,
                      child: ZevCachedImage.grid(
                        imageUrl: thumbUrl,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.title.isNotEmpty && !post.title.startsWith('['))
                      Text(
                        post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                    if (post.content.isNotEmpty)
                      Text(
                        post.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: ZevColors.textSecondary,
                        ),
                      )
                    else
                      const Text(
                        '(Media only post)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: ZevColors.textMuted,
                        ),
                      ),
                    if (post.location.isNotEmpty ||
                        post.collaborators.isNotEmpty ||
                        post.taggedUsers.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (post.location.isNotEmpty)
                            Text(
                              '📍 ${post.location}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: ZevColors.textMuted,
                              ),
                            ),
                          if (post.collaborators.isNotEmpty)
                            Text(
                              '🤝 ${post.collaborators.length} collab',
                              style: const TextStyle(
                                fontSize: 11,
                                color: ZevColors.secondaryBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (post.taggedUsers.isNotEmpty)
                            Text(
                              '🏷️ ${post.taggedUsers.length} tagged',
                              style: const TextStyle(
                                fontSize: 11,
                                color: ZevColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isBusy ? null : () => _publishNow(post),
                  icon: isBusy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.publish_rounded, size: 17),
                  label: Text(
                    isBusy ? 'Publishing...' : 'Publish Now',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZevColors.secondaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: isBusy ? null : () => _deleteItem(post),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: ZevColors.errorRed,
                ),
                label: const Text(
                  'Delete',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ZevColors.errorRed,
                    fontSize: 13,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: ZevColors.errorRed.withValues(alpha: 0.35),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: ZevColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: ZevColors.border),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.deepNavy.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.schedule_send_rounded,
                size: 34,
                color: ZevColors.secondaryBlue,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Drafts or Scheduled Posts',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Save posts as drafts or schedule them for later from the Create Post studio.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: ZevColors.errorRed,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMsg ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ZevColors.deepNavy,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _loadItems,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.secondaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
