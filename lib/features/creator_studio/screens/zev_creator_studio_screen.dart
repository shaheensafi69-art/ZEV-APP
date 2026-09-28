import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/utils/blob_url.dart';
import 'package:zev_app/core/services/cloudflare_storage_service.dart';
import 'package:zev_app/core/services/hashtag_service.dart';
import 'package:zev_app/core/utils/app_media_picker.dart';
import 'package:zev_app/core/widgets/responsive_layout.dart';

/// Next-Generation Creator Studio for ZEV Web & Mobile
/// Seamlessly create Posts, Reels, and 24h Stories with real-time live preview.
class ZevCreatorStudioScreen extends StatefulWidget {
  final int initialTab;
  final VoidCallback? onBack;

  const ZevCreatorStudioScreen({
    super.key,
    this.initialTab = 0,
    this.onBack,
  });

  @override
  State<ZevCreatorStudioScreen> createState() => _ZevCreatorStudioScreenState();
}

class _ZevCreatorStudioScreenState extends State<ZevCreatorStudioScreen> {
  final supabase = Supabase.instance.client;

  // 0 = Post, 1 = Reel, 2 = Story
  late int _activeTab;
  // Mobile sub-tab: 0 = Editor, 1 = Live Preview
  int _mobileSubTab = 0;

  bool _isPublishing = false;
  Map<String, dynamic>? _userProfile;

  // Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  // Media
  AppPickedMedia? _pickedMedia;
  VideoPlayerController? _videoPreviewController;
  String? _blobVideoUrl;
  bool _isVideoInitializing = false;

  int get _maxContentLength {
    switch (_activeTab) {
      case 0:
        return 2200;
      case 1:
        return 1000;
      case 2:
      default:
        return 280;
    }
  }

  int get _maxHashtags {
    switch (_activeTab) {
      case 0:
        return 30;
      case 1:
        return 20;
      case 2:
      default:
        return 5;
    }
  }

  // Post Mood
  String _selectedMood = "🚀 Excited";
  final List<String> _moods = [
    "🚀 Excited",
    "🌟 Explore",
    "💡 Learning",
    "📊 Analysis",
    "🔥 Motivated",
    "📢 Announcement",
  ];

  // Reel Category
  String _selectedCategory = "Explore";
  final List<String> _categories = [
    "Explore",
    "Educational",
    "Trading",
    "Coding",
    "Motivation",
  ];

