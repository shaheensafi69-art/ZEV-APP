import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';

/// Ultra-Modern, 100% Tactile Light Clearmorphic "Edit Profile" Screen for ZEV.
/// Supports debounced `is_username_available` RPC + 14-day cooldown,
/// location editing, multi-link `user_links` CRUD (up to 5 links),
/// and safe Cloudflare R2 avatar replacement with old-object cleanup.
class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialProfile;

  const EditProfileScreen({
    super.key,
    required this.initialProfile,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _pronounsCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _websiteCtrl;
  late final TextEditingController _publicEmailCtrl;
  late final TextEditingController _publicPhoneCtrl;

  String _selectedCategory = 'Digital Creator';
  String _selectedGender = 'Prefer not to say';
  bool _showCategoryOnProfile = true;
  bool _showContactInfo = true;

  File? _newAvatarFile;
  String _currentAvatarUrl = '';
  String _initialAvatarUrl = '';
  String _initialUsername = '';
  int _usernameCooldownDaysLeft = 0;

  Timer? _usernameDebounce;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameStatusText;

  List<Map<String, dynamic>> _userLinks = [];
  final Set<String> _deletedLinkIds = {};
  bool _isLoadingLinks = true;

  bool _isSaving = false;
  String? _errorMessage;

  final List<String> _categories = [
    'Digital Creator',
    'Artist & Designer',
    'Musician / Band',
    'Entrepreneur / Business',
    'Gamer & Streamer',
    'Photographer / Videographer',
    'Blogger / Writer',
    'Educator / Teacher',
    'Athlete / Fitness',
    'Community Leader',
    'Personal Blog',
  ];

  final List<String> _genders = [
    'Male',
    'Female',
    'Custom',
    'Prefer not to say',
  ];

  final List<String> _pronounSuggestions = [
    'He/Him',
    'She/Her',
    'They/Them',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _firstNameCtrl = TextEditingController(text: p['first_name'] ?? '');
    _lastNameCtrl = TextEditingController(text: p['last_name'] ?? '');
    _initialUsername = (p['username'] ?? '').toString().trim().toLowerCase();
    _usernameCtrl = TextEditingController(text: p['username'] ?? '');
    _pronounsCtrl = TextEditingController(text: p['pronouns'] ?? '');
    _bioCtrl = TextEditingController(text: p['bio'] ?? '');
    _locationCtrl = TextEditingController(text: p['location'] ?? '');
    _websiteCtrl = TextEditingController(text: p['website'] ?? '');
    _publicEmailCtrl =
        TextEditingController(text: p['public_email'] ?? p['email'] ?? '');
    _publicPhoneCtrl = TextEditingController(
      text: p['public_phone'] ?? p['phone_number'] ?? '',
    );

    if (p['category'] != null && _categories.contains(p['category'])) {
      _selectedCategory = p['category'];
    }
    if (p['gender'] != null && _genders.contains(p['gender'])) {
      _selectedGender = p['gender'];
    }
    _showCategoryOnProfile = p['show_category_on_profile'] ?? true;
    _showContactInfo = p['show_contact_info'] ?? true;

    _initialAvatarUrl = (p['avatar_url'] ?? '').toString();
    _currentAvatarUrl = _initialAvatarUrl;

    final changedAtRaw = p['username_changed_at']?.toString();
    if (changedAtRaw != null && changedAtRaw.isNotEmpty) {
      final changedAt = DateTime.tryParse(changedAtRaw);
      if (changedAt != null) {
        final daysSince = DateTime.now().toUtc().difference(changedAt.toUtc()).inDays;
        if (daysSince < 14) {
          _usernameCooldownDaysLeft = 14 - daysSince;
        }
      }
    }

    _usernameCtrl.addListener(_onUsernameChanged);
    _fetchUserLinks();
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameCtrl.removeListener(_onUsernameChanged);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _usernameCtrl.dispose();
    _pronounsCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    _websiteCtrl.dispose();
    _publicEmailCtrl.dispose();
    _publicPhoneCtrl.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    _usernameDebounce?.cancel();
    final raw = _usernameCtrl.text.trim().toLowerCase().replaceAll('@', '');
    if (raw == _initialUsername) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = null;
        _usernameStatusText = null;
      });
      return;
    }

    if (_usernameCooldownDaysLeft > 0) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusText =
            'Username locked for $_usernameCooldownDaysLeft more day${_usernameCooldownDaysLeft == 1 ? '' : 's'}';
      });
      return;
    }

    if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(raw)) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusText = 'Use 3-30 lowercase letters, numbers, _ or .';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _isUsernameAvailable = null;
      _usernameStatusText = 'Checking availability...';
    });

    _usernameDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final res = await supabase.rpc(
          'is_username_available',
          params: {'p_username': raw},
        );
        if (!mounted) return;
        final currentRaw =
            _usernameCtrl.text.trim().toLowerCase().replaceAll('@', '');
        if (currentRaw != raw) return;
        final available = res == true;
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = available;
          _usernameStatusText = available
              ? '@$raw is available'
              : '@$raw is already taken';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = null;
          _usernameStatusText = null;
        });
      }
    });
  }

  Future<void> _fetchUserLinks() async {
    final userId = widget.initialProfile['id']?.toString() ??
        supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoadingLinks = false);
      return;
    }
    try {
      final res = await supabase
          .from('user_links')
          .select('id, title, url, sort_order')
          .eq('user_id', userId)
          .order('sort_order', ascending: true);
      if (mounted) {
        setState(() {
          _userLinks = List<Map<String, dynamic>>.from(res as List);
          _isLoadingLinks = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch user_links notice: $e');
      if (mounted) setState(() => _isLoadingLinks = false);
    }
  }

  Future<void> _showAddOrEditLinkSheet({int? editIndex}) async {
    if (editIndex == null && _userLinks.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can add up to 5 profile links.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.deepNavy,
        ),
      );
      return;
    }

    final existing = editIndex != null ? _userLinks[editIndex] : null;
    final titleCtrl = TextEditingController(
      text: (existing?['title'] ?? '').toString(),
    );
    final urlCtrl = TextEditingController(
      text: (existing?['url'] ?? '').toString(),
    );

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: ZevColors.softSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                Text(
                  editIndex == null ? 'Add Profile Link' : 'Edit Profile Link',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 12),
                _buildClayInputField(
                  label: 'Title (optional)',
                  controller: titleCtrl,
                  hint: 'e.g. Portfolio, YouTube, Store',
                  isSmall: false,
                ),
                const SizedBox(height: 10),
                _buildClayInputField(
                  label: 'URL',
                  controller: urlCtrl,
                  hint: 'https://example.com',
                  prefixIcon: Icons.link_rounded,
                  keyboardType: TextInputType.url,
                  isSmall: false,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    var url = urlCtrl.text.trim();
                    if (url.isEmpty) return;
                    if (!url.startsWith('http://') &&
                        !url.startsWith('https://')) {
                      url = 'https://$url';
                    }
                    final title = titleCtrl.text.trim().isNotEmpty
                        ? titleCtrl.text.trim()
                        : Uri.tryParse(url)?.host.replaceFirst('www.', '') ??
                            url;
                    Navigator.pop(ctx, {'title': title, 'url': url});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZevColors.secondaryBlue,
                    foregroundColor: ZevColors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    editIndex == null ? 'Add Link' : 'Update Link',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (editIndex != null) {
          _userLinks[editIndex] = {
            ..._userLinks[editIndex],
            'title': result['title'],
            'url': result['url'],
          };
        } else {
          _userLinks.add({
            'title': result['title'],
            'url': result['url'],
            'sort_order': _userLinks.length,
          });
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Core Claymorphic Elevation Helper
  // ---------------------------------------------------------------------------
  Widget _buildClayCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 20,
    Color color = Colors.white,
    double depth = 4.0,
    Border? border,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ??
            Border.all(
              color: Colors.white.withValues(alpha: 0.95),
              width: 1.5,
            ),
        boxShadow: [
          // Dark tactile drop shadow (bottom-right)
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.07),
            blurRadius: depth * 2.6,
            offset: Offset(depth * 0.7, depth * 0.9),
          ),
          // Crisp glossy white ambient light (top-left)
          BoxShadow(
            color: Colors.white,
            blurRadius: depth * 1.6,
            offset: Offset(-depth * 0.6, -depth * 0.6),
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _pickAvatar() async {
    HapticFeedback.lightImpact();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF1F5F9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 25,
              offset: Offset(0, -5),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              _buildClayCard(
                borderRadius: 16,
                depth: 3.0,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_library_rounded,
                            color: Color(0xFF0284C7), size: 20),
                      ),
                      title: const Text(
                        "Choose from Gallery",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Color(0xFF0284C7), size: 20),
                      ),
                      title: const Text(
                        "Take Photo",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, ImageSource.camera),
                    ),
                    if (_currentAvatarUrl.isNotEmpty || _newAvatarFile != null) ...[
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.delete_outline_rounded,
                              color: Color(0xFFEF4444), size: 20),
                        ),
                        title: const Text(
                          "Remove Photo",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _newAvatarFile = null;
                            _currentAvatarUrl = '';
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 800,
    );

    if (picked != null) {
      setState(() => _newAvatarFile = File(picked.path));
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    final userId = widget.initialProfile['id']?.toString() ??
        supabase.auth.currentUser?.id;
    if (userId == null) return;

    final newUsername =
        _usernameCtrl.text.trim().toLowerCase().replaceAll('@', '');
    if (newUsername.isEmpty) {
      setState(() => _errorMessage = "Username cannot be empty");
      return;
    }

    if (newUsername != _initialUsername) {
      if (_usernameCooldownDaysLeft > 0) {
        setState(
          () => _errorMessage =
              "You can change your username again in $_usernameCooldownDaysLeft day${_usernameCooldownDaysLeft == 1 ? '' : 's'}.",
        );
        return;
      }
      if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(newUsername)) {
        setState(
          () => _errorMessage =
              "Username must be 3-30 characters using lowercase letters, numbers, _ or .",
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    try {
      // 1. Check username availability if changed via authoritative RPC
      final usernameChanged = newUsername != _initialUsername;
      if (usernameChanged) {
        final avail = await supabase.rpc(
          'is_username_available',
          params: {'p_username': newUsername},
        );
        if (avail != true) {
          if (mounted) {
            setState(() {
              _isSaving = false;
              _isUsernameAvailable = false;
              _usernameStatusText = "@$newUsername is already taken";
              _errorMessage = "Username @$newUsername is already taken";
            });
          }
          return;
        }
      }

      // 2. Upload avatar if selected (fail loudly instead of swallowing error)
      String finalAvatarUrl = _currentAvatarUrl;
      if (_newAvatarFile != null) {
        final ext = _newAvatarFile!.path.contains('.')
            ? _newAvatarFile!.path.split('.').last
            : 'jpg';
        final fileName =
            'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final uploaded = await CloudflareStorageService.instance.upload(
          bucket: 'avatars',
          path: fileName,
          file: _newAvatarFile,
          maxImageDimension: 800,
          imageQuality: 85,
        );
        if (uploaded.isEmpty) {
          throw Exception('Avatar upload returned empty URL');
        }
        finalAvatarUrl = uploaded;
      }

      // 3. Update Supabase profiles table
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final updateData = <String, dynamic>{
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'username': newUsername,
        'pronouns': _pronounsCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'category': _selectedCategory,
        'gender': _selectedGender,
        'show_category_on_profile': _showCategoryOnProfile,
        'show_contact_info': _showContactInfo,
        'public_email': _publicEmailCtrl.text.trim(),
        'public_phone': _publicPhoneCtrl.text.trim(),
        'avatar_url': finalAvatarUrl,
        'updated_at': nowIso,
      };
      if (usernameChanged) {
        updateData['username_changed_at'] = nowIso;
      }

      await supabase.from('profiles').update(updateData).eq('id', userId);

      // 4. Sync user_links (up to 5 links)
      if (_deletedLinkIds.isNotEmpty) {
        await supabase
            .from('user_links')
            .delete()
            .eq('user_id', userId)
            .inFilter('id', _deletedLinkIds.toList());
      }
      for (var i = 0; i < _userLinks.length; i++) {
        final link = _userLinks[i];
        final title = (link['title'] ?? '').toString().trim();
        final url = (link['url'] ?? '').toString().trim();
        if (url.isEmpty) continue;
        final linkId = link['id']?.toString();
        if (linkId != null && linkId.isNotEmpty) {
          await supabase
              .from('user_links')
              .update({'title': title, 'url': url, 'sort_order': i})
              .eq('id', linkId)
              .eq('user_id', userId);
        } else {
          await supabase.from('user_links').insert({
            'user_id': userId,
            'title': title,
            'url': url,
            'sort_order': i,
          });
        }
      }

      // 5. Clean up old R2 avatar only after DB save succeeded
      if (_initialAvatarUrl.isNotEmpty &&
          finalAvatarUrl != _initialAvatarUrl) {
        unawaited(
          CloudflareStorageService.instance.deleteByUrl(_initialAvatarUrl),
        );
      }

      // Return the updated profile map to parent
      final mergedProfile = Map<String, dynamic>.from(widget.initialProfile)
        ..addAll(updateData);

      if (mounted) {
        Navigator.pop(context, mergedProfile);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = "Could not save profile: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isSmall = screenWidth < 360;
    final horizontalPad = isSmall ? 14.0 : 18.0;
    final avatarSize = isSmall ? 84.0 : 98.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Serene Clay Canvas
      body: SafeArea(
        child: Column(
          children: [
            // -----------------------------------------------------------------
            // Claymorphic Top App Bar
            // -----------------------------------------------------------------
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPad,
                8,
                horizontalPad,
                8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Clay Close Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    child: _buildClayCard(
                      borderRadius: 14,
                      depth: 2.8,
                      padding: const EdgeInsets.all(9),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),

                  // Screen Title
                  Text(
                    "Edit Profile",
                    style: TextStyle(
                      fontSize: isSmall ? 16 : 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),

                  // Clay Checkmark / Save Button
                  GestureDetector(
                    onTap: _isSaving ? null : _saveProfile,
                    child: _buildClayCard(
                      borderRadius: 14,
                      depth: 2.8,
                      color: const Color(0xFF0284C7),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.4,
                      ),
                      padding: const EdgeInsets.all(9),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // -----------------------------------------------------------------
            // Scrollable Claymorphic Content Body
            // -----------------------------------------------------------------
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  horizontalPad,
                  10,
                  horizontalPad,
                  28 + mediaQuery.viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Error Notice Banner
                    if (_errorMessage != null) ...[
                      _buildClayCard(
                        borderRadius: 16,
                        depth: 2.5,
                        color: const Color(0xFFFEF2F2),
                        border: Border.all(
                          color: const Color(0xFFFCA5A5),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFEF4444),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ---------------------------------------------------------
                    // Tactile 3D Clay Avatar Section
                    // ---------------------------------------------------------
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _pickAvatar,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Clay Outer Ring
                                Container(
                                  width: avatarSize + 16,
                                  height: avatarSize + 16,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF0F172A)
                                            .withValues(alpha: 0.1),
                                        blurRadius: 18,
                                        offset: const Offset(3, 5),
                                      ),
                                      const BoxShadow(
                                        color: Colors.white,
                                        blurRadius: 14,
                                        offset: Offset(-4, -4),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: ClipOval(
                                      child: _newAvatarFile != null
                                          ? Image.file(
                                              _newAvatarFile!,
                                              fit: BoxFit.cover,
                                            )
                                          : (_currentAvatarUrl.isNotEmpty
                                              ? ZevCachedImage(
                                                  imageUrl: _currentAvatarUrl,
                                                  fit: BoxFit.cover,
                                                )
                                              : Container(
                                                  color:
                                                      const Color(0xFFE2E8F0),
                                                  child: const Icon(
                                                    Icons.person_rounded,
                                                    size: 48,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                )),
                                    ),
                                  ),
                                ),

                                // Tactile Camera Badge
                                Positioned(
                                  bottom: 2,
                                  right: 2,
                                  child: _buildClayCard(
                                    borderRadius: 14,
                                    depth: 2.2,
                                    color: const Color(0xFF0284C7),
                                    padding: const EdgeInsets.all(7),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.0,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt_rounded,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Clay Pill: Edit Picture
                          GestureDetector(
                            onTap: _pickAvatar,
                            child: _buildClayCard(
                              borderRadius: 14,
                              depth: 2.2,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              child: const Text(
                                "Edit picture or avatar",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ---------------------------------------------------------
                    // Section 1: Public Identity Card (Clay Container)
                    // ---------------------------------------------------------
                    _buildSectionHeader("Public Identity", isSmall),
                    _buildClayCard(
                      borderRadius: 22,
                      depth: 3.5,
                      padding: EdgeInsets.all(isSmall ? 12 : 16),
                      child: Column(
                        children: [
                          _buildClayInputField(
                            label: "First Name",
                            controller: _firstNameCtrl,
                            hint: "First name",
                            isSmall: isSmall,
                          ),
                          const SizedBox(height: 12),
                          _buildClayInputField(
                            label: "Last Name",
                            controller: _lastNameCtrl,
                            hint: "Last name",
                            isSmall: isSmall,
                          ),
                          const SizedBox(height: 12),
                          _buildClayInputField(
                            label: "Username",
                            controller: _usernameCtrl,
                            hint: "username",
                            prefixText: "@ ",
                            isSmall: isSmall,
                          ),
                          if (_isCheckingUsername ||
                              _usernameStatusText != null ||
                              _usernameCooldownDaysLeft > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (_isCheckingUsername)
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: ZevColors.secondaryBlue,
                                    ),
                                  )
                                else if (_isUsernameAvailable != null)
                                  Icon(
                                    _isUsernameAvailable!
                                        ? Icons.check_circle_rounded
                                        : Icons.info_outline_rounded,
                                    size: 14,
                                    color: _isUsernameAvailable!
                                        ? ZevColors.successGreen
                                        : ZevColors.errorRed,
                                  )
                                else
                                  const Icon(
                                    Icons.lock_clock_outlined,
                                    size: 14,
                                    color: ZevColors.textMuted,
                                  ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _usernameStatusText ??
                                        'Username can be changed once every 14 days ($_usernameCooldownDaysLeft day${_usernameCooldownDaysLeft == 1 ? '' : 's'} remaining)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _isUsernameAvailable == true
                                          ? ZevColors.successGreen
                                          : (_isUsernameAvailable == false
                                                ? ZevColors.errorRed
                                                : ZevColors.textSecondary),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),

                          // Pronouns Input & Quick Selection Chips
                          _buildClayInputField(
                            label: "Pronouns",
                            controller: _pronounsCtrl,
                            hint: "He/Him, She/Her, They/Them",
                            isSmall: isSmall,
                          ),
                          const SizedBox(height: 8),

                          // Pronoun Chips in Tactile Clay Pills
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: _pronounSuggestions.map((pronoun) {
                                final isSelected =
                                    _pronounsCtrl.text.trim() == pronoun;
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _pronounsCtrl.text = pronoun;
                                    });
                                  },
                                  child: _buildClayCard(
                                    borderRadius: 12,
                                    depth: isSelected ? 1.5 : 2.5,
                                    color: isSelected
                                        ? const Color(0xFFE0F2FE)
                                        : Colors.white,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF0284C7)
                                          : Colors.white,
                                      width: 1.2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      pronoun,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                        color: isSelected
                                            ? const Color(0xFF0284C7)
                                            : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Bio Multi-line
                          _buildClayInputField(
                            label: "Bio",
                            controller: _bioCtrl,
                            hint: "Share your passions, philosophy, or goals...",
                            maxLines: 3,
                            isSmall: isSmall,
                          ),
                          const SizedBox(height: 12),

                          // Location
                          _buildClayInputField(
                            label: "Location",
                            controller: _locationCtrl,
                            hint: "City, Country",
                            prefixIcon: Icons.location_on_outlined,
                            isSmall: isSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ---------------------------------------------------------
                    // Section 2: Creator & Links (Instagram Pro Style)
                    // ---------------------------------------------------------
                    _buildSectionHeader(
                        "Creator & Professional Details", isSmall),
                    _buildClayCard(
                      borderRadius: 22,
                      depth: 3.5,
                      padding: EdgeInsets.all(isSmall ? 12 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildClayInputField(
                            label: "Primary Website",
                            controller: _websiteCtrl,
                            hint: "https://yourwebsite.com",
                            prefixIcon: Icons.link_rounded,
                            keyboardType: TextInputType.url,
                            isSmall: isSmall,
                          ),
                          const SizedBox(height: 12),

                          // Profile Links (user_links up to 5)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Profile Links (${_userLinks.length}/5)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.textSecondary,
                                ),
                              ),
                              if (_userLinks.length < 5)
                                GestureDetector(
                                  onTap: () => _showAddOrEditLinkSheet(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ZevColors.secondaryBlue
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.add_rounded,
                                          size: 14,
                                          color: ZevColors.secondaryBlue,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Add Link',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: ZevColors.secondaryBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (_isLoadingLinks)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ZevColors.primaryBlue,
                                  ),
                                ),
                              ),
                            )
                          else if (_userLinks.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            for (var i = 0; i < _userLinks.length; i++)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: ZevColors.softSurface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: ZevColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.public_rounded,
                                      size: 16,
                                      color: ZevColors.secondaryBlue,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (_userLinks[i]['title'] ?? '')
                                                    .toString()
                                                    .isNotEmpty
                                                ? _userLinks[i]['title']
                                                    .toString()
                                                : (_userLinks[i]['url'] ?? '')
                                                    .toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: ZevColors.deepNavy,
                                            ),
                                          ),
                                          Text(
                                            (_userLinks[i]['url'] ?? '')
                                                .toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: ZevColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          _showAddOrEditLinkSheet(editIndex: i),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 17,
                                        color: ZevColors.textSecondary,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 30,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          final existingId =
                                              _userLinks[i]['id']?.toString();
                                          if (existingId != null &&
                                              existingId.isNotEmpty) {
                                            _deletedLinkIds.add(existingId);
                                          }
                                          _userLinks.removeAt(i);
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 17,
                                        color: ZevColors.errorRed,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 30,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          const SizedBox(height: 12),

                          // Clay Dropdown: Category
                          _buildClayDropdown(
                            label: "Creator Category",
                            value: _selectedCategory,
                            items: _categories,
                            isSmall: isSmall,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedCategory = val);
                              }
                            },
                          ),
                          const SizedBox(height: 12),

                          // Clay Dropdown: Gender
                          _buildClayDropdown(
                            label: "Gender",
                            value: _selectedGender,
                            items: _genders,
                            isSmall: isSmall,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedGender = val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ---------------------------------------------------------
                    // Section 3: Profile Display Options (Instagram Toggles)
                    // ---------------------------------------------------------
                    _buildSectionHeader("Profile Display Options", isSmall),
                    _buildClayCard(
                      borderRadius: 22,
                      depth: 3.5,
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmall ? 12 : 16,
                        vertical: 10,
                      ),
                      child: Column(
                        children: [
                          _buildClaySwitchTile(
                            title: "Display category label",
                            subtitle:
                                "Show '$_selectedCategory' on your profile",
                            value: _showCategoryOnProfile,
                            isSmall: isSmall,
                            onChanged: (val) =>
                                setState(() => _showCategoryOnProfile = val),
                          ),
                          const Divider(height: 16, color: Color(0xFFF1F5F9)),
                          _buildClaySwitchTile(
                            title: "Display contact info",
                            subtitle:
                                "Show email and phone buttons to visitors",
                            value: _showContactInfo,
                            isSmall: isSmall,
                            onChanged: (val) =>
                                setState(() => _showContactInfo = val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ---------------------------------------------------------
                    // Section 4: Public Contact Details (If enabled)
                    // ---------------------------------------------------------
                    if (_showContactInfo) ...[
                      _buildSectionHeader("Public Contact Channels", isSmall),
                      _buildClayCard(
                        borderRadius: 22,
                        depth: 3.5,
                        padding: EdgeInsets.all(isSmall ? 12 : 16),
                        child: Column(
                          children: [
                            _buildClayInputField(
                              label: "Public Business Email",
                              controller: _publicEmailCtrl,
                              hint: "contact@example.com",
                              prefixIcon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              isSmall: isSmall,
                            ),
                            const SizedBox(height: 12),
                            _buildClayInputField(
                              label: "Public Phone / WhatsApp",
                              controller: _publicPhoneCtrl,
                              hint: "+93 79 ... or +1 ...",
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              isSmall: isSmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],

                    // ---------------------------------------------------------
                    // Big Tactile Clay Save Button
                    // ---------------------------------------------------------
                    GestureDetector(
                      onTap: _isSaving ? null : _saveProfile,
                      child: _buildClayCard(
                        borderRadius: 18,
                        depth: 4.5,
                        color: const Color(0xFF0284C7),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.8),
                          width: 1.6,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 19,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Save Profile",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isSmall ? 14 : 15.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Responsive Claymorphic Sub-Widgets
  // ---------------------------------------------------------------------------
  Widget _buildSectionHeader(String title, bool isSmall) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8, top: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: isSmall ? 10.5 : 11.5,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF64748B),
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _buildClayInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? prefixText,
    IconData? prefixIcon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    required bool isSmall,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: const [
          // Inset subtle recess shadow
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 12 : 14,
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isSmall ? 10 : 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (prefixIcon != null) ...[
                Icon(prefixIcon, size: 16, color: const Color(0xFF94A3B8)),
                const SizedBox(width: 8),
              ],
              if (prefixText != null) ...[
                Text(
                  prefixText,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: maxLines,
                  keyboardType: keyboardType,
                  style: TextStyle(
                    fontSize: isSmall ? 13 : 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: const Color(0xFFCBD5E1),
                      fontSize: isSmall ? 12 : 13,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClayDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required bool isSmall,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 12 : 14,
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isSmall ? 10 : 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF0284C7),
                size: 20,
              ),
              style: TextStyle(
                fontSize: isSmall ? 13 : 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaySwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isSmall,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isSmall ? 12.5 : 13.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: isSmall ? 10.5 : 11.5,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch.adaptive(
          value: value,
          onChanged: (v) {
            HapticFeedback.lightImpact();
            onChanged(v);
          },
          activeTrackColor: const Color(0xFF0284C7),
        ),
      ],
    );
  }
}
