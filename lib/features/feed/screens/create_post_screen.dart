import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/content_safety_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../models/feed_post_item.dart';
import '../widgets/feed_post_card.dart';
import 'drafts_scheduled_screen.dart';

/// Flagship Instagram-Grade Post Creation Studio for ZEV.
/// Supports multi-image carousels (up to 8 photos + reorder), collaborators (up to 3),
/// tagged accounts (up to 5), locations, drafts, scheduled publishing,
/// real-time Live Preview, Cloudflare R2 upload with rollback, and dynamic RTL/LTR.
class CreatePostScreen extends StatefulWidget {
  final VoidCallback onPostCreated;

  const CreatePostScreen({super.key, required this.onPostCreated});

  static Future<void> open(
    BuildContext context, {
    required VoidCallback onPostCreated,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CreatePostScreen(onPostCreated: onPostCreated),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxCarouselImages = 8;
  static const int _maxCollaborators = 3;
  static const int _maxTaggedUsers = 5;

  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  final PageController _previewPageCtrl = PageController();

  // Mode: 0 = Editor, 1 = Live Preview
  int _activeMode = 0;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();

  final List<File> _selectedImages = [];
  int _currentSlideIndex = 0;

  final List<FeedPostUserTag> _collaborators = [];
  final List<FeedPostUserTag> _taggedUsers = [];
  DateTime? _scheduledAt;

  bool _isPublishing = false;
  bool _lastAttemptAsDraft = false;
  double _uploadProgress = 0.0;
  String _uploadStage = '';
  String? _errorMessage;

  // Author Profile
  String _authorUsername = 'user';
  String _authorFullName = 'ZEV Creator';
  String _authorAvatar = '';
  bool _isVerified = false;

  // Category tags
  String _selectedCategory = "Explore";
  final List<String> _categories = const [
    "Analysis",
    "Education",
    "Explore",
    "Tech",
    "Trading",
    "Community",
    "Design",
  ];

  // Quick Hashtags
  final List<String> _quickTags = const [
    "#zev",
    "#tech",
    "#education",
    "#analysis",
    "#crypto",
    "#coding",
    "#community",
  ];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _contentCtrl.addListener(() => setState(() {}));
    _titleCtrl.addListener(() => setState(() {}));
    _locationCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _previewPageCtrl.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('username, first_name, last_name, avatar_url, is_verified')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        final fn = res['first_name'] ?? '';
        final ln = res['last_name'] ?? '';
        final full = "$fn $ln".trim();
        setState(() {
          _authorUsername = res['username'] ?? (full.isNotEmpty ? full : 'user');
          _authorFullName = full.isNotEmpty ? full : 'ZEV Creator';
          _authorAvatar = res['avatar_url'] ?? '';
          _isVerified = res['is_verified'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickGalleryImages() async {
    HapticFeedback.lightImpact();
    final remaining = _maxCarouselImages - _selectedImages.length;
    if (remaining <= 0) {
      _showSnack('Maximum $_maxCarouselImages photos allowed per carousel.');
      return;
    }

    try {
      if (remaining == 1) {
        final picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 1920,
        );
        if (picked != null && mounted) {
          setState(() {
            _selectedImages.add(File(picked.path));
            _currentSlideIndex = _selectedImages.length - 1;
          });
          _jumpToSlide(_currentSlideIndex);
        }
      } else {
        final pickedList = await _picker.pickMultiImage(
          imageQuality: 90,
          maxWidth: 1920,
          limit: remaining,
        );
        if (pickedList.isNotEmpty && mounted) {
          final toAdd = pickedList.take(remaining).map((x) => File(x.path));
          setState(() {
            _selectedImages.addAll(toAdd);
            _currentSlideIndex = _selectedImages.length - 1;
          });
          _jumpToSlide(_currentSlideIndex);
          if (pickedList.length > remaining) {
            _showSnack('Only the first $remaining photo(s) were added (max $_maxCarouselImages).');
          }
        }
      }
    } catch (e) {
      debugPrint("Gallery image pick notice: $e");
    }
  }

  Future<void> _pickCameraImage() async {
    HapticFeedback.lightImpact();
    if (_selectedImages.length >= _maxCarouselImages) {
      _showSnack('Maximum $_maxCarouselImages photos allowed per carousel.');
      return;
    }

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 1920,
      );
      if (picked != null && mounted) {
        setState(() {
          _selectedImages.add(File(picked.path));
          _currentSlideIndex = _selectedImages.length - 1;
        });
        _jumpToSlide(_currentSlideIndex);
      }
    } catch (e) {
      debugPrint("Camera pick notice: $e");
    }
  }

  void _jumpToSlide(int index) {
    if (!mounted || !_previewPageCtrl.hasClients) return;
    if (index < 0 || index >= _selectedImages.length) return;
    _previewPageCtrl.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _removeSlideAt(int index) {
    if (index < 0 || index >= _selectedImages.length) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selectedImages.removeAt(index);
      if (_selectedImages.isEmpty) {
        _currentSlideIndex = 0;
      } else if (_currentSlideIndex >= _selectedImages.length) {
        _currentSlideIndex = _selectedImages.length - 1;
      }
    });
    if (_selectedImages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToSlide(_currentSlideIndex);
      });
    }
  }

  void _moveSlide(int index, int delta) {
    final target = index + delta;
    if (index < 0 ||
        index >= _selectedImages.length ||
        target < 0 ||
        target >= _selectedImages.length) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      final item = _selectedImages.removeAt(index);
      _selectedImages.insert(target, item);
      _currentSlideIndex = target;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToSlide(target);
    });
  }

  void _insertHashtag(String tag) {
    HapticFeedback.selectionClick();
    final currentText = _contentCtrl.text;
    final space = currentText.isNotEmpty && !currentText.endsWith(' ') ? ' ' : '';
    _contentCtrl.text = "$currentText$space$tag ";
    _contentCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _contentCtrl.text.length),
    );
  }

  Future<void> _pickScheduleDateTime() async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final initial = _scheduledAt ?? now.add(const Duration(hours: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? initial : now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: ZevColors.secondaryBlue,
            onPrimary: Colors.white,
            surface: ZevColors.white,
            onSurface: ZevColors.deepNavy,
          ),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: ZevColors.secondaryBlue,
            onPrimary: Colors.white,
            surface: ZevColors.white,
            onSurface: ZevColors.deepNavy,
          ),
        ),
        child: child!,
      ),
    );
    if (pickedTime == null || !mounted) return;

    final candidate = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (candidate.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
      _showSnack(
        'Please schedule at least 5 minutes in the future.',
        isError: true,
      );
      return;
    }

    setState(() => _scheduledAt = candidate);
  }

  Future<void> _openUserTagPicker({required bool forCollaborators}) async {
    HapticFeedback.lightImpact();
    final currentList = forCollaborators ? _collaborators : _taggedUsers;
    final maxCount = forCollaborators ? _maxCollaborators : _maxTaggedUsers;
    final me = supabase.auth.currentUser?.id ?? '';

    final searchCtrl = TextEditingController();
    Timer? debounce;
    bool initialized = false;
    bool loading = true;
    List<FeedPostUserTag> results = [];
    final selectedMap = <String, FeedPostUserTag>{
      for (final u in currentList) u.id: u,
    };

    Future<void> runSearch(
      String q,
      StateSetter setModalState,
    ) async {
      setModalState(() => loading = true);
      try {
        final safety = await SocialGraphService.instance.fetchSafetyFilters();
        final trimmed = q.trim().replaceAll(',', ' ');

        var query = supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified, is_banned, account_status',
            )
            .neq('id', me)
            .eq('is_banned', false)
            .eq('account_status', 'active');

        if (trimmed.isNotEmpty) {
          query = query.or(
            'username.ilike.%$trimmed%,first_name.ilike.%$trimmed%,last_name.ilike.%$trimmed%',
          );
        }

        final res = await query.order('followers_count', ascending: false).limit(30);
        final rows = List<Map<String, dynamic>>.from(res as List);

        final clean = <FeedPostUserTag>[];
        for (final row in rows) {
          final id = row['id']?.toString() ?? '';
          if (id.isEmpty ||
              id == me ||
              safety.blockedUserIds.contains(id)) {
            continue;
          }
          clean.add(FeedPostUserTag.fromMap(row));
        }

        if (mounted) {
          setModalState(() {
            results = clean;
            loading = false;
          });
        }
      } catch (e) {
        debugPrint('Tag user search notice: $e');
        if (mounted) {
          setModalState(() => loading = false);
        }
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (!initialized) {
            initialized = true;
            unawaited(runSearch('', setModalState));
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.78,
            ),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                18,
                14,
                18,
                18 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: ZevColors.softSurface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: ZevColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              forCollaborators
                                  ? 'Invite Collaborators'
                                  : 'Tag People',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            Text(
                              'Select up to $maxCount accounts (${selectedMap.length}/$maxCount)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: ZevColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            if (forCollaborators) {
                              _collaborators
                                ..clear()
                                ..addAll(selectedMap.values);
                            } else {
                              _taggedUsers
                                ..clear()
                                ..addAll(selectedMap.values);
                            }
                          });
                          Navigator.pop(sheetCtx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZevColors.secondaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: ZevColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (val) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 280), () {
                          unawaited(runSearch(val, setModalState));
                        });
                      },
                      style: const TextStyle(
                        fontSize: 14,
                        color: ZevColors.deepNavy,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: ZevColors.textMuted,
                          size: 20,
                        ),
                        hintText: 'Search username or name...',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: ZevColors.textMuted,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: ZevColors.primaryBlue,
                            ),
                          )
                        : results.isEmpty
                            ? const Center(
                                child: Text(
                                  'No matching accounts found.',
                                  style: TextStyle(
                                    color: ZevColors.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                physics: const BouncingScrollPhysics(),
                                itemCount: results.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, idx) {
                                  final u = results[idx];
                                  final isPicked = selectedMap.containsKey(u.id);
                                  return GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setModalState(() {
                                        if (isPicked) {
                                          selectedMap.remove(u.id);
                                        } else {
                                          if (selectedMap.length >= maxCount) {
                                            ScaffoldMessenger.of(ctx)
                                              ..hideCurrentSnackBar()
                                              ..showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Maximum $maxCount accounts can be selected.',
                                                  ),
                                                  backgroundColor:
                                                      ZevColors.deepNavy,
                                                ),
                                              );
                                            return;
                                          }
                                          selectedMap[u.id] = u;
                                        }
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: ZevColors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isPicked
                                              ? ZevColors.secondaryBlue
                                              : ZevColors.border,
                                          width: isPicked ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          u.avatarUrl.isNotEmpty
                                              ? ZevCachedImage.avatar(
                                                  imageUrl: u.avatarUrl,
                                                  size: 38,
                                                )
                                              : Container(
                                                  width: 38,
                                                  height: 38,
                                                  decoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: ZevColors.softSurface,
                                                  ),
                                                  child: const Icon(
                                                    Icons.person_rounded,
                                                    color: ZevColors.textMuted,
                                                  ),
                                                ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        '@${u.username}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              ZevColors.deepNavy,
                                                        ),
                                                      ),
                                                    ),
                                                    if (u.isVerified) ...[
                                                      const SizedBox(width: 4),
                                                      const Icon(
                                                        Icons.verified_rounded,
                                                        size: 14,
                                                        color:
                                                            ZevColors.primaryBlue,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                if (u.fullName.isNotEmpty)
                                                  Text(
                                                    u.fullName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      color: ZevColors
                                                          .textSecondary,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            isPicked
                                                ? Icons.check_circle_rounded
                                                : Icons.add_circle_outline_rounded,
                                            color: isPicked
                                                ? ZevColors.secondaryBlue
                                                : ZevColors.textMuted,
                                            size: 22,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    debounce?.cancel();
    searchCtrl.dispose();
  }

  Future<void> _submitPost({bool asDraft = false}) async {
    final content = _contentCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    final location = _locationCtrl.text.trim();

    if (content.isEmpty && _selectedImages.isEmpty) {
      _showSnack("Please write text or attach at least one photo.");
      return;
    }

    final isScheduled = !asDraft && _scheduledAt != null;
    if (isScheduled &&
        _scheduledAt!
            .isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
      _showSnack(
        'Scheduled time must be at least 5 minutes in the future.',
        isError: true,
      );
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnack("Please sign in to publish.");
      return;
    }

    HapticFeedback.mediumImpact();
    _lastAttemptAsDraft = asDraft;
    setState(() {
      _isPublishing = true;
      _uploadProgress = 0.0;
      _uploadStage = _selectedImages.isNotEmpty
          ? 'Checking media safety...'
          : (asDraft
              ? 'Saving draft...'
              : (isScheduled ? 'Scheduling post...' : 'Publishing post...'));
      _errorMessage = null;
    });

    final uploadedUrls = <String>[];
    String? insertedPostId;

    try {
      // 1. Pre-upload +18 and violence moderation across ALL selected slides
      for (int i = 0; i < _selectedImages.length; i++) {
        if (mounted) {
          setState(() {
            _uploadStage = _selectedImages.length > 1
                ? 'Checking safety (${i + 1}/${_selectedImages.length})...'
                : 'Checking media safety...';
          });
        }
        final safetyResult =
            await ContentSafetyService.instance.checkImageSafety(
          file: _selectedImages[i],
        );
        if (!safetyResult.isSafe) {
          if (mounted) {
            setState(() {
              _isPublishing = false;
              _uploadProgress = 0.0;
              _uploadStage = '';
              _errorMessage = safetyResult.errorMessage ??
                  "Image #${i + 1} was flagged as inappropriate (+18) and cannot be posted.";
            });
            _showSnack(_errorMessage!, isError: true);
          }
          return;
        }
      }

      // 2. Upload all slides to R2 `feed/` folder tracking URLs for rollback
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < _selectedImages.length; i++) {
        final file = _selectedImages[i];
        final ext = file.path.contains('.') ? file.path.split('.').last : 'jpg';
        final fileName = 'feed_${user.id}_${ts}_$i.$ext';

        final url = await CloudflareStorageService.instance.upload(
          bucket: 'feed',
          path: fileName,
          file: file,
          compressImage: true,
          onProgress: (p) {
            if (mounted) {
              final overall = (i + p) / _selectedImages.length;
              setState(() {
                _uploadProgress = overall;
                _uploadStage = _selectedImages.length > 1
                    ? 'Uploading slide ${i + 1}/${_selectedImages.length} (${(overall * 100).round()}%)...'
                    : 'Uploading photo (${(p * 100).round()}%)...';
              });
            }
          },
        );
        uploadedUrls.add(url);
      }

      if (mounted) {
        setState(() {
          _uploadStage = asDraft
              ? 'Saving draft...'
              : (isScheduled ? 'Scheduling post...' : 'Saving post...');
          _uploadProgress = 1.0;
        });
      }

      final formattedTitle = title.startsWith('[')
          ? title
          : "[$_selectedCategory] ${title.isNotEmpty ? title : (content.length > 30 ? content.substring(0, 30) : content)}";

      final nowUtc = DateTime.now().toUtc();
      final effectiveCreatedAt =
          isScheduled ? _scheduledAt!.toUtc() : nowUtc;

      final inserted = await supabase
          .from('discussion_posts')
          .insert({
            'student_id': user.id,
            'title': formattedTitle,
            'content': content,
            'image_url': uploadedUrls.isNotEmpty ? uploadedUrls.first : '',
            'post_type': uploadedUrls.length > 1
                ? 'carousel'
                : (uploadedUrls.isNotEmpty ? 'image' : 'text'),
            'location': location.isEmpty ? null : location,
            'collaborator_ids': _collaborators.map((c) => c.id).toList(),
            'tagged_user_ids': _taggedUsers.map((t) => t.id).toList(),
            'is_draft': asDraft,
            'scheduled_at':
                isScheduled ? _scheduledAt!.toUtc().toIso8601String() : null,
            'published_at': (asDraft || isScheduled)
                ? null
                : nowUtc.toIso8601String(),
            'created_at': effectiveCreatedAt.toIso8601String(),
            'updated_at': nowUtc.toIso8601String(),
          })
          .select('id')
          .single();

      insertedPostId = inserted['id']?.toString();

      if (insertedPostId != null &&
          insertedPostId.isNotEmpty &&
          uploadedUrls.isNotEmpty) {
        final mediaRows = <Map<String, dynamic>>[];
        for (int i = 0; i < uploadedUrls.length; i++) {
          mediaRows.add({
            'post_id': insertedPostId,
            'media_type': 'image',
            'media_url': uploadedUrls[i],
            'sort_order': i,
          });
        }
        await supabase.from('post_media').insert(mediaRows);
      }

      HapticFeedback.lightImpact();
      widget.onPostCreated();

      if (mounted) {
        _showSnack(
          asDraft
              ? 'Draft saved! Find it under Drafts & Scheduled.'
              : (isScheduled
                  ? 'Post scheduled for ${_formatScheduleLabel(_scheduledAt!)}'
                  : 'Post published successfully!'),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      // Roll back partially inserted post or uploaded R2 assets cleanly
      if (insertedPostId != null && insertedPostId.isNotEmpty) {
        unawaited(
          Future<void>.microtask(() async {
            try {
              await supabase
                  .from('discussion_posts')
                  .delete()
                  .eq('id', insertedPostId!)
                  .eq('student_id', user.id);
            } catch (_) {}
          }),
        );
      }
      if (uploadedUrls.isNotEmpty) {
        unawaited(CloudflareStorageService.instance.deleteUrls(uploadedUrls));
      }
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _uploadProgress = 0.0;
          _uploadStage = '';
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: isError ? ZevColors.errorRed : ZevColors.deepNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  String _formatScheduleLabel(DateTime dt) {
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
    return '$m ${local.day} at $hh:$mm';
  }

  bool get _canPublish =>
      _contentCtrl.text.trim().isNotEmpty || _selectedImages.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final primaryCtaLabel = _scheduledAt != null ? "Schedule" : "Share";

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.06),
        leadingWidth: 48,
        titleSpacing: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Center(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (_canPublish) {
                  _showDiscardDialog();
                } else {
                  Navigator.pop(context);
                }
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: ZevColors.deepNavy,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        centerTitle: true,
        // Center Segmented Toggle: [ Editor | Preview ]
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSegmentTab(
                  index: 0,
                  label: "Editor",
                  icon: Icons.edit_note_rounded,
                ),
                _buildSegmentTab(
                  index: 1,
                  label: "Preview",
                  icon: Icons.visibility_outlined,
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Drafts & Scheduled',
            onPressed: _isPublishing
                ? null
                : () {
                    DraftsScheduledScreen.open(
                      context,
                      onPostPublished: widget.onPostCreated,
                    );
                  },
            icon: const Icon(
              Icons.schedule_send_rounded,
              color: ZevColors.deepNavy,
              size: 21,
            ),
          ),
          // Share / Schedule Button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _isPublishing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ZevColors.primaryBlue,
                      ),
                    )
                  : GestureDetector(
                      onTap:
                          _canPublish ? () => _submitPost(asDraft: false) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: _canPublish
                              ? const LinearGradient(
                                  colors: [Color(0xFF00D4FF), Color(0xFF0284C7)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: _canPublish ? null : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _canPublish
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF0284C7)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          primaryCtaLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _canPublish
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _activeMode == 0
              ? _buildEditorView()
              : _buildLivePreviewView(),
        ),
      ),
    );
  }

  Widget _buildSegmentTab({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _activeMode == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeMode = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                  const BoxShadow(
                    color: Colors.white,
                    blurRadius: 2,
                    offset: Offset(0, -1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? ZevColors.deepNavy : const Color(0xFF64748B),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? ZevColors.deepNavy : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. Editor View
  Widget _buildEditorView() {
    final isRtl = TextDirectionHelper.isRtl(_contentCtrl.text);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: ZevColors.softSurface,
                backgroundImage: _authorAvatar.isNotEmpty
                    ? NetworkImage(_authorAvatar)
                    : null,
                child: _authorAvatar.isEmpty
                    ? const Icon(Icons.person_rounded, color: ZevColors.textMuted)
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _authorUsername,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      if (_isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: ZevColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ZevColors.border, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _scheduledAt != null
                              ? Icons.schedule_rounded
                              : Icons.public_rounded,
                          size: 12,
                          color: _scheduledAt != null
                              ? ZevColors.secondaryBlue
                              : ZevColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _scheduledAt != null
                              ? "Scheduled: ${_formatScheduleLabel(_scheduledAt!)}"
                              : "Public Feed",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _scheduledAt != null
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _scheduledAt != null
                                ? ZevColors.secondaryBlue
                                : ZevColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category Pills
          const Text(
            "SELECT TOPIC CATEGORY",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ZevColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final isSelected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = cat);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [Color(0xFF00D4FF), Color(0xFF0284C7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected ? null : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? Colors.transparent : Colors.white,
                        width: 1.2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                              const BoxShadow(
                                color: Colors.white,
                                blurRadius: 3,
                                offset: Offset(0, -1),
                              ),
                            ],
                    ),
                    child: Center(
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : ZevColors.deepNavy,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),

          // Optional Title Field
          _buildWhiteInputCard(
            child: TextField(
              controller: _titleCtrl,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: ZevColors.deepNavy,
              ),
              decoration: const InputDecoration(
                hintText: "Title / Headline (optional)",
                hintStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ZevColors.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Caption Field
          Container(
            constraints: const BoxConstraints(minHeight: 130),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
                const BoxShadow(
                  color: Colors.white,
                  blurRadius: 4,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: TextField(
              controller: _contentCtrl,
              maxLines: null,
              minLines: 5,
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(
                fontSize: 14.5,
                color: ZevColors.deepNavy,
                height: 1.4,
              ),
              decoration: const InputDecoration(
                hintText:
                    "What's on your mind? Share thoughts, insights, or tutorials with the ZEV community...",
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: ZevColors.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Quick Hashtags Strip
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickTags.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final tag = _quickTags[i];
                return GestureDetector(
                  onTap: () => _insertHashtag(tag),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Location Input Field
          _buildWhiteInputCard(
            child: TextField(
              controller: _locationCtrl,
              maxLength: 80,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ZevColors.deepNavy,
              ),
              decoration: InputDecoration(
                counterText: '',
                prefixIcon: const Icon(
                  Icons.location_on_outlined,
                  color: ZevColors.secondaryBlue,
                  size: 20,
                ),
                suffixIcon: _locationCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: ZevColors.textMuted,
                        ),
                        onPressed: () => _locationCtrl.clear(),
                      )
                    : null,
                hintText: "Add location (optional)",
                hintStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: ZevColors.textMuted,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tag People & Collaborators Row
          Row(
            children: [
              Expanded(
                child: _buildCompactOptionButton(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Tag People (${_taggedUsers.length}/$_maxTaggedUsers)',
                  onTap: () => _openUserTagPicker(forCollaborators: false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCompactOptionButton(
                  icon: Icons.group_add_outlined,
                  label:
                      'Collaborate (${_collaborators.length}/$_maxCollaborators)',
                  onTap: () => _openUserTagPicker(forCollaborators: true),
                ),
              ),
            ],
          ),

          if (_collaborators.isNotEmpty || _taggedUsers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._collaborators.map(
                  (u) => _buildUserChip(
                    user: u,
                    prefix: 'Collab:',
                    onRemove: () =>
                        setState(() => _collaborators.removeWhere((x) => x.id == u.id)),
                  ),
                ),
                ..._taggedUsers.map(
                  (u) => _buildUserChip(
                    user: u,
                    prefix: 'Tag:',
                    onRemove: () =>
                        setState(() => _taggedUsers.removeWhere((x) => x.id == u.id)),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // Media Carousel Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "MEDIA CAROUSEL (UP TO 8 PHOTOS)",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              if (_selectedImages.isNotEmpty)
                Text(
                  '${_selectedImages.length}/$_maxCarouselImages slides',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (_selectedImages.isNotEmpty) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: double.infinity,
                    height: 320,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: PageView.builder(
                      controller: _previewPageCtrl,
                      itemCount: _selectedImages.length,
                      onPageChanged: (idx) =>
                          setState(() => _currentSlideIndex = idx),
                      itemBuilder: (context, idx) => Image.file(
                        _selectedImages[idx],
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ),
                  ),
                ),
                // Slide index pill
                if (_selectedImages.length > 1)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${(_currentSlideIndex + 1).clamp(1, _selectedImages.length)}/${_selectedImages.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                // Remove current slide
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () => _removeSlideAt(_currentSlideIndex),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                // Bottom controls: Reorder + Add more
                Positioned(
                  bottom: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_selectedImages.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _currentSlideIndex > 0
                                    ? () => _moveSlide(_currentSlideIndex, -1)
                                    : null,
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  size: 18,
                                  color: _currentSlideIndex > 0
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  'Reorder',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _currentSlideIndex <
                                        _selectedImages.length - 1
                                    ? () => _moveSlide(_currentSlideIndex, 1)
                                    : null,
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: _currentSlideIndex <
                                          _selectedImages.length - 1
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      if (_selectedImages.length < _maxCarouselImages)
                        GestureDetector(
                          onTap: _pickGalleryImages,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  "Add photos",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_selectedImages.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final active = idx == _currentSlideIndex;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _currentSlideIndex = idx);
                        _jumpToSlide(idx);
                      },
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active
                                ? ZevColors.secondaryBlue
                                : Colors.white,
                            width: active ? 2.5 : 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.file(
                          _selectedImages[idx],
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ] else
            Row(
              children: [
                Expanded(
                  child: _buildMediaPickerCard(
                    icon: Icons.photo_library_outlined,
                    title: "Gallery",
                    subtitle: "Select up to 8 photos",
                    gradientColors: const [Color(0xFF00D4FF), Color(0xFF0284C7)],
                    onTap: _pickGalleryImages,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMediaPickerCard(
                    icon: Icons.camera_alt_outlined,
                    title: "Camera",
                    subtitle: "Take a photo now",
                    gradientColors: const [Color(0xFF536DFE), Color(0xFF8B5CF6)],
                    onTap: _pickCameraImage,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),

          // Draft & Scheduling Options Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PUBLISHING OPTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                if (_scheduledAt != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_available_rounded,
                          size: 16,
                          color: ZevColors.secondaryBlue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Will publish on ${_formatScheduleLabel(_scheduledAt!)}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _scheduledAt = null),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: ZevColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_isPublishing || !_canPublish)
                            ? null
                            : () => _submitPost(asDraft: true),
                        icon: const Icon(Icons.save_outlined, size: 17),
                        label: const Text(
                          'Save Draft',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ZevColors.deepNavy,
                          side: const BorderSide(color: ZevColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isPublishing ? null : _pickScheduleDateTime,
                        icon: const Icon(Icons.schedule_rounded, size: 17),
                        label: Text(
                          _scheduledAt != null
                              ? 'Change Time'
                              : 'Schedule Post',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ZevColors.secondaryBlue,
                          side: BorderSide(
                            color:
                                ZevColors.secondaryBlue.withValues(alpha: 0.4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
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

          if (_isPublishing) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ZevColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          _uploadStage.isNotEmpty
                              ? _uploadStage
                              : 'Uploading...',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_uploadProgress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.secondaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _uploadProgress > 0 ? _uploadProgress : null,
                      minHeight: 6,
                      backgroundColor: ZevColors.softSurface,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        ZevColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isPublishing
                        ? null
                        : () => _submitPost(asDraft: _lastAttemptAsDraft),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ZevColors.deepNavy,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildWhiteInputCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildCompactOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: ZevColors.secondaryBlue),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.deepNavy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserChip({
    required FeedPostUserTag user,
    required String prefix,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ZevColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$prefix @${user.username}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 15,
              color: ZevColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPickerCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required List<Color> gradientColors,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors.first.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 2. Live Real-Time Feed Preview
  Widget _buildLivePreviewView() {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    final previewMedia = <FeedPostMediaItem>[
      for (int i = 0; i < _selectedImages.length; i++)
        FeedPostMediaItem(
          id: 'preview_$i',
          mediaType: 'image',
          mediaUrl: _selectedImages[i].path,
          sortOrder: i,
        ),
    ];

    final previewPost = FeedPostItem(
      id: 'preview_post',
      authorId: supabase.auth.currentUser?.id ?? 'preview_author',
      authorUsername: _authorUsername,
      authorFullName: _authorFullName,
      authorAvatar: _authorAvatar,
      isVerified: _isVerified,
      title: title.startsWith('[')
          ? title
          : "[$_selectedCategory] ${title.isNotEmpty ? title : (content.length > 30 ? content.substring(0, 30) : content)}",
      content: content.isNotEmpty
          ? content
          : "Your caption text will appear here with dynamic RTL/LTR support.",
      imageUrl: _selectedImages.isNotEmpty ? _selectedImages.first.path : '',
      createdAt: DateTime.now(),
      likesCount: 0,
      isLikedByMe: false,
      commentsCount: 0,
      categoryTag: _selectedCategory,
      isAuthorFollowed: true,
      location: _locationCtrl.text.trim(),
      mediaItems: previewMedia,
      collaborators: _collaborators,
      taggedUsers: _taggedUsers,
      scheduledAt: _scheduledAt,
    );

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: ZevColors.primaryBlue.withValues(alpha: 0.1),
              border: const Border(
                bottom: BorderSide(color: ZevColors.border, width: 0.8),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: ZevColors.primaryBlue,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Live Feed Preview: Exactly how your post appears to followers.",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),

          FeedPostCard(
            key: ValueKey(
              'preview_${_selectedImages.length}_${_collaborators.length}_${_taggedUsers.length}_${_locationCtrl.text}',
            ),
            post: previewPost,
            onCommentsUpdated: null,
          ),

          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed:
                    _canPublish && !_isPublishing ? () => _submitPost(asDraft: false) : null,
                icon: Icon(
                  _scheduledAt != null
                      ? Icons.schedule_send_rounded
                      : Icons.send_rounded,
                  size: 18,
                ),
                label: Text(
                  _scheduledAt != null
                      ? "Schedule Post (${_formatScheduleLabel(_scheduledAt!)})"
                      : "Looks Great! Publish Now",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: ZevColors.deepNavy,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showDiscardDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "Discard post?",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          "You can save this post as a draft or discard your changes.",
          style: TextStyle(color: ZevColors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_submitPost(asDraft: true));
            },
            child: const Text(
              "Save Draft",
              style: TextStyle(
                color: ZevColors.secondaryBlue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text(
              "Discard",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}
