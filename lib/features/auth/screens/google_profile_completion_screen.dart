import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/auth_session_manager.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_text_field.dart';
import '../../main_navigation/screens/zev_main_layout.dart';

/// Dedicated Onboarding / Profile Setup Screen for users signing in via Google.
/// Captures all necessary ZEV profile information that Google OAuth does not provide:
/// - Unique @username (with live debounce availability checker)
/// - Date of Birth (with interactive date picker)
/// - Country
/// - Phone Number
/// - Bio / About me
/// - Avatar customizer (pre-filled with Google photo)
class GoogleProfileCompletionScreen extends StatefulWidget {
  final User user;
  final Map<String, dynamic>? existingProfile;

  const GoogleProfileCompletionScreen({
    super.key,
    required this.user,
    this.existingProfile,
  });

  @override
  State<GoogleProfileCompletionScreen> createState() =>
      _GoogleProfileCompletionScreenState();
}

class _GoogleProfileCompletionScreenState
    extends State<GoogleProfileCompletionScreen> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _bioCtrl;

  String _avatarUrl = '';
  File? _customAvatarFile;
  DateTime? _dob;
  String _selectedCountry = 'United States';

  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameError;
  Timer? _usernameDebounce;

  bool _isLoading = false;
  String? _errorMsg;

  final List<Map<String, String>> _countries = [
    {'name': 'United States', 'flag': '🇺🇸'},
    {'name': 'Afghanistan', 'flag': '🇦🇫'},
    {'name': 'Germany', 'flag': '🇩🇪'},
    {'name': 'United Kingdom', 'flag': '🇬🇧'},
    {'name': 'Canada', 'flag': '🇨🇦'},
    {'name': 'Turkey', 'flag': '🇹🇷'},
    {'name': 'United Arab Emirates', 'flag': '🇦🇪'},
    {'name': 'Iran', 'flag': '🇮🇷'},
    {'name': 'Australia', 'flag': '🇦🇺'},
    {'name': 'France', 'flag': '🇫🇷'},
    {'name': 'Netherlands', 'flag': '🇳🇱'},
    {'name': 'Sweden', 'flag': '🇸🇪'},
    {'name': 'India', 'flag': '🇮🇳'},
    {'name': 'Pakistan', 'flag': '🇵🇰'},
    {'name': 'Saudi Arabia', 'flag': '🇸🇦'},
    {'name': 'Other', 'flag': '🌍'},
  ];

  @override
  void initState() {
    super.initState();
    final meta = widget.user.userMetadata ?? {};
    final existing = widget.existingProfile ?? {};

    // 1. Resolve names
    String firstName = existing['first_name']?.toString() ?? '';
    String lastName = existing['last_name']?.toString() ?? '';

    if (firstName.isEmpty) {
      firstName = (meta['given_name'] ?? meta['first_name'] ?? '').toString();
    }
    if (lastName.isEmpty) {
      lastName = (meta['family_name'] ?? meta['last_name'] ?? '').toString();
    }

    if (firstName.isEmpty && meta['full_name'] != null) {
      final parts = meta['full_name'].toString().trim().split(' ');
      firstName = parts.first;
      if (parts.length > 1) {
        lastName = parts.sublist(1).join(' ');
      }
    }

    // 2. Resolve avatar
    _avatarUrl = existing['avatar_url']?.toString() ??
        meta['avatar_url']?.toString() ??
        meta['picture']?.toString() ??
        '';

    // 3. Resolve username suggestion
    String suggestedUsername = existing['username']?.toString() ?? '';
    if (suggestedUsername.isEmpty || suggestedUsername.startsWith('user_')) {
      final emailPrefix = (widget.user.email ?? '')
          .split('@')
          .first
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
          .toLowerCase();
      suggestedUsername = emailPrefix.isNotEmpty ? emailPrefix : 'user';
    }

    _firstNameCtrl = TextEditingController(text: firstName);
    _lastNameCtrl = TextEditingController(text: lastName);
    _usernameCtrl = TextEditingController(text: suggestedUsername);
    _phoneCtrl = TextEditingController(
      text: existing['phone_number']?.toString() ?? '',
    );
    _bioCtrl = TextEditingController(text: existing['bio']?.toString() ?? '');

    if (existing['country'] != null && existing['country'].toString().isNotEmpty) {
      _selectedCountry = existing['country'].toString();
    }

    if (existing['date_of_birth'] != null) {
      _dob = DateTime.tryParse(existing['date_of_birth'].toString());
    }

    _usernameCtrl.addListener(_onUsernameChanged);

    // Initial check for pre-filled username
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUsernameAvailability(_usernameCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameCtrl.removeListener(_onUsernameChanged);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final raw = _usernameCtrl.text.trim().toLowerCase();
    _usernameDebounce?.cancel();

    if (raw.length < 3) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameError = "Username must be at least 3 characters";
      });
      return;
    }

    if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(raw)) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameError = "Letters, numbers, and underscores only";
      });
      return;
    }

    _usernameDebounce = Timer(const Duration(milliseconds: 350), () {
      _checkUsernameAvailability(raw);
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    final clean = username.trim().toLowerCase();
    if (clean.length < 3) return;

    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    try {
      final res = await supabase
          .from('profiles')
          .select('id')
          .ilike('username', clean)
          .neq('id', widget.user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = res == null;
          _usernameError = res != null ? "This @username is already taken" : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = true;
        });
      }
    }
  }

  Future<void> _pickCustomAvatar() async {
    HapticFeedback.lightImpact();
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 88,
      );
      if (picked != null) {
        setState(() {
          _customAvatarFile = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint("Avatar picker notice: $e");
    }
  }

  Future<void> _selectDateOfBirth() async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final initialDate = _dob ?? DateTime(now.year - 18, now.month, now.day);
    final firstDate = DateTime(1930);
    final lastDate = DateTime(now.year - 10, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(lastDate) ? lastDate : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: ZevColors.primaryBlue,
              onPrimary: ZevColors.deepNavy,
              surface: Colors.white,
              onSurface: ZevColors.deepNavy,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  Future<void> _submitProfile() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();

    if (firstName.isEmpty || lastName.isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMsg = "Please enter your first and last name.");
      return;
    }

    if (username.length < 3 || _isUsernameAvailable == false) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMsg = "Please choose a valid and available username.");
      return;
    }

    if (_dob == null) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMsg = "Please select your date of birth.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      String finalAvatarUrl = _avatarUrl;

      // 1. Upload custom avatar if chosen
      if (_customAvatarFile != null) {
        final ext = _customAvatarFile!.path.split('.').last;
        final fileName =
            'avatar_${widget.user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        try {
          finalAvatarUrl = await CloudflareStorageService.instance.upload(
            bucket: 'avatars',
            path: fileName,
            file: _customAvatarFile,
          );
        } catch (uploadErr) {
          debugPrint("Custom avatar upload notice: $uploadErr");
        }
      }

      final dobString = DateFormat('yyyy-MM-dd').format(_dob!);

      // 2. Upsert completed profile
      await supabase.from('profiles').upsert({
        'id': widget.user.id,
        'email': widget.user.email ?? '',
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'avatar_url': finalAvatarUrl,
        'date_of_birth': dobString,
        'country': _selectedCountry,
        'phone_number': _phoneCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'is_phone_hidden': false,
        'is_dob_hidden': false,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 3. Mark user logged in locally and sync FCM
      await AuthHelper.markUserLoggedIn(
        userId: widget.user.id,
        role: 'user',
      );
      unawaited(
        AuthSessionManager.instance.recordSecurityEvent(
          userId: widget.user.id,
          eventType: 'google_profile_completed',
        ),
      );

      // 4. Save into multi-account manager
      await MultiAccountService.saveCurrentAccount(
        overrideUsername: username,
        overrideFullName: '$firstName $lastName'.trim(),
        overrideAvatar: finalAvatarUrl,
      );

      if (!mounted) return;

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Welcome to ZEV, @$username! Profile completed.",
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.deepNavy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ZevMainLayout()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = widget.user.email ?? '';

    return Scaffold(
      backgroundColor: ZevColors.white,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Complete Your Profile",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Google Connected Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/icon/google_logo.png',
                          width: 17,
                          height: 17,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.account_circle_rounded,
                            size: 17,
                            color: ZevColors.secondaryBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          userEmail,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 2. Avatar with Change Camera overlay
                  GestureDetector(
                    onTap: _pickCustomAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ZevColors.primaryBlue,
                              width: 3.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: _customAvatarFile != null
                                ? Image.file(_customAvatarFile!, fit: BoxFit.cover)
                                : (_avatarUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: _avatarUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: ZevColors.primaryBlue,
                                          ),
                                        ),
                                        errorWidget: (_, _, _) => Image.asset(
                                          'assets/icon/icon-192x192.png',
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Image.asset(
                                        'assets/icon/icon-192x192.png',
                                        fit: BoxFit.cover,
                                      )),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: ZevColors.deepNavy,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Text(
                    "Set Profile Picture",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.secondaryBlue,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Error Banner
                  if (_errorMsg != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMsg!,
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // 3. First Name & Last Name in Row
                  Row(
                    children: [
                      Expanded(
                        child: ZevTextField(
                          label: "First Name",
                          hint: "First name",
                          controller: _firstNameCtrl,
                          prefixIcon: Icons.badge_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ZevTextField(
                          label: "Last Name",
                          hint: "Last name",
                          controller: _lastNameCtrl,
                          prefixIcon: Icons.badge_outlined,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 4. Unique Username
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ZevTextField(
                        label: "Choose Username (@)",
                        hint: "username",
                        controller: _usernameCtrl,
                        prefixIcon: Icons.alternate_email_rounded,
                        suffixIcon: _isCheckingUsername
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ZevColors.primaryBlue,
                                  ),
                                ),
                              )
                            : (_isUsernameAvailable != null
                                ? Icon(
                                    _isUsernameAvailable!
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    color: _isUsernameAvailable!
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFDC2626),
                                    size: 20,
                                  )
                                : null),
                      ),
                      if (_usernameError != null) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            _usernameError!,
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else if (_isUsernameAvailable == true) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: const Text(
                            "✓ Username is available!",
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 5. Date of Birth Picker
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 6),
                        child: Text(
                          "Date of Birth",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _selectDateOfBirth,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: ZevColors.softSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: ZevColors.border, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.cake_outlined,
                                color: ZevColors.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _dob != null
                                    ? DateFormat('MMMM dd, yyyy').format(_dob!)
                                    : "Select your date of birth",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: _dob != null
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _dob != null
                                      ? ZevColors.deepNavy
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.calendar_month_rounded,
                                color: ZevColors.primaryBlue,
                                size: 19,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 6. Country Selector
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 6),
                        child: Text(
                          "Country",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: ZevColors.softSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: ZevColors.border, width: 1.2),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedCountry,
                            isExpanded: true,
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: ZevColors.deepNavy,
                            ),
                            items: _countries.map((c) {
                              return DropdownMenuItem<String>(
                                value: c['name'],
                                child: Row(
                                  children: [
                                    Text(
                                      c['flag'] ?? '',
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      c['name'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: ZevColors.deepNavy,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedCountry = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 7. Phone Number
                  ZevTextField(
                    label: "Phone Number",
                    hint: "+1 234 567 8900",
                    controller: _phoneCtrl,
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),

                  const SizedBox(height: 18),

                  // 8. Bio
                  ZevTextField(
                    label: "Bio (Optional)",
                    hint: "Write something about yourself...",
                    controller: _bioCtrl,
                    prefixIcon: Icons.info_outline_rounded,
                    maxLines: 3,
                  ),

                  const SizedBox(height: 32),

                  // 9. Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: ZevColors.brandGradientHorizontal,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Complete Profile & Enter ZEV",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
