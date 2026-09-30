import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/activity_log_service.dart';
import '../services/auth_helper.dart';
import '../services/notification_service.dart';
import '../services/security_service.dart';
import '../services/web_navigation_service.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/main_navigation/screens/zev_main_layout.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  Widget _targetScreen = const WelcomeScreen();

  static const Color primaryPink = Color(0xFFFC466B);

  @override
  void initState() {
    super.initState();
    _initializeAuthListener();
  }

  void _initializeAuthListener() {
    try {
      supabase.auth.onAuthStateChange.listen(
        (data) {
          final AuthChangeEvent event = data.event;
          final Session? session = data.session;

          if (event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.initialSession ||
              event == AuthChangeEvent.userUpdated) {
            if (session != null) {
              _resolveUserSessionAndRole(session);
            }
          } else if (event == AuthChangeEvent.signedOut) {
            _handleExplicitSignOut();
          }
        },
        onError: (error) {
          debugPrint('Auth stream error: $error');
        },
      );

      _checkInitialSession();
    } catch (e) {
      debugPrint('Auth listener setup failed: $e');
      _showFallbackScreen();
    }
  }

  Future<void> _checkInitialSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isUserLoggedIn =
          prefs.getBool(AuthHelper.keyUserLoggedIn) ?? false;
      final bool isExplicitlyLoggedOut =
          prefs.getBool(AuthHelper.keyUserExplicitlyLoggedOut) ?? false;

      // 1. If previously logged in and did not explicitly log out
      if (isUserLoggedIn && !isExplicitlyLoggedOut) {
        if (supabase.auth.currentSession != null) {
          await _resolveUserSessionAndRole(supabase.auth.currentSession);
          return;
        }

        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;
          if (supabase.auth.currentSession != null) {
            await _resolveUserSessionAndRole(supabase.auth.currentSession);
            return;
          }
        }

        if (mounted) {
          setState(() {
            _targetScreen = ZevMainLayout(
              initialIndex: WebNavigationService.instance.getInitialTabIndex(),
            );
            _isLoading = false;
          });
        }
        return;
      }

      // 2. Standard session check
      if (supabase.auth.currentSession != null) {
        await _resolveUserSessionAndRole(supabase.auth.currentSession);
        return;
      }

      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        if (supabase.auth.currentSession != null) {
          await _resolveUserSessionAndRole(supabase.auth.currentSession);
          return;
        }
      }

      // 3. Fallback
      await _showFallbackScreen();
    } catch (e) {
      debugPrint("Error in _checkInitialSession: $e");
      await _showFallbackScreen();
    }
  }

  Future<void> _handleExplicitSignOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isExplicit =
          prefs.getBool(AuthHelper.keyUserExplicitlyLoggedOut) ?? false;
      if (isExplicit) {
        _showFallbackScreen();
      } else {
        debugPrint(
          "Temporary signedOut event ignored because user did not explicitly log out",
        );
      }
    } catch (_) {
      _showFallbackScreen();
    }
  }

  Future<void> _showFallbackScreen() async {
    if (!mounted) return;
    try {
      final user = supabase.auth.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final bool isExplicit =
          prefs.getBool(AuthHelper.keyUserExplicitlyLoggedOut) ?? false;
      final bool isUserLoggedIn =
          prefs.getBool(AuthHelper.keyUserLoggedIn) ?? false;

      if ((user != null || isUserLoggedIn) && !isExplicit) {
        if (mounted) {
          setState(() {
            _targetScreen = ZevMainLayout(
              initialIndex: WebNavigationService.instance.getInitialTabIndex(),
            );
            _isLoading = false;
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _targetScreen = const WelcomeScreen();
        _isLoading = false;
      });
    }
  }

  Future<void> _resolveUserSessionAndRole(Session? session) async {
    try {
      final user = session?.user ?? supabase.auth.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final bool isExplicit =
          prefs.getBool(AuthHelper.keyUserExplicitlyLoggedOut) ?? false;
      final bool isUserLoggedIn =
          prefs.getBool(AuthHelper.keyUserLoggedIn) ?? false;

      if (user == null) {
        if (!isUserLoggedIn || isExplicit) {
          await _showFallbackScreen();
        } else {
          if (mounted) {
            setState(() {
              _targetScreen = ZevMainLayout(
                initialIndex: WebNavigationService.instance
                    .getInitialTabIndex(),
              );
              _isLoading = false;
            });
          }
        }
        return;
      }

      await prefs.setBool(AuthHelper.keyUserExplicitlyLoggedOut, false);
      await prefs.setBool(AuthHelper.keyUserLoggedIn, true);

      if (!mounted) return;

      Widget destination = ZevMainLayout(
        initialIndex: WebNavigationService.instance.getInitialTabIndex(),
      );

      try {
        NotificationService().saveFCMTokenToDatabase();
      } catch (_) {}

      try {
        ActivityLogService.instance.recordLogin(user.id);
      } catch (_) {}

      setState(() {
        _targetScreen = destination;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          SecurityService.instance.verifyLockIfNeeded(context);
        }
      });
    } catch (e) {
      debugPrint("Auth Resolution Error: $e");
      if (mounted) {
        final user = session?.user ?? supabase.auth.currentUser;
        if (user != null) {
          setState(() {
            _targetScreen = ZevMainLayout(
              initialIndex: WebNavigationService.instance.getInitialTabIndex(),
            );
            _isLoading = false;
          });
        } else {
          await _showFallbackScreen();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: primaryPink)),
      );
    }

    return _targetScreen;
  }
}
