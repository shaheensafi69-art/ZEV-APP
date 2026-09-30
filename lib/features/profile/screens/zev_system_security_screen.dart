import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/security_service.dart';
import '../../../core/utils/zev_alert.dart';
import '../../../core/widgets/circular_flag.dart';
import '../../../core/widgets/responsive_layout.dart';
import 'zev_device_activities_screen.dart';

class ZevSystemSecurityScreen extends StatefulWidget {
  const ZevSystemSecurityScreen({super.key});

  @override
  State<ZevSystemSecurityScreen> createState() =>
      _ZevSystemSecurityScreenState();
}

class _ZevSystemSecurityScreenState extends State<ZevSystemSecurityScreen> {
  final supabase = Supabase.instance.client;
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFFF0F5);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  bool _isBiometricEnabled = false;
  bool _canCheckBiometrics = false;
  String _currentPin = "";
  bool _hasPin = false;
  bool _isLoadingSecurity = true;

  // Password fields
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isChangingPassword = false;

  @override
  void initState() {
    super.initState();
    _initBiometricsAndSettings();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _initBiometricsAndSettings() async {
    setState(() => _isLoadingSecurity = true);
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      final prefs = await SharedPreferences.getInstance();
      final localBio = prefs.getBool('zev_biometrics_enabled') ?? false;

      final user = supabase.auth.currentUser;
      String pin = "";
      bool dbBio = false;
      if (user != null) {
        final res = await supabase
            .from('student_security_settings')
            .select('pin_code, is_biometric_enabled')
            .eq('student_id', user.id)
            .maybeSingle();

        if (res != null) {
          pin = res['pin_code']?.toString() ?? '';
          dbBio = res['is_biometric_enabled'] ?? false;
        }
      }

      if (mounted) {
        setState(() {
          _canCheckBiometrics = canCheck || isSupported;
          _isBiometricEnabled = dbBio || localBio;
          _currentPin = pin;
          _hasPin = pin.isNotEmpty;
          _isLoadingSecurity = false;
        });
      }
    } catch (e) {
      debugPrint("Error initializing security settings: $e");
      if (mounted) setState(() => _isLoadingSecurity = false);
    }
  }

  Future<void> _toggleBiometrics(bool enable) async {
    if (enable) {
      if (!_canCheckBiometrics) {
        ZevAlert.error(
          context,
          "Biometric hardware (Fingerprint / Face ID) is not available on this device.",
        );
        return;
      }

      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason:
              'Scan fingerprint or Face ID to enable biometric login for ZEV',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );

        if (!authenticated) {
          if (!mounted) return;
          ZevAlert.error(
            context,
            "Biometric authentication was cancelled or not recognized.",
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        ZevAlert.error(context, e);
        return;
      }
    }

    setState(() => _isBiometricEnabled = enable);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('zev_biometrics_enabled', enable);

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('student_security_settings').upsert({
          'student_id': user.id,
          'is_biometric_enabled': enable,
          'pin_code': _currentPin.isNotEmpty ? _currentPin : null,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      if (!mounted) return;
      if (enable) {
        ZevAlert.success(
          context,
          "Biometric authentication activated successfully!",
        );
      } else {
        ZevAlert.show(
          context,
          "Biometric authentication disabled.",
          isError: false,
        );
      }
    } catch (e) {
      debugPrint("Error syncing biometrics with server: $e");
    }
  }

  /// Show dialog to set or update 4-digit PIN
  void _showSetPinDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF334155) : lightPinkBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pin_rounded,
                color: primaryPink,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _hasPin ? context.zevTr('changePin') : context.zevTr('setPin'),
              style: TextStyle(
                color: isDark ? Colors.white : textDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Enter a 4-digit security PIN to lock and protect your ZEV account.",
              style: TextStyle(
                color: isDark ? Colors.white70 : textGrey,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              textAlign: TextAlign.center,
              autofocus: true,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 14,
                color: isDark ? Colors.white : textDark,
              ),
              decoration: InputDecoration(
                counterText: "",
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : cardBorder,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryPink, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              context.zevTr('cancel'),
              style: TextStyle(color: isDark ? Colors.white60 : textGrey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final pin = controller.text.trim();
              if (pin.length != 4) {
                ZevAlert.error(context, "PIN code must be exactly 4 digits.");
                return;
              }

              Navigator.pop(ctx);
              setState(() {
                _currentPin = pin;
                _hasPin = true;
              });

              await SecurityService.instance.saveSecuritySettings(
                enabled: true,
                pin: pin,
              );

              if (!mounted) return;
              ZevAlert.success(
                context,
                "4-digit security PIN saved successfully!",
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryPink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              context.zevTr('save'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Turn off and disable PIN completely
  void _confirmDisablePin() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.lock_open_rounded, color: primaryPink, size: 24),
            const SizedBox(width: 8),
            Text(
              "Disable PIN Lock",
              style: TextStyle(
                color: isDark ? Colors.white : textDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        content: Text(
          context.zevTr('disablePinConfirm'),
          style: TextStyle(
            color: isDark ? Colors.white70 : textGrey,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              context.zevTr('cancel'),
              style: TextStyle(color: isDark ? Colors.white60 : textGrey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await SecurityService.instance.disablePin();
              if (!mounted) return;
              setState(() {
                _hasPin = false;
                _currentPin = "";
              });
              ZevAlert.success(context, "PIN code has been disabled.");
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              "Disable PIN",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    final cur = _currentPasswordController.text.trim();
    final np = _newPasswordController.text.trim();
    final cp = _confirmPasswordController.text.trim();

    if (cur.isEmpty || np.isEmpty || cp.isEmpty) {
      ZevAlert.error(context, "Please fill in all password fields.");
      return;
    }

    if (np.length < 6) {
      ZevAlert.error(context, "New password must be at least 6 characters.");
      return;
    }

    if (np != cp) {
      ZevAlert.error(context, "New passwords do not match.");
      return;
    }

    setState(() => _isChangingPassword = true);
    try {
      await supabase.auth.updateUser(UserAttributes(password: np));
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      if (!mounted) return;
      ZevAlert.success(context, "Password updated successfully!");
    } catch (e) {
      if (!mounted) return;
      ZevAlert.error(context, e);
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  void _showLanguageSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131926) : surfaceWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.zevTr('language'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : textDark,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white70 : textGrey,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Divider(
                color: isDark ? const Color(0xFF1E293B) : cardBorder,
                height: 1,
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: LanguageService.supportedLanguages.length,
                  separatorBuilder: (_, _) => Divider(
                    color: isDark ? const Color(0xFF1E293B) : cardBorder,
                    height: 1,
                    indent: 64,
                  ),
                  itemBuilder: (context, index) {
                    final lang = LanguageService.supportedLanguages[index];
                    final isSelected =
                        LanguageService.instance.currentLanguageCode ==
                        lang.code;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      leading: CircularFlag(
                        countryCode: lang.countryCode,
                        size: 34,
                      ),
                      title: Text(
                        lang.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isSelected
                              ? primaryPink
                              : (isDark ? Colors.white : textDark),
                        ),
                      ),
                      subtitle: Text(
                        lang.englishName,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : textGrey,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: primaryPink,
                              size: 22,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        LanguageService.instance.changeLanguage(lang.code);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, activeLocale, _) {
        final currentLang = LanguageService.instance.currentLanguage;
        final isRtl = LanguageService.isRtl(activeLocale.languageCode);

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final scaffoldBg = isDark ? const Color(0xFF0B0F19) : surfaceWhite;
        final appbarBg = isDark ? const Color(0xFF131926) : surfaceWhite;
        final cardBg = isDark ? const Color(0xFF131926) : surfaceWhite;
        final cardBorderColor = isDark ? const Color(0xFF1E293B) : cardBorder;
        final primaryTextColor = isDark ? Colors.white : textDark;
        final secondaryTextColor = isDark ? Colors.white70 : textGrey;
        final iconBg = isDark ? const Color(0xFF1E293B) : lightPinkBg;

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: scaffoldBg,
            appBar: AppBar(
              backgroundColor: appbarBg,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: primaryTextColor,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                context.zevTr('systemSecurity'),
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            body: ResponsiveLayout.feedConstraint(
              maxWidth: 600,
              child: _isLoadingSecurity
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: primaryPink,
                        strokeWidth: 2.5,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      children: [
                        // --- BIOMETRICS & PIN ---
                        _buildSectionHeader(
                          context.zevTr('authAndAccess'),
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),

                        // Biometric Toggle Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: cardBorderColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: iconBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.fingerprint_rounded,
                                  color: primaryPink,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.zevTr('biometricLogin'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _canCheckBiometrics
                                          ? context.zevTr('biometricFast')
                                          : context.zevTr(
                                              'biometricUnavailable',
                                            ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _canCheckBiometrics
                                            ? secondaryTextColor
                                            : Colors.orange.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isBiometricEnabled,
                                onChanged: _canCheckBiometrics
                                    ? _toggleBiometrics
                                    : null,
                                activeThumbColor: Colors.white,
                                activeTrackColor: primaryPink,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // PIN Code Card with Switch Toggle (Turn Off / Turn On)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: cardBorderColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: iconBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.pin_rounded,
                                  color: primaryPink,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: InkWell(
                                  onTap: _hasPin
                                      ? _showSetPinDialog
                                      : _showSetPinDialog,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.zevTr('appPinCode'),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: primaryTextColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _hasPin
                                            ? "${context.zevTr('pinActive')} • ${context.zevTr('changePin')}"
                                            : context.zevTr('pinDisabled'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _hasPin
                                              ? const Color(0xFF10B981)
                                              : secondaryTextColor,
                                          fontWeight: _hasPin
                                              ? FontWeight.w700
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Switch(
                                value: _hasPin,
                                onChanged: (value) {
                                  if (value) {
                                    _showSetPinDialog();
                                  } else {
                                    _confirmDisablePin();
                                  }
                                },
                                activeThumbColor: Colors.white,
                                activeTrackColor: primaryPink,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // --- DEVICE ACTIVITY BUTTON ---
                        _buildSectionHeader(
                          context.zevTr('sessionsActivity'),
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),

                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const ZevDeviceActivitiesScreen(),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cardBorderColor),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: iconBg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.devices_rounded,
                                    color: primaryPink,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.zevTr('deviceActivity'),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: primaryTextColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        context.zevTr('deviceActivitySub'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: secondaryTextColor,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // --- LANGUAGE PREFERENCES ---
                        _buildSectionHeader(
                          context.zevTr('langPreferences'),
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),

                        InkWell(
                          onTap: _showLanguageSelector,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cardBorderColor),
                            ),
                            child: Row(
                              children: [
                                CircularFlag(
                                  countryCode: currentLang.countryCode,
                                  size: 32,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.zevTr('language'),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: primaryTextColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "${currentLang.name} (${currentLang.englishName})",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: primaryPink,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: secondaryTextColor,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // --- PASSWORD MANAGEMENT ---
                        _buildSectionHeader(
                          context.zevTr('passwordManagement'),
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: cardBorderColor),
                          ),
                          child: Column(
                            children: [
                              _buildPasswordField(
                                controller: _currentPasswordController,
                                hint: context.zevTr('currentPassword'),
                                obscure: _obscureCurrent,
                                onToggle: () => setState(
                                  () => _obscureCurrent = !_obscureCurrent,
                                ),
                                isDark: isDark,
                              ),
                              const SizedBox(height: 12),
                              _buildPasswordField(
                                controller: _newPasswordController,
                                hint: context.zevTr('newPassword'),
                                obscure: _obscureNew,
                                onToggle: () =>
                                    setState(() => _obscureNew = !_obscureNew),
                                isDark: isDark,
                              ),
                              const SizedBox(height: 12),
                              _buildPasswordField(
                                controller: _confirmPasswordController,
                                hint: context.zevTr('confirmNewPassword'),
                                obscure: _obscureConfirm,
                                onToggle: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                                isDark: isDark,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isChangingPassword
                                      ? null
                                      : _changePassword,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryPink,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: _isChangingPassword
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          context.zevTr('updatePassword'),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, {bool isDark = false}) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white70 : textGrey,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    bool isDark = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : cardBorder,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(fontSize: 14, color: isDark ? Colors.white : textDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : textGrey,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: isDark ? Colors.white54 : textGrey,
              size: 20,
            ),
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }
}
