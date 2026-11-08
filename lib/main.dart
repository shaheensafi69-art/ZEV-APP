import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/services/admob_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/google_auth_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/user_presence_service.dart';
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

  // 2. Load environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Dotenv initialization warning: $e');
  }

  // 3. Initialize Supabase with retry logic
  final supabaseUrl = dotenv.env['NEXT_PUBLIC_SUPABASE_URL'] ??
      'https://zjwmioalrhkyfbzhdnnw.supabase.co';
  final supabaseAnonKey = dotenv.env['NEXT_PUBLIC_SUPABASE_ANON_KEY'] ??
      'sb_publishable_mhRdQoBdG-Ha0_nQ4dHIVw_MrXwmR5z';

  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        // ignore: deprecated_member_use
        anonKey: supabaseAnonKey,
      );
      break;
    } catch (e) {
      debugPrint('Supabase initialization attempt $attempt failed: $e');
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  // 4. Initialize Push Notifications & Firebase
  unawaited(NotificationService().initPushNotifications());

  // 5. Initialize Google Mobile Ads (Native in-stream Ad Units)
  unawaited(AdmobService.instance.init());

  // 6. Initial home is the flagship cinematic animated ZEV splash screen
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
    DeepLinkService.instance.init();
    GoogleAuthService.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UserPresenceService.instance.stopPresenceHeartbeat();
    DeepLinkService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemUiHelper.enableFullScreen();
      UserPresenceService.instance.updatePresence(isOnline: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      UserPresenceService.instance.updatePresence(isOnline: false);
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
