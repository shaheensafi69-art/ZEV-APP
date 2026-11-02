import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/zev_theme.dart';
import 'core/utils/system_ui_helper.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/main_navigation/screens/zev_main_layout.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      'https://enpuoypqpklndnnhndax.supabase.co';
  final supabaseAnonKey = dotenv.env['NEXT_PUBLIC_SUPABASE_ANON_KEY'] ??
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVucHVveXBxcGtsbmRubmhuZGF4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMwNzg1MjgsImV4cCI6MjA5ODY1NDUyOH0.slU2vYIzM0BXG_3ksR5pcfvP-cpFH7IkwIyuzF1pNCo';

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

  // 4. Check existing session
  final session = Supabase.instance.client.auth.currentSession;
  final initialHome =
      session != null ? const ZevMainLayout() : const WelcomeScreen();

  runApp(ZevApp(home: initialHome));
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemUiHelper.enableFullScreen();
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