  // Hashtags
  List<HashtagItem> _trendingHashtags = [];
  List<HashtagItem> _hashtagSuggestions = [];
  bool _showHashtagDropdown = false;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color accentPurple = Color(0xFF3F5EFB);

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _fetchProfile();
    _loadTrendingHashtags();
    _contentController.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _cleanupVideoController();
    _contentController.removeListener(_onContentChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('id, first_name, last_name, avatar_url, role')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() => _userProfile = res);
      }
    } catch (_) {}
  }

  Future<void> _loadTrendingHashtags() async {
    try {
      final tags = await HashtagService.instance.getTrendingHashtags(limit: 12);
      if (mounted) setState(() => _trendingHashtags = tags);
    } catch (_) {}
  }

  void _onContentChanged() {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (sel.baseOffset < 0 || sel.baseOffset > text.length) {
      if (_showHashtagDropdown) setState(() => _showHashtagDropdown = false);
      return;
    }

    final beforeCursor = text.substring(0, sel.baseOffset);
    final lastHashIndex = beforeCursor.lastIndexOf('#');

    if (lastHashIndex != -1) {
      final tagSub = beforeCursor.substring(lastHashIndex + 1);
      if (!tagSub.contains(' ') && !tagSub.contains('\n')) {
        setState(() {
          _showHashtagDropdown = true;
          _hashtagSuggestions = _trendingHashtags
              .where((item) =>
                  item.tag.toLowerCase().contains(tagSub.toLowerCase()))
              .toList();
        });
        return;
      }
    }

    if (_showHashtagDropdown) {
      setState(() => _showHashtagDropdown = false);
    }
  }

  void _insertHashtag(String tag) {
    final cleanTag = tag.replaceAll('#', '').trim();
    final text = _contentController.text;
    final sel = _contentController.selection;
    final beforeCursor =
        sel.baseOffset >= 0 ? text.substring(0, sel.baseOffset) : text;
    final afterCursor =
        sel.baseOffset >= 0 ? text.substring(sel.baseOffset) : '';
    final lastHashIndex = beforeCursor.lastIndexOf('#');

    final isCurrentlyTypingTag = lastHashIndex != -1 &&
        !beforeCursor.substring(lastHashIndex).contains(' ') &&
        !beforeCursor.substring(lastHashIndex).contains('\n');

    final currentTagsCount =
        RegExp(r'#[a-zA-Z0-9_\u0600-\u06FF]+').allMatches(text).length;

    if (!isCurrentlyTypingTag && currentTagsCount >= _maxHashtags) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Maximum $_maxHashtags hashtags allowed for this mode."),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    String newText;
    int newCursorPos;

    if (isCurrentlyTypingTag) {
      newText =
          "${beforeCursor.substring(0, lastHashIndex)}#$cleanTag $afterCursor";
      newCursorPos = lastHashIndex + cleanTag.length + 2;
    } else {
      final prefix = (beforeCursor.isNotEmpty &&
              !beforeCursor.endsWith(' ') &&
              !beforeCursor.endsWith('\n'))
          ? ' '
          : '';
      newText = "$beforeCursor$prefix#$cleanTag $afterCursor";
      newCursorPos = beforeCursor.length + prefix.length + cleanTag.length + 2;
    }

    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    setState(() => _showHashtagDropdown = false);
  }

  Future<void> _pickMedia() async {
    final bool allowImages = _activeTab == 0 || _activeTab == 2;
    final bool allowVideos = _activeTab == 1 || _activeTab == 2;

    final media = await AppMediaPicker.instance.pickUniversalMedia(
      allowImages: allowImages,
      allowVideos: allowVideos,
    );

    if (media == null) return;

    _cleanupVideoController();

    setState(() {
      _pickedMedia = media;
    });

    if (media.isVideo) {
      await _initVideoPreview(media);
    }
  }

  Future<void> _initVideoPreview(AppPickedMedia media) async {
    setState(() => _isVideoInitializing = true);
    try {
      if (kIsWeb) {
        final mime = media.mimeType.isNotEmpty ? media.mimeType : 'video/mp4';
        _blobVideoUrl = createBlobUrlFromBytes(media.bytes, mimeType: mime);
        _videoPreviewController =
            VideoPlayerController.networkUrl(Uri.parse(_blobVideoUrl!));
      } else {
        if (media.file != null && media.file!.existsSync()) {
          _videoPreviewController = VideoPlayerController.file(media.file!);
        } else if (media.path != null && media.path!.isNotEmpty) {
          _videoPreviewController =
              VideoPlayerController.file(io.File(media.path!));
        } else {
          final tempDir = await getTemporaryDirectory();
          final tempFile = io.File(
            '${tempDir.path}/zev_preview_${DateTime.now().millisecondsSinceEpoch}.mp4',
          );
          await tempFile.writeAsBytes(media.bytes);
          _videoPreviewController = VideoPlayerController.file(tempFile);
        }
      }

      await _videoPreviewController!.initialize();
      await _videoPreviewController!.setLooping(true);
      await _videoPreviewController!.setVolume(0); // muted for preview
      await _videoPreviewController!.play();
    } catch (e) {
      debugPrint("Error initializing studio video preview: $e");
    } finally {
      if (mounted) setState(() => _isVideoInitializing = false);
    }
  }

  void _cleanupVideoController() {
    if (_blobVideoUrl != null) {
      revokeBlobUrl(_blobVideoUrl!);
      _blobVideoUrl = null;
    }
    _videoPreviewController?.pause();
    _videoPreviewController?.dispose();
    _videoPreviewController = null;
  }

  void _clearMedia() {
    _cleanupVideoController();
    setState(() => _pickedMedia = null);
  }

  Future<void> _publish() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please sign in to publish content."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (_activeTab == 0) {
      // POST
      if (title.isEmpty || content.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please provide both a title and post content."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      setState(() => _isPublishing = true);
      try {
        String? uploadedImageUrl;
        if (_pickedMedia != null) {
          final ext = _pickedMedia!.name.split('.').last.toLowerCase();
          final fileName =
              "post_${DateTime.now().millisecondsSinceEpoch}_${user.id}.$ext";
          uploadedImageUrl = await CloudflareStorageService.instance.upload(
            bucket: "safiacademy-media",
            path: "feed/$fileName",
            bytes: _pickedMedia!.bytes,
            file: _pickedMedia!.file,
            contentType: _pickedMedia!.mimeType,
          );
        }

        final insertData = {
          'student_id': user.id,
          'title': "[$_selectedMood] $title",
          'content': content,
          if (uploadedImageUrl != null && uploadedImageUrl.isNotEmpty)
            'image_url': uploadedImageUrl,
        };

        final res = await supabase
            .from("discussion_posts")
            .insert(insertData)
            .select('id')
            .maybeSingle();

        if (res != null) {
          final newPostId = res['id']?.toString();
          if (newPostId != null) {
            HashtagService.instance
                .syncPostHashtags(newPostId, "$title $content");
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("🎉 Post published successfully to ZEV!"),
              backgroundColor: Colors.green,
            ),
          );
          _resetStudio();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to publish post: $e"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isPublishing = false);
      }
    } else if (_activeTab == 1) {
      // REEL
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please provide a title for your reel."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if (_pickedMedia == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please select a video file for your reel."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      setState(() => _isPublishing = true);
      try {
        final ext = _pickedMedia!.name.split('.').last.toLowerCase();
        final fileName =
            "reel_${DateTime.now().millisecondsSinceEpoch}_${user.id}.$ext";
        final publicUrl = await CloudflareStorageService.instance.upload(
          bucket: "safiacademy-media",
          path: "reels/$fileName",
          bytes: _pickedMedia!.bytes,
          file: _pickedMedia!.file,
          contentType: _pickedMedia!.mimeType.isNotEmpty
              ? _pickedMedia!.mimeType
              : "video/mp4",
        );

        if (publicUrl.isEmpty) {
          throw Exception("Video upload failed.");
        }

        final reelRes = await supabase.from("reels").insert({
          'user_id': user.id,
          'title': title,
          'description': content,
          'video_url': publicUrl,
          'category': _selectedCategory,
          'is_published': true,
          'views_count': 0,
          'likes_count': 0,
          'comments_count': 0,
          'created_at': DateTime.now().toIso8601String(),
        }).select('id').maybeSingle();

        if (reelRes != null) {
          final newReelId = reelRes['id']?.toString();
          if (newReelId != null) {
            HashtagService.instance
                .syncReelHashtags(newReelId, "$title $content");
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("🎬 Reel published successfully!"),
              backgroundColor: Colors.green,
            ),
          );
          _resetStudio();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error publishing reel: $e"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isPublishing = false);
      }
    } else {
      // 24H STORY
      if (_pickedMedia == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please select an image or video for your story."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      setState(() => _isPublishing = true);
      try {
        final isVideo = _pickedMedia!.isVideo;
        final ext = _pickedMedia!.name.split('.').last.toLowerCase();
        final fileName =
            "story_${DateTime.now().millisecondsSinceEpoch}_${user.id}.$ext";
        final publicUrl = await CloudflareStorageService.instance.upload(
          bucket: "safiacademy-media",
          path: "story/$fileName",
          bytes: _pickedMedia!.bytes,
          file: _pickedMedia!.file,
          contentType: _pickedMedia!.mimeType.isNotEmpty
              ? _pickedMedia!.mimeType
              : (isVideo ? 'video/mp4' : 'image/jpeg'),
        );

        final now = DateTime.now();
        final expiresAt = now.add(const Duration(hours: 24)).toIso8601String();

        await supabase.from("user_stories").insert({
          'user_id': user.id,
          'media_url': publicUrl,
          'media_type': isVideo ? 'video' : 'image',
          'caption': content.isNotEmpty ? content : title,
          'expires_at': expiresAt,
          'created_at': now.toIso8601String(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("📸 24h Story shared successfully!"),
              backgroundColor: Colors.green,
            ),
          );
          _resetStudio();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error publishing story: $e"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isPublishing = false);
      }
    }
  }

  void _resetStudio() {
    _titleController.clear();
    _contentController.clear();
    _clearMedia();
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    }
  }

  bool _isRtl(String text) {
    if (text.isEmpty) return false;
    final rtlRegex = RegExp(
      r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
    );
    return rtlRegex.hasMatch(text);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0B0E14) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF131722) : Colors.white;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);

    return StudioLoadingOverlay(
      isLoading: _isPublishing,
      message: "PUBLISHING TO ZEV...",
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Column(
            children: [
              // Top Studio Header
              _buildStudioTopHeader(isDark, cardBg, borderColor),

              // Main Workspace
              Expanded(
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: Studio Editor & Form Deck
                          Expanded(
                            flex: 6,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(28),
                              child: _buildEditorForm(
                                  isDark, cardBg, borderColor),
                            ),
                          ),

                          // Divider
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: borderColor,
                          ),

                          // Right: Live Interactive Card Simulator
                          Expanded(
                            flex: 5,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(28),
                              child: _buildLiveSimulatorPanel(
                                  isDark, cardBg, borderColor),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          // Mobile Sub-Tab Bar (Editor vs Live Preview)
                          Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1A1F2C)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => _mobileSubTab = 0),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _mobileSubTab == 0
                                            ? primaryPink
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        "✍️ Studio Editor",
                                        style: TextStyle(
                                          color: _mobileSubTab == 0
                                              ? Colors.white
                                              : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => _mobileSubTab = 1),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _mobileSubTab == 1
                                            ? primaryPink
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        "📱 Live Preview",
                                        style: TextStyle(
                                          color: _mobileSubTab == 1
                                              ? Colors.white
                                              : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: _mobileSubTab == 0
                                  ? _buildEditorForm(
                                      isDark, cardBg, borderColor)
                                  : _buildLiveSimulatorPanel(
                                      isDark, cardBg, borderColor),
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

  // =========================================================================
  // TOP STUDIO TOOLBAR & MODE SELECTOR
  // =========================================================================
  // =========================================================================
  // TOP STUDIO TOOLBAR & MODE SELECTOR
  // =========================================================================
  Widget _buildStudioTopHeader(bool isDark, Color cardBg, Color borderColor) {
    final isDesktop = ResponsiveLayout.isDesktop(context);

    final modeSwitcher = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2433) : const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFCBD5E1),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.white.withOpacity(0.9),
                  offset: const Offset(-2, -2),
                  blurRadius: 4,
                ),
                BoxShadow(
                  color: const Color(0xFFD1D9E6),
                  offset: const Offset(2, 2),
                  blurRadius: 4,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildModeTabItem(
            index: 0,
            icon: Icons.article_rounded,
            label: context.zevTr('studioPost'),
            isDark: isDark,
          ),
          const SizedBox(width: 4),
          _buildModeTabItem(
            index: 1,
            icon: Icons.movie_filter_rounded,
            label: context.zevTr('studioReel'),
            isDark: isDark,
          ),
          const SizedBox(width: 4),
          _buildModeTabItem(
            index: 2,
            icon: Icons.camera_alt_rounded,
            label: context.zevTr('studioStory'),
            isDark: isDark,
          ),
        ],
      ),
    );

    final publishBtn = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: primaryPink.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _isPublishing ? null : _publish,
        icon: const Icon(Icons.rocket_launch_rounded, size: 15),
        label: Text(
          _activeTab == 0
              ? context.zevTr('publishPost')
              : (_activeTab == 1
                  ? context.zevTr('publishReel')
                  : context.zevTr('publishStory')),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPink,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 20 : 12,
            vertical: isDesktop ? 14 : 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );

    if (!isDesktop) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cardBg,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                if (widget.onBack != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    onPressed: widget.onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryPink, accentPurple],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "CREATOR STUDIO",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                publishBtn,
              ],
            ),
            const SizedBox(height: 8),
            modeSwitcher,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Row(
            children: [
              if (widget.onBack != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryPink, accentPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: primaryPink.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "ZEV CREATOR STUDIO",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    "Create & publish across ZEV ecosystem",
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          modeSwitcher,
          const Spacer(),
          publishBtn,
        ],
      ),
    );
  }

  Widget _buildModeTabItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = index;
          _clearMedia();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [primaryPink, Color(0xFFFF5E7E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryPink.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white60 : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
  }

  // =========================================================================
  // LEFT PANEL: EDITOR & FORM DECK
  // =========================================================================
  Widget _buildEditorForm(bool isDark, Color cardBg, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Drag & Drop Media Upload Zone
        _buildMediaUploadZone(isDark, cardBg, borderColor),

        const SizedBox(height: 24),

        // 2. Title & Mood / Category
        if (_activeTab == 0) ...[
          // Mood Chips for Post
          _buildLabel("SELECT MOOD / TOPIC 🎯"),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _moods.map((mood) {
                final isSelected = _selectedMood == mood;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(mood),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedMood = mood);
                    },
                    selectedColor: primaryPink.withValues(alpha: 0.15),
                    backgroundColor: isDark
                        ? const Color(0xFF1E2433)
                        : const Color(0xFFF1F5F9),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? primaryPink
                          : (isDark ? Colors.white70 : const Color(0xFF475569)),
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? primaryPink : Colors.transparent,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
        ] else if (_activeTab == 1) ...[
          // Category Chips for Reel
          _buildLabel("REEL CATEGORY 🎬"),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedCategory = cat);
                    },
                    selectedColor: primaryPink.withValues(alpha: 0.15),
                    backgroundColor: isDark
                        ? const Color(0xFF1E2433)
                        : const Color(0xFFF1F5F9),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? primaryPink
                          : (isDark ? Colors.white70 : const Color(0xFF475569)),
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? primaryPink : Colors.transparent,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
        ],

        // 3. Title Input (for Post & Reel)
        if (_activeTab != 2) ...[
          _buildLabel(_activeTab == 0 ? "POST TITLE ✍️" : "REEL TITLE 🎬"),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            textDirection: _isRtl(_titleController.text)
                ? TextDirection.rtl
                : TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _activeTab == 0
                  ? "What would you like to discuss today?"
                  : "Give your reel a catchy headline...",
              hintStyle: TextStyle(
                color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                fontSize: 14,
              ),
              filled: true,
              fillColor: cardBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: primaryPink, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 4. Content / Caption Field
        _buildLabel(_activeTab == 0
            ? "CONTENT & HASHTAGS 📝"
            : (_activeTab == 1
                ? "REEL DESCRIPTION & TAGS 💬"
                : "STORY CAPTION 📸")),
        const SizedBox(height: 8),
        Stack(
          children: [
            TextField(
              controller: _contentController,
              maxLines: _activeTab == 2 ? 3 : 6,
              textDirection: _isRtl(_contentController.text)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              style: const TextStyle(fontSize: 14, height: 1.5),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _activeTab == 0
                    ? "Share your insights, questions, or ideas. Type # to insert hashtags..."
                    : "Add context, tags, or mentions...",
                hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: cardBg,
                contentPadding: const EdgeInsets.all(18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: primaryPink, width: 1.5),
                ),
              ),
            ),

            // Live Hashtag Dropdown
            if (_showHashtagDropdown && _hashtagSuggestions.isNotEmpty)
              Positioned(
                bottom: 8,
                left: 12,
                right: 12,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  color: isDark ? const Color(0xFF1E2433) : Colors.white,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: primaryPink.withValues(alpha: 0.3)),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _hashtagSuggestions.length,
                      itemBuilder: (context, idx) {
                        final tag = _hashtagSuggestions[idx];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.tag_rounded,
                            color: primaryPink,
                            size: 18,
                          ),
                          title: Text(
                            "#${tag.tag}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          trailing: Text(
                            "${tag.postsCount} posts",
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white38
                                  : const Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                          onTap: () => _insertHashtag(tag.tag),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),

        // Live Character & Hashtag Limits Counter
        Builder(
          builder: (context) {
            final textLen = _contentController.text.length;
            final currentTagsCount = RegExp(r'#[a-zA-Z0-9_\u0600-\u06FF]+')
                .allMatches(_contentController.text)
                .length;
            final isNearLenLimit = textLen > _maxContentLength * 0.9;
            final isOverLenLimit = textLen > _maxContentLength;

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2433) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.06)
                          : Colors.black.withOpacity(0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tag_rounded, size: 13, color: primaryPink),
                      const SizedBox(width: 4),
                      Text(
                        "Hashtags: $currentTagsCount/$_maxHashtags",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: currentTagsCount >= _maxHashtags
                              ? Colors.orangeAccent
                              : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  "$textLen/$_maxContentLength",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isOverLenLimit
                        ? Colors.redAccent
                        : (isNearLenLimit
                            ? Colors.orangeAccent
                            : (isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 12),

        // Quick Hashtags Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                "Popular:",
                style: TextStyle(
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              ..._trendingHashtags.take(6).map((tag) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => _insertHashtag(tag.tag),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primaryPink.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: primaryPink.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        "#${tag.tag}",
                        style: const TextStyle(
                          color: primaryPink,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Action Buttons Row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isPublishing ? null : _publish,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _activeTab == 0
                      ? "PUBLISH POST TO FEED"
                      : (_activeTab == 1 ? "PUBLISH REEL" : "SHARE 24H STORY"),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 6,
                  shadowColor: primaryPink.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _resetStudio,
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    isDark ? Colors.white70 : const Color(0xFF64748B),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text("Clear"),
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================================
  // MEDIA UPLOAD ZONE (Images & Videos)
  // =========================================================================
  Widget _buildMediaUploadZone(bool isDark, Color cardBg, Color borderColor) {
    if (_pickedMedia != null) {
      final isVideo = _pickedMedia!.isVideo;
      final sizeKb = (_pickedMedia!.bytes.lengthInBytes / 1024).round();
      final sizeStr = sizeKb > 1024
          ? "${(sizeKb / 1024).toStringAsFixed(1)} MB"
          : "$sizeKb KB";

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: primaryPink.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            // Media thumbnail or icon
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 70,
                height: 70,
                color:
                    isDark ? const Color(0xFF1E2433) : const Color(0xFFF1F5F9),
                child: isVideo
                    ? (_videoPreviewController != null &&
                            _videoPreviewController!.value.isInitialized
                        ? _buildVideoPlayerWidget(
                            height: 70,
                            fit: BoxFit.cover,
                            showControls: false,
                          )
                        : const Center(
                            child: Icon(Icons.videocam_rounded,
                                color: primaryPink, size: 32)))
                    : Image.memory(
                        _pickedMedia!.bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.image_rounded,
                          color: primaryPink,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: primaryPink.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isVideo ? "🎬 VIDEO" : "🖼️ IMAGE",
                          style: const TextStyle(
                            color: primaryPink,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sizeStr,
                        style: TextStyle(
                          color:
                              isDark ? Colors.white38 : const Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _pickedMedia!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              tooltip: "Remove file",
              onPressed: _clearMedia,
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _pickMedia,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryPink.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _activeTab == 1
                    ? Icons.video_call_rounded
                    : Icons.add_photo_alternate_rounded,
                color: primaryPink,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _activeTab == 1
                  ? "Click to upload Reel Video (.mp4, .mov, .webm)"
                  : "Click or drag & drop media here",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              "Supports high-resolution images & videos across all formats",
              style: TextStyle(
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // LIVE VIDEO PLAYER WIDGET
  // =========================================================================
  Widget _buildVideoPlayerWidget({
    double? height,
    BoxFit fit = BoxFit.cover,
    bool showControls = true,
  }) {
    if (_isVideoInitializing) {
      return Container(
        height: height,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryPink),
                ),
              ),
              SizedBox(height: 10),
              Text(
                "Loading video preview...",
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    if (_videoPreviewController == null ||
        !_videoPreviewController!.value.isInitialized) {
      return Container(
        height: height,
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_rounded, color: primaryPink, size: 40),
              const SizedBox(height: 6),
              Text(
                "Video preview ready",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isPlaying = _videoPreviewController!.value.isPlaying;
    final isMuted = _videoPreviewController!.value.volume == 0;

    return Container(
      height: height,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: fit,
              child: SizedBox(
                width: _videoPreviewController!.value.size.width > 0
                    ? _videoPreviewController!.value.size.width
                    : 16,
                height: _videoPreviewController!.value.size.height > 0
                    ? _videoPreviewController!.value.size.height
                    : 9,
                child: VideoPlayer(_videoPreviewController!),
              ),
            ),
          ),
          if (showControls) ...[
            // Tap area to play/pause
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    if (isPlaying) {
                      _videoPreviewController!.pause();
                    } else {
                      _videoPreviewController!.play();
                    }
                  });
                },
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            // Play icon overlay when paused
            Positioned(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: isPlaying ? 0.0 : 0.85,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
            // Mute / Unmute toggle button
            Positioned(
              bottom: 10,
              right: 10,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isMuted) {
                      _videoPreviewController!.setVolume(1.0);
                    } else {
                      _videoPreviewController!.setVolume(0.0);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black60,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // RIGHT PANEL: LIVE INTERACTIVE SIMULATOR / PREVIEW
  // =========================================================================
  Widget _buildLiveSimulatorPanel(
      bool isDark, Color cardBg, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live Simulator Header Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2433) : const Color(0xFFEDF2F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "REAL-TIME SIMULATOR PREVIEW",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Device Frame / Mockup
        Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: _activeTab == 0 ? 520 : 360,
            ),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _activeTab == 0
                ? _buildPostSimulator(isDark)
                : (_activeTab == 1
                    ? _buildReelSimulator(isDark)
                    : _buildStorySimulator(isDark)),
          ),
        ),
      ],
    );
  }

  // Live Post Card Simulator
  Widget _buildPostSimulator(bool isDark) {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final name =
        "${_userProfile?['first_name'] ?? 'ZEV'} ${_userProfile?['last_name'] ?? 'Creator'}"
            .trim();
    final avatar = _userProfile?['avatar_url']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Row
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: primaryPink.withValues(alpha: 0.2),
                backgroundImage:
                    avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0] : 'Z',
                        style: const TextStyle(
                          color: primaryPink,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          color: primaryPink,
                          size: 16,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          _selectedMood,
                          style: const TextStyle(
                            color: primaryPink,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "• Just now",
                          style: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.more_horiz_rounded,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Title
          Text(
            title.isNotEmpty ? title : "Your Post Title Will Appear Here...",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: title.isNotEmpty
                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                  : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
            ),
          ),

          const SizedBox(height: 8),

          // Content
          Text(
            content.isNotEmpty
                ? content
                : "Your post body content and highlighted #hashtags will be rendered right here in real time.",
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: content.isNotEmpty
                  ? (isDark ? Colors.white70 : const Color(0xFF334155))
                  : (isDark ? Colors.white30 : const Color(0xFFCBD5E1)),
            ),
          ),

          const SizedBox(height: 14),

          // Media Preview
          if (_pickedMedia != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _pickedMedia!.isVideo
                  ? _buildVideoPlayerWidget(
                      height: 240,
                      fit: BoxFit.cover,
                      showControls: true,
                    )
                  : Image.memory(
                      _pickedMedia!.bytes,
                      width: double.infinity,
                      height: 240,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 14),
          ],

          // Action Row (Likes, Comments, Share)
          Row(
            children: [
              _buildSimAction(Icons.favorite_border_rounded, "0", isDark),
              const SizedBox(width: 18),
              _buildSimAction(Icons.chat_bubble_outline_rounded, "0", isDark),
              const SizedBox(width: 18),
              _buildSimAction(Icons.repeat_rounded, "0", isDark),
              const Spacer(),
              Icon(
                Icons.bookmark_border_rounded,
                size: 18,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Live Reel Simulator (9:16 Vertical Card)
  Widget _buildReelSimulator(bool isDark) {
    final title = _titleController.text.trim();
    final name =
        "${_userProfile?['first_name'] ?? 'ZEV'} ${_userProfile?['last_name'] ?? ''}"
            .trim();

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background / Media
          if (_pickedMedia != null && _pickedMedia!.isVideo)
            _buildVideoPlayerWidget(fit: BoxFit.cover, showControls: true)
          else if (_pickedMedia != null && !_pickedMedia!.isVideo)
            Image.memory(_pickedMedia!.bytes, fit: BoxFit.cover)
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E1035), Color(0xFF0D0221)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  color: Colors.white38,
                  size: 64,
                ),
              ),
            ),

          // Dark overlay gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black87],
                begin: Alignment.center,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // Top Badges
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.remove_red_eye_rounded,
                      color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text(
                    "0 views",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right Side Action Icons
          Positioned(
            right: 12,
            bottom: 40,
            child: Column(
              children: [
                _buildReelAction(Icons.favorite_rounded, "0"),
                const SizedBox(height: 14),
                _buildReelAction(Icons.chat_bubble_rounded, "0"),
                const SizedBox(height: 14),
                _buildReelAction(Icons.share_rounded, "Share"),
              ],
            ),
          ),

          // Bottom Caption & Creator
          Positioned(
            left: 14,
            right: 64,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "@$name",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title.isNotEmpty ? title : "Reel title and caption...",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Live 24h Story Simulator
  Widget _buildStorySimulator(bool isDark) {
    final caption = _contentController.text.trim();
    final name =
        "${_userProfile?['first_name'] ?? 'ZEV'} ${_userProfile?['last_name'] ?? ''}"
            .trim();

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_pickedMedia != null && _pickedMedia!.isVideo)
            _buildVideoPlayerWidget(fit: BoxFit.cover, showControls: true)
          else if (_pickedMedia != null && !_pickedMedia!.isVideo)
            Image.memory(_pickedMedia!.bytes, fit: BoxFit.cover)
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryPink, Color(0xFF3F5EFB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Icon(Icons.camera_alt_rounded,
                    color: Colors.white54, size: 54),
              ),
            ),

          // Top Story Bar
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Column(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white24,
                      backgroundImage: (_userProfile?['avatar_url'] != null &&
                              (_userProfile!['avatar_url'] as String).isNotEmpty)
                          ? NetworkImage(_userProfile!['avatar_url'])
                          : null,
                      child: (_userProfile?['avatar_url'] == null ||
                              (_userProfile!['avatar_url'] as String).isEmpty)
                          ? const Icon(Icons.person,
                              color: Colors.white, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      "• 24h",
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Caption
          if (caption.isNotEmpty)
            Positioned(
              left: 14,
              right: 14,
              bottom: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  caption,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSimAction(IconData icon, String count, bool isDark) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark ? Colors.white54 : const Color(0xFF64748B),
        ),
        const SizedBox(width: 5),
        Text(
          count,
          style: TextStyle(
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildReelAction(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 11,
        letterSpacing: 0.8,
      ),
    );
  }
}

class StudioLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final Widget child;

  const StudioLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = "LOADING...",
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: Color(0xFFFC466B),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 20),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
