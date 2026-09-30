import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/routing/auth_gate.dart';
import 'core/services/ad_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/language_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/security_service.dart';
import 'core/services/chat_pin_service.dart';
import 'core/services/chat_block_report_service.dart';
import 'core/services/web_navigation_service.dart';
import 'core/services/url_strategy_stub.dart'
    if (dart.library.html) 'core/services/url_strategy_web.dart';
import 'core/theme/app_theme_service.dart';
import 'core/utils/system_ui_helper.dart';
import 'l10n/generated/app_localizations.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategy();
  WebNavigationService.instance.init();

  if (!kIsWeb) {
    try {
      await SystemUiHelper.init();
    } catch (e) {
      debugPrint('SystemUiHelper initialization skipped: $e');
    }
  }

  // Initialize Language
  await LanguageService.instance.init();

  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Dotenv initialization warning: $e');
  }

  // Initialize Supabase with retry logic
  bool isInitialized = false;
  final supabaseUrl =
      dotenv.env['NEXT_PUBLIC_SUPABASE_URL'] ??
      'https://enpuoypqpklndnnhndax.supabase.co';
  final supabaseAnonKey =
      dotenv.env['NEXT_PUBLIC_SUPABASE_ANON_KEY'] ??
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVucHVveXBxcGtsbmRubmhuZGF4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMwNzg1MjgsImV4cCI6MjA5ODY1NDUyOH0.slU2vYIzM0BXG_3ksR5pcfvP-cpFH7IkwIyuzF1pNCo';

  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      isInitialized = true;
      break;
    } catch (e) {
      debugPrint('Supabase initialization attempt $attempt failed: $e');
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  if (isInitialized) {
    try {
      NotificationService().initPushNotifications();
    } catch (_) {}

    try {
      DeepLinkService().init(appNavigatorKey);
    } catch (_) {}

    try {
      AdService.instance.initialize();
    } catch (_) {}

    try {
      await AppThemeService.instance.initialize();
    } catch (_) {}

    try {
      await ChatPinService.instance.init();
    } catch (_) {}

    try {
      await ChatBlockReportService.instance.init();
    } catch (_) {}
  }

  runApp(const ZevApp());
}

class ZevApp extends StatefulWidget {
  const ZevApp({super.key});

  @override
  State<ZevApp> createState() => _ZevAppState();
}

class _ZevAppState extends State<ZevApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SecurityService.instance.markSessionLocked();
    } else if (state == AppLifecycleState.resumed) {
      final context = appNavigatorKey.currentContext;
      if (context != null) {
        SecurityService.instance.verifyLockIfNeeded(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, currentLocale, _) {
        return ValueListenableBuilder<LuxuryPalette>(
          valueListenable: AppThemeService.instance.currentPaletteNotifier,
          builder: (context, luxuryPalette, _) {
            return MaterialApp(
              navigatorKey: appNavigatorKey,
              title: 'ZEV',
              debugShowCheckedModeBanner: false,
              locale: currentLocale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              localeResolutionCallback: (locale, supportedLocales) {
                for (var supported in supportedLocales) {
                  if (supported.languageCode == currentLocale.languageCode) {
                    return supported;
                  }
                }
                return supportedLocales.first;
              },
              theme: luxuryPalette.toThemeData(),
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}
