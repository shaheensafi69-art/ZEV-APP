import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/content_deletion_service.dart';
import '../../../../core/theme/zev_theme.dart';
import '../../../../core/widgets/zev_cached_image.dart';
import '../../../../core/widgets/zev_video_thumbnail.dart';
import '../../../feed/models/feed_post_item.dart';

/// Instagram-Grade Archive Activity Screen for ZEV.
/// Displays expired 24h stories and archived posts hidden from profile with restore and trash actions.
class ActivityArchiveScreen extends StatefulWidget {
  const ActivityArchiveScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ActivityArchiveScreen(),
      ),
    );
  }

  @override
  State<ActivityArchiveScreen> createState() => _ActivityArchiveScreenState();
}

class _ActivityArchiveScreenState extends State<ActivityArchiveScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabCtrl;

  bool _isLoading = true;
  List<Map<String, dynamic>> _archivedStories = [];
  List<Map<String, dynamic>> _archivedPosts = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchArchive();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  bool _isVideoMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v');
  }

  Future<void> _fetchArchive() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      final results = await Future.wait([
        supabase
            .from('user_stories')
            .select(
              'id, user_id, media_url, media_type, caption, views_count, expires_at, created_at',
            )
            .eq('user_id', userId)
            .isFilter('deleted_at', null)
            .lte('expires_at', nowIso)
            .order('created_at', ascending: false)
            .limit(60),
        supabase
            .from('discussion_posts')
            .select(
              'id, student_id, title, content, image_url, location, likes_count, comments_count, reposts_count, created_at',
            )
            .eq('student_id', userId)
            .isFilter('deleted_at', null)
            .eq('is_draft', true)
            .isFilter('scheduled_at', null)
            .order('created_at', ascending: false)
            .limit(60),
      ]);

      final stories = List<Map<String, dynamic>>.from(results[0] as List);
      final posts = List<Map<String, dynamic>>.from(results[1] as List);

      if (mounted) {
        setState(() {
          _archivedStories = stories;
          _archivedPosts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch archive error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _trashStory(Map<String, dynamic> story) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final id = story['id'].toString();
    try {
      await supabase
          .from('user_stories')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id)
          .eq('user_id', userId);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story moved to Recently Deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchArchive();
    } catch (e) {
      debugPrint('Trash archived story error: $e');
    }
  }

  Future<void> _repostStoryFor24h(Map<String, dynamic> story) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final id = story['id'].toString();
    final newExpiry =
        DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
    try {
      await supabase
          .from('user_stories')
          .update({'expires_at': newExpiry})
          .eq('id', id)
          .eq('user_id', userId);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story is live on your profile for 24 hours.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchArchive();
    } catch (e) {
      debugPrint('Re-share archived story error: $e');
    }
  }

  void _openStoryActionsSheet(Map<String, dynamic> story) {
    final mediaUrl = (story['media_url'] ?? '').toString();
    final isVideo = story['media_type'] == 'video' || _isVideoMediaUrl(mediaUrl);
    final caption = (story['caption'] ?? '').toString();
    final views = (story['views_count'] as int?) ?? 0;
    final createdAt = DateTime.tryParse(story['created_at']?.toString() ?? '');
    final dateLabel = createdAt != null
        ? '${createdAt.toLocal().year}/${createdAt.toLocal().month}/${createdAt.toLocal().day}'
        : '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: const BoxDecoration(
          color: ZevColors.white,
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
              Row(
                children: [
                  const Text(
                    'Archived Story',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$views views${dateLabel.isNotEmpty ? ' • $dateLabel' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ZevColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: isVideo
                      ? ZevVideoThumbnail(
                          videoUrl: mediaUrl,
                          autoPlay: true,
                          showPlayBadge: false,
                          showViews: false,
                        )
                      : ZevCachedImage.grid(
                          imageUrl: mediaUrl,
                          borderRadius: BorderRadius.circular(18),
                        ),
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _trashStory(story);
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      label: const Text(
                        'Move to Trash',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _repostStoryFor24h(story);
                      },
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: const Text(
                        'Share for 24h',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZevColors.primaryBlue,
                        foregroundColor: ZevColors.deepNavy,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPostActionsSheet(Map<String, dynamic> rawPost) {
    final postId = rawPost['id'].toString();
    final authorId = (rawPost['student_id'] ?? '').toString();
    final title = (rawPost['title'] ?? '').toString();
    final content = (rawPost['content'] ?? '').toString();
    final imageUrl = (rawPost['image_url'] ?? '').toString();
    final isVideo = _isVideoMediaUrl(imageUrl);

    final postModel = FeedPostItem(
      id: postId,
      authorId: authorId,
      authorUsername: 'me',
      authorFullName: 'You',
      authorAvatar: '',
      title: title,
      content: content,
      imageUrl: imageUrl,
      location: (rawPost['location'] ?? '').toString(),
      likesCount: (rawPost['likes_count'] as int?) ?? 0,
      commentsCount: (rawPost['comments_count'] as int?) ?? 0,
      repostsCount: (rawPost['reposts_count'] as int?) ?? 0,
      createdAt:
          DateTime.tryParse(rawPost['created_at']?.toString() ?? '') ??
              DateTime.now(),
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: const BoxDecoration(
          color: ZevColors.white,
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
                'Archived Post',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 12),
              if (imageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: isVideo
                        ? ZevVideoThumbnail(
                            videoUrl: imageUrl,
                            autoPlay: true,
                            showPlayBadge: false,
                            showViews: false,
                          )
                        : ZevCachedImage.grid(
                            imageUrl: imageUrl,
                            borderRadius: BorderRadius.circular(18),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (title.isNotEmpty)
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  content,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: ZevColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        ContentDeletionService.movePostToTrash(
                          context,
                          post: postModel,
                          onTrashed: _fetchArchive,
                        );
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      label: const Text(
                        'Move to Trash',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        ContentDeletionService.setPostArchived(
                          context,
                          post: postModel,
                          archived: false,
                          onUpdated: _fetchArchive,
                        );
                      },
                      icon: const Icon(Icons.unarchive_rounded, size: 18),
                      label: const Text(
                        'Show on Profile',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZevColors.primaryBlue,
                        foregroundColor: ZevColors.deepNavy,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStoriesTab = _tabCtrl.index == 0;
    final activeItems = isStoriesTab ? _archivedStories : _archivedPosts;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              'Archive',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${_archivedStories.length} stories • ${_archivedPosts.length} posts',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ZevColors.textMuted,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: ZevColors.border,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    _buildTabPill(
                      index: 0,
                      label: 'Stories Archive',
                      count: _archivedStories.length,
                    ),
                    _buildTabPill(
                      index: 1,
                      label: 'Posts Archive',
                      count: _archivedPosts.length,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? _buildShimmerGrid()
                  : activeItems.isEmpty
                      ? _buildEmptyState(isStoriesTab)
                      : RefreshIndicator(
                          color: ZevColors.primaryBlue,
                          onRefresh: _fetchArchive,
                          child: GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: activeItems.length,
                            itemBuilder: (context, index) => isStoriesTab
                                ? _buildStoryTile(activeItems[index])
                                : _buildPostTile(activeItems[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryTile(Map<String, dynamic> story) {
    final mediaUrl = (story['media_url'] ?? '').toString();
    final isVideo =
        story['media_type'] == 'video' || _isVideoMediaUrl(mediaUrl);
    final dt = DateTime.tryParse(story['created_at']?.toString() ?? '');
    final dateBadge = dt != null ? '${dt.toLocal().month}/${dt.toLocal().day}' : '';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _openStoryActionsSheet(story);
      },
      child: Container(
        decoration: BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isVideo && mediaUrl.isNotEmpty)
              ZevVideoThumbnail(
                videoUrl: mediaUrl,
                showPlayBadge: false,
                showViews: false,
                borderRadius: BorderRadius.circular(16),
              )
            else if (mediaUrl.isNotEmpty)
              ZevCachedImage.grid(
                imageUrl: mediaUrl,
                borderRadius: BorderRadius.circular(16),
              )
            else
              Container(
                color: ZevColors.softSurface,
                child: const Icon(
                  Icons.history_rounded,
                  color: ZevColors.textMuted,
                ),
              ),
            if (dateBadge.isNotEmpty)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: ZevColors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dateBadge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ),
              ),
            if (isVideo)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostTile(Map<String, dynamic> post) {
    final imageUrl = (post['image_url'] ?? '').toString();
    final isVideo = _isVideoMediaUrl(imageUrl);
    final caption =
        (post['content'] ?? post['title'] ?? '').toString().trim();

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _openPostActionsSheet(post);
      },
      child: Container(
        decoration: BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isVideo && imageUrl.isNotEmpty)
              ZevVideoThumbnail(
                videoUrl: imageUrl,
                showPlayBadge: false,
                showViews: false,
                borderRadius: BorderRadius.circular(16),
              )
            else if (imageUrl.isNotEmpty)
              ZevCachedImage.grid(
                imageUrl: imageUrl,
                borderRadius: BorderRadius.circular(16),
              )
            else
              Container(
                color: ZevColors.softSurface,
                padding: const EdgeInsets.all(10),
                alignment: Alignment.center,
                child: Text(
                  caption.isNotEmpty ? caption : 'Archived Post',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ),
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: ZevColors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.archive_rounded,
                  size: 13,
                  color: ZevColors.secondaryBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isStoriesTab) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: ZevColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: ZevColors.border, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.deepNavy.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.archive_outlined,
                size: 34,
                color: ZevColors.secondaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isStoriesTab ? 'No Archived Stories' : 'No Archived Posts',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isStoriesTab
                  ? 'Your stories are automatically archived here after 24 hours so only you can view or re-share them.'
                  : 'Posts you archive from your profile without deleting them will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: ZevColors.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemCount: 9,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: ZevColors.border,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildTabPill({
    required int index,
    required String label,
    required int count,
  }) {
    final isSelected = _tabCtrl.index == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _tabCtrl.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? ZevColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color:
                      isSelected ? ZevColors.deepNavy : ZevColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? ZevColors.secondaryBlue
                      : ZevColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
