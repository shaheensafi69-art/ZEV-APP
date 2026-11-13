import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/services/admob_service.dart';
import 'core/services/app_session_tracker_service.dart';
import 'core/services/auth_helper.dart';
import 'core/services/auth_session_manager.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/secure_local_storage.dart';
import 'core/services/user_presence_service.dart';
import 'core/services/zev_rtc_service.dart';
import 'core/theme/zev_theme.dart';
import 'core/utils/system_ui_helper.dart';
import 'features/splash/screens/zev_splash_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // High-performance image cache tuning for silky smooth 120 FPS scrolling
  PaintingBinding.instance.imageCache.maximumSizeBytes = 250 << 20; // 250 MB
  PaintingBinding.instance.imageCache.maximumSize = 500;

  // 1. Enable Full-Screen Immersive Mode & Hide System Navigation Bar
  await SystemUiHelper.enableFullScreen();

  // 2. Initialize OS-encrypted Supabase session storage (Keystore / Keychain)
  final secureStorage = SecureLocalStorage(
    persistSessionKey: AppConfig.supabasePersistSessionKey,
  );
  await secureStorage.initialize();

  // 3. Initialize Supabase with public build-time config & encrypted session storage
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: secureStorage,
          detectSessionInUri: true,
        ),
      );
      break;
    } catch (e) {
      debugPrint('Supabase initialization attempt $attempt failed: $e');
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  // 4. Initialize Auth Session Lifecycle Manager (singleflight token refresh)
  AuthSessionManager.instance.init();

  // 5. Initialize Push Notifications & Firebase
  unawaited(NotificationService().initPushNotifications());

  // 6. Initialize Google Mobile Ads (Native in-stream Ad Units)
  unawaited(AdmobService.instance.init());

  // 7. Initial home is the flagship cinematic animated ZEV splash screen
  runApp(const ZevApp(home: ZevSplashScreen()));
}

class ZevApp extends StatefulWidget {
  final Widget home;
  const ZevApp({super.key, required this.home});

  @override
  State<ZevApp> createState() => _ZevAppState();
}

class _ZevAppState extends State<ZevApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemUiHelper.enableFullScreen();
    UserPresenceService.instance.startPresenceHeartbeat();
    unawaited(AppSessionTrackerService.instance.init());
    DeepLinkService.instance.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppSessionTrackerService.instance.dispose();
    UserPresenceService.instance.stopPresenceHeartbeat();
    DeepLinkService.instance.dispose();
    AuthSessionManager.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.isAppInForeground = true;
      SystemUiHelper.enableFullScreen();
      unawaited(AuthSessionManager.instance.ensureValidSession());
      unawaited(AuthHelper.syncCurrentUserFcmTokenIfLoggedIn());
      NotificationService().startRealtimeNotifications();
      ZevRtcService.instance.startIncomingCallListener();
      UserPresenceService.instance.updatePresence(isOnline: true);
      AppSessionTrackerService.instance.onAppResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      NotificationService.isAppInForeground = false;
      UserPresenceService.instance.updatePresence(isOnline: false);
      if (state != AppLifecycleState.inactive) {
        AppSessionTrackerService.instance.onAppPaused();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'ZEV',
      debugShowCheckedModeBanner: false,
      theme: ZevColors.lightTheme,
      locale: const Locale('en', 'US'),
      supportedLocales: const [Locale('en', 'US')],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: widget.home,
    );
  }
}
