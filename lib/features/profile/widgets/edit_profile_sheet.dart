import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/content_safety_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';

/// Serene, Instagram-Grade Edit Profile Bottom Sheet for ZEV.
/// Allows updating avatar (via Cloudflare R2), name, username, bio, and website.
class EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic> initialProfile;
  final ValueChanged<Map<String, dynamic>> onProfileUpdated;

  const EditProfileSheet({
    super.key,
    required this.initialProfile,
    required this.onProfileUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> initialProfile,
    required ValueChanged<Map<String, dynamic>> onProfileUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditProfileSheet(
        initialProfile: initialProfile,
        onProfileUpdated: onProfileUpdated,
      ),
    );
  }

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _countryCtrl;

  File? _newAvatarFile;
  String _currentAvatarUrl = '';
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _firstNameCtrl = TextEditingController(text: p['first_name'] ?? '');
    _lastNameCtrl = TextEditingController(text: p['last_name'] ?? '');
    _usernameCtrl = TextEditingController(text: p['username'] ?? '');
    _bioCtrl = TextEditingController(text: p['bio'] ?? '');
    _countryCtrl = TextEditingController(text: p['country'] ?? '');
    _currentAvatarUrl = p['avatar_url'] ?? '';
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 720,
      );
      if (picked != null) {
        setState(() => _newAvatarFile = File(picked.path));
      }
    } catch (e) {
      debugPrint("Avatar pick notice: $e");
    }
  }

  Future<void> _handleSave() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final username = _usernameCtrl.text.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() => _errorMessage = "Username cannot be empty.");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      String avatarUrl = _currentAvatarUrl;

      // 1. Upload new avatar if picked
      if (_newAvatarFile != null) {
        // Pre-upload +18 and Violence Safety Check
        final safetyResult =
            await ContentSafetyService.instance.checkImageSafety(
          file: _newAvatarFile,
        );
        if (!safetyResult.isSafe) {
          if (mounted) {
            setState(() {
              _isSaving = false;
              _errorMessage = safetyResult.errorMessage ??
                  "This avatar was flagged as inappropriate (+18) and cannot be used.";
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  safetyResult.errorMessage ??
                      "Avatar flagged as inappropriate (+18).",
                ),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        final ext = _newAvatarFile!.path.split('.').last;
        final fileName =
            'avatar_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        avatarUrl = await CloudflareStorageService.instance.upload(
          bucket: 'avatars',
          path: fileName,
          file: _newAvatarFile,
        );
      }

      final updatedData = {
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'username': username,
        'bio': _bioCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        'avatar_url': avatarUrl,
      };

      // 2. Update Supabase profiles table
      await supabase.from('profiles').update(updatedData).eq('id', user.id);

      HapticFeedback.lightImpact();
      widget.onProfileUpdated({
        ...widget.initialProfile,
        ...updatedData,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Profile updated successfully!"),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.90,
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
          // Clay Drag Handle
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
          const SizedBox(height: 12),

          // Header: Cancel ('✕') | Edit Profile | Save ('✓')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                          blurRadius: 8,
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
                const Text(
                  "Edit Profile",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                    letterSpacing: -0.3,
                  ),
                ),
                _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ZevColors.primaryBlue,
                        ),
                      )
                    : GestureDetector(
                        onTap: _handleSave,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00D4FF), Color(0xFF0095F6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.9),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Form Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // Avatar with "Edit picture" Button
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                  const BoxShadow(
                                    color: Colors.white,
                                    blurRadius: 6,
                                    offset: Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: _newAvatarFile != null
                                    ? Image.file(_newAvatarFile!,
                                        fit: BoxFit.cover)
                                    : (_currentAvatarUrl.isNotEmpty
                                        ? ZevCachedImage.avatar(
                                            imageUrl: _currentAvatarUrl,
                                            size: 96,
                                          )
                                        : const Icon(
                                            Icons.person_rounded,
                                            size: 48,
                                            color: ZevColors.textMuted,
                                          )),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00D4FF), Color(0xFF0095F6)],
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
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
                        const SizedBox(height: 8),
                        const Text(
                          "Change Profile Photo",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.secondaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // First Name & Last Name
                  Row(
                    children: [
                      Expanded(
                        child: _buildFormField(
                          label: "First Name",
                          controller: _firstNameCtrl,
                          hint: "First name",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFormField(
                          label: "Last Name",
                          controller: _lastNameCtrl,
                          hint: "Last name",
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Username
                  _buildFormField(
                    label: "Username",
                    controller: _usernameCtrl,
                    hint: "username",
                    prefixText: "@",
                  ),
                  const SizedBox(height: 14),

                  // Bio
                  _buildFormField(
                    label: "Bio",
                    controller: _bioCtrl,
                    hint: "Write a bio about yourself...",
                    maxLines: 3,
                  ),
                  const SizedBox(height: 14),

                  // Country
                  _buildFormField(
                    label: "Country / Location",
                    controller: _countryCtrl,
                    hint: "e.g. Afghanistan, USA, Germany",
                    prefixIcon: Icons.location_on_outlined,
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    String? prefixText,
    IconData? prefixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              const BoxShadow(
                color: Colors.white,
                blurRadius: 4,
                offset: Offset(0, -1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              if (prefixText != null) ...[
                Text(
                  prefixText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (prefixIcon != null) ...[
                Icon(prefixIcon, size: 18, color: ZevColors.textMuted),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: maxLines,
                  style: const TextStyle(
                    fontSize: 14,
                    color: ZevColors.deepNavy,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontSize: 13.5,
                      color: ZevColors.textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

