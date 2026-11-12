import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/content_deletion_service.dart';
import '../../../../core/theme/zev_theme.dart';
import '../../../../core/widgets/zev_cached_image.dart';
import '../../../../core/widgets/zev_video_thumbnail.dart';

/// Instagram-Grade Recently Deleted Media Screen for ZEV.
/// Displays soft-deleted posts, reels, and stories with 30-day recovery countdown,
/// Restore to Profile, and Permanent Delete (+ Cloudflare R2 cleanup).
class ActivityDeletedScreen extends StatefulWidget {
  const ActivityDeletedScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ActivityDeletedScreen(),
      ),
    );
  }

  @override
  State<ActivityDeletedScreen> createState() => _ActivityDeletedScreenState();
}

class _ActivityDeletedScreenState extends State<ActivityDeletedScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabCtrl;

  bool _isLoading = true;
  bool _isProcessing = false;
  List<Map<String, dynamic>> _deletedPosts = [];
  List<Map<String, dynamic>> _deletedReels = [];
  List<Map<String, dynamic>> _deletedStories = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchDeletedItems();
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

  Future<void> _fetchDeletedItems() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        supabase
            .from('discussion_posts')
            .select('id, title, content, image_url, deleted_at, created_at')
            .eq('student_id', userId)
            .not('deleted_at', 'is', null)
            .order('deleted_at', ascending: false),
        supabase
            .from('reels')
            .select('id, title, description, video_url, thumbnail_url, deleted_at, created_at')
            .eq('user_id', userId)
            .not('deleted_at', 'is', null)
            .order('deleted_at', ascending: false),
        supabase
            .from('user_stories')
            .select('id, media_url, media_type, caption, deleted_at, created_at')
            .eq('user_id', userId)
            .not('deleted_at', 'is', null)
            .order('deleted_at', ascending: false),
      ]);

      final posts = (results[0] as List).map((p) {
        final imageUrl = (p['image_url'] ?? '').toString();
        return {
          'id': p['id'].toString(),
          'type': 'post',
          'preview_url': imageUrl,
          'video_url': _isVideoMediaUrl(imageUrl) ? imageUrl : '',
          'caption': (p['content'] ?? p['title'] ?? '').toString(),
          'media_urls': imageUrl.isNotEmpty ? <String>[imageUrl] : <String>[],
          'deleted_at': (p['deleted_at'] ?? '').toString(),
        };
      }).toList();

      final reels = (results[1] as List).map((r) {
        final thumb = (r['thumbnail_url'] ?? '').toString();
        final video = (r['video_url'] ?? '').toString();
        return {
          'id': r['id'].toString(),
          'type': 'reel',
          'preview_url': thumb,
          'video_url': video,
          'caption': (r['title'] ?? r['description'] ?? '').toString(),
          'media_urls': <String>[
            if (video.isNotEmpty) video,
            if (thumb.isNotEmpty) thumb,
          ],
          'deleted_at': (r['deleted_at'] ?? '').toString(),
        };
      }).toList();

      final stories = (results[2] as List).map((s) {
        final media = (s['media_url'] ?? '').toString();
        final isVid = s['media_type'] == 'video' || _isVideoMediaUrl(media);
        return {
          'id': s['id'].toString(),
          'type': 'story',
          'preview_url': isVid ? '' : media,
          'video_url': isVid ? media : '',
          'caption': (s['caption'] ?? '').toString(),
          'media_urls': media.isNotEmpty ? <String>[media] : <String>[],
          'deleted_at': (s['deleted_at'] ?? '').toString(),
        };
      }).toList();

      if (mounted) {
        setState(() {
          _deletedPosts = posts;
          _deletedReels = reels;
          _deletedStories = stories;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch recently deleted error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _activeItems() {
    List<Map<String, dynamic>> list;
    switch (_tabCtrl.index) {
      case 1:
        list = List.from(_deletedPosts);
        break;
      case 2:
        list = List.from(_deletedReels);
        break;
      case 3:
        list = List.from(_deletedStories);
        break;
      default:
        list = [..._deletedPosts, ..._deletedReels, ..._deletedStories];
        break;
    }
    list.sort((a, b) {
      final tA = DateTime.tryParse(a['deleted_at']?.toString() ?? '') ??
          DateTime(2000);
      final tB = DateTime.tryParse(b['deleted_at']?.toString() ?? '') ??
          DateTime(2000);
      return tB.compareTo(tA);
    });
    return list;
  }

  int _daysRemaining(String deletedAtIso) {
    final dt = DateTime.tryParse(deletedAtIso);
    if (dt == null) return 30;
    final elapsed = DateTime.now().toUtc().difference(dt.toUtc()).inDays;
    return (30 - elapsed).clamp(0, 30);
  }

  Future<void> _restoreItem(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final ok = await ContentDeletionService.restoreContent(
      type: item['type'].toString(),
      id: item['id'].toString(),
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (ok) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restored successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchDeletedItems();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not restore item. Please try again.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _permanentlyDeleteItem(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Delete Permanently?',
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'This cannot be undone. Media files and interactions will be erased immediately.',
          style: TextStyle(color: ZevColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: ZevColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    final urls = List<String>.from(item['media_urls'] as List? ?? const []);
    final ok = await ContentDeletionService.permanentDeleteById(
      type: item['type'].toString(),
      id: item['id'].toString(),
      mediaUrls: urls,
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (ok) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permanently deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchDeletedItems();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permanent delete failed. Please try again.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  void _openItemActionsSheet(Map<String, dynamic> item) {
    final type = item['type'].toString();
    final daysLeft = _daysRemaining(item['deleted_at'].toString());
    final previewUrl = (item['preview_url'] ?? '').toString();
    final videoUrl = (item['video_url'] ?? '').toString();
    final caption = (item['caption'] ?? '').toString();

    final typeLabel = type == 'reel'
        ? 'Reel'
        : (type == 'story' ? 'Story' : 'Post');

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
                  Text(
                    'Deleted $typeLabel',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: Text(
                      daysLeft == 1 ? '1 day left' : '$daysLeft days left',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.secondaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (videoUrl.isNotEmpty || previewUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: videoUrl.isNotEmpty
                        ? ZevVideoThumbnail(
                            videoUrl: videoUrl,
                            thumbnailUrl:
                                previewUrl.isNotEmpty ? previewUrl : null,
                            autoPlay: true,
                            showPlayBadge: false,
                            showViews: false,
                          )
                        : ZevCachedImage.grid(
                            imageUrl: previewUrl,
                            borderRadius: BorderRadius.circular(18),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (caption.isNotEmpty)
                Text(
                  caption,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: ZevColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _permanentlyDeleteItem(item);
                      },
                      icon: const Icon(
                        Icons.delete_forever_rounded,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      label: const Text(
                        'Delete Forever',
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
                        _restoreItem(item);
                      },
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text(
                        'Restore',
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
    final total =
        _deletedPosts.length + _deletedReels.length + _deletedStories.length;
    final items = _activeItems();

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
              'Recently Deleted',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '$total items in trash',
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
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: ZevColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ZevColors.border),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: ZevColors.secondaryBlue,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Items stay here for 30 days before permanent removal.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 40,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: ZevColors.border,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _buildTabPill(0, 'All ($total)'),
                    _buildTabPill(1, 'Posts (${_deletedPosts.length})'),
                    _buildTabPill(2, 'Reels (${_deletedReels.length})'),
                    _buildTabPill(3, 'Stories (${_deletedStories.length})'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isProcessing)
              const LinearProgressIndicator(
                color: ZevColors.primaryBlue,
                backgroundColor: ZevColors.border,
              ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: ZevColors.primaryBlue,
                      ),
                    )
                  : items.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: ZevColors.primaryBlue,
                          onRefresh: _fetchDeletedItems,
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
                              childAspectRatio: 0.85,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) =>
                                _buildDeletedTile(items[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill(int index, String label) {
    final isSelected = _tabCtrl.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _tabCtrl.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: isSelected ? ZevColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? ZevColors.deepNavy : ZevColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeletedTile(Map<String, dynamic> item) {
    final type = item['type'].toString();
    final previewUrl = (item['preview_url'] ?? '').toString();
    final videoUrl = (item['video_url'] ?? '').toString();
    final caption = (item['caption'] ?? '').toString();
    final daysLeft = _daysRemaining(item['deleted_at'].toString());

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _openItemActionsSheet(item);
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
            if (videoUrl.isNotEmpty)
              ZevVideoThumbnail(
                videoUrl: videoUrl,
                thumbnailUrl: previewUrl.isNotEmpty ? previewUrl : null,
                showPlayBadge: false,
                showViews: false,
                borderRadius: BorderRadius.circular(16),
              )
            else if (previewUrl.isNotEmpty)
              ZevCachedImage.grid(
                imageUrl: previewUrl,
                borderRadius: BorderRadius.circular(16),
              )
            else
              Container(
                color: ZevColors.softSurface,
                padding: const EdgeInsets.all(10),
                alignment: Alignment.center,
                child: Text(
                  caption.isNotEmpty ? caption : type.toUpperCase(),
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
              top: 6,
              right: 6,
              child: Icon(
                type == 'reel'
                    ? Icons.play_arrow_rounded
                    : (type == 'story'
                        ? Icons.history_rounded
                        : Icons.photo_rounded),
                color: Colors.white,
                size: 16,
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${daysLeft}d',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
                Icons.delete_outline_rounded,
                size: 34,
                color: ZevColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Recently Deleted Content',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'When you delete posts, stories or reels, they will be kept here for 30 days before being permanently removed.',
              textAlign: TextAlign.center,
              style: TextStyle(
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
}
