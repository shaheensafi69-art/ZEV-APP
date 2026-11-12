import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zev_app/core/services/auth_session_manager.dart';
import 'package:zev_app/core/theme/zev_theme.dart';
import 'package:zev_app/core/utils/rich_text_helper.dart';
import 'package:zev_app/core/widgets/zev_skeleton.dart';
import 'package:zev_app/features/auth/screens/account_standing_screen.dart';
import 'package:zev_app/features/feed/models/feed_post_item.dart';
import 'package:zev_app/features/feed/widgets/feed_post_card.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-publishable-key-placeholder',
      );
    }
  });

  testWidgets('ZevRichText renders Light Clearmorphic body & handles hashtag tap', (
    WidgetTester tester,
  ) async {
    String? tappedTag;
    await tester.pumpWidget(
      MaterialApp(
        theme: ZevColors.lightTheme,
        home: Scaffold(
          backgroundColor: ZevColors.white,
          body: ZevRichText(
            text: 'Check #FlutterDev with @zev_team at https://zevapp.com',
            style: const TextStyle(fontSize: 14, color: ZevColors.deepNavy),
            onHashtagTap: (tag) => tappedTag = tag,
          ),
        ),
      ),
    );

    final textWidget = tester.widget<Text>(find.byType(Text));
    final plain = textWidget.textSpan!.toPlainText();
    expect(plain, contains('#FlutterDev'));
    expect(plain, contains('@zev_team'));
    expect(plain, contains('https://zevapp.com'));

    // Trigger #FlutterDev recognizer callback
    final rootSpan = textWidget.textSpan as TextSpan;
    final tagSpan = rootSpan.children!
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == '#FlutterDev');
    expect(tagSpan.recognizer, isA<TapGestureRecognizer>());
    (tagSpan.recognizer as TapGestureRecognizer).onTap?.call();
    expect(tappedTag, 'FlutterDev');
  });

  testWidgets('ZevFeedCardSkeleton renders Light Clearmorphic white surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ZevColors.lightTheme,
        home: const Scaffold(
          backgroundColor: ZevColors.softSurface,
          body: SingleChildScrollView(child: ZevFeedCardSkeleton()),
        ),
      ),
    );

    expect(find.byType(ZevFeedCardSkeleton), findsOneWidget);
    expect(find.byType(ZevSkeleton), findsWidgets);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('AccountStandingScreen renders Light Clearmorphic suspension card and actions', (
    WidgetTester tester,
  ) async {
    final standing = AccountAccessResult(
      status: AccountStandingStatus.banned,
      reason: 'Automated spam policy violation',
      userId: 'user-123',
      bannedUntil: DateTime.utc(2026, 12, 1, 10, 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ZevColors.lightTheme,
        home: AccountStandingScreen(standing: standing),
      ),
    );

    expect(find.text('Account Suspended'), findsOneWidget);
    expect(find.text('Automated spam policy violation'), findsOneWidget);
    expect(find.text('Submit / View Appeal'), findsOneWidget);
    expect(find.text('Re-check Account Status'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, ZevColors.softSurface);
  });

  testWidgets('FeedPostCard renders collaborator, multi-slide 1/2 badge & tagged pill in Light Clearmorphism', (
    WidgetTester tester,
  ) async {
    final post = FeedPostItem(
      id: 'post-widget-1',
      authorId: 'author-1',
      authorUsername: 'main_creator',
      authorFullName: 'Main Creator',
      authorAvatar: '',
      isVerified: true,
      title: '[Design] Clearmorphism UI',
      content: 'Multi-photo carousel test #Design',
      imageUrl: '/nonexistent/slide1.png',
      createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      likesCount: 12,
      commentsCount: 3,
      repostsCount: 1,
      location: 'Kabul',
      mediaItems: const [
        FeedPostMediaItem(
          id: 'm1',
          mediaType: 'image',
          mediaUrl: '/nonexistent/slide1.png',
          sortOrder: 0,
        ),
        FeedPostMediaItem(
          id: 'm2',
          mediaType: 'image',
          mediaUrl: '/nonexistent/slide2.png',
          sortOrder: 1,
        ),
      ],
      collaborators: const [
        FeedPostUserTag(id: 'u2', username: 'partner_dev'),
        FeedPostUserTag(id: 'u3', username: 'designer_pro'),
      ],
      taggedUsers: const [
        FeedPostUserTag(id: 'u4', username: 'tagged_one'),
        FeedPostUserTag(id: 'u5', username: 'tagged_two'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ZevColors.lightTheme,
        home: Scaffold(
          backgroundColor: ZevColors.softSurface,
          body: SingleChildScrollView(child: FeedPostCard(post: post)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('main_creator'), findsOneWidget);
    expect(find.text('• with @partner_dev +1'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('2 Tagged'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Kabul'), findsOneWidget);
  });
}
