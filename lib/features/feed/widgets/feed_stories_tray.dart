import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/auth_required_modal.dart';
import '../../../core/widgets/fast_cached_image.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/localization/zev_localizations.dart';
import '../screens/create_story_screen.dart';
import '../screens/story_viewer_screen.dart';
import '../screens/sponsored_story_screen.dart';

class ActiveFriendStory {
  final String userId;
  final String userName;
  final String userAvatar;
  final int storiesCount;

  const ActiveFriendStory({
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.storiesCount,
  });
}

/// Modular horizontal stories tray for Feed with full responsive scaling across
/// Phones (iPhone/Android), Tablets (iPad), and Desktop/Web (Windows/macOS/Linux).
class FeedStoriesTray extends StatelessWidget {
  final List<ActiveFriendStory> activeFriendStories;
  final VoidCallback onStoryCreated;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);

  const FeedStoriesTray({
    super.key,
    required this.activeFriendStories,
    required this.onStoryCreated,
  });

  @override
  Widget build(BuildContext context) {
    // Responsive metrics per device class
    final double trayHeight = context.responsive(
      phone: 105.0,
      tablet: 128.0,
      desktop: 138.0,
    );
    final double addCircleSize = context.responsive(
      phone: 50.0,
      tablet: 64.0,
      desktop: 70.0,
    );
    final double avatarRadius = context.responsive(
      phone: 20.0,
      tablet: 28.0,
      desktop: 31.0,
    );
    final double cameraIconSize = context.respIcon(
      phone: 22.0,
      tablet: 28.0,
      desktop: 30.0,
    );
    final double plusIconSize = context.respIcon(
      phone: 14.0,
      tablet: 18.0,
      desktop: 20.0,
    );
    final double labelFontSize = context.respFont(
      phone: 10.0,
      tablet: 12.0,
      desktop: 13.0,
    );
    final double labelWidth = context.responsive(
      phone: 58.0,
      tablet: 76.0,
      desktop: 84.0,
    );
    final double itemSpacing = context.respSpacing(
      phone: 14.0,
      tablet: 20.0,
      desktop: 24.0,
    );

    return SizedBox(
      height: trayHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: context.respSpacing(
            phone: 16.0,
            tablet: 24.0,
            desktop: 32.0,
          ),
          vertical: 8,
        ),
        children: [
          // Add story button
          GestureDetector(
            onTap: () {
              final user = Supabase.instance.client.auth.currentUser;
              if (user == null) {
                AuthRequiredModal.show(context, actionName: "create stories");
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateStoryScreen()),
              ).then((_) => onStoryCreated());
            },
            child: Padding(
              padding: EdgeInsets.only(right: itemSpacing),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: addCircleSize,
                        height: addCircleSize,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF4F6),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: primaryPink.withValues(alpha: 0.3),
                            width: context.responsive(
                              phone: 1.5,
                              tablet: 2.0,
                              desktop: 2.2,
                            ),
                          ),
                        ),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          color: primaryPink,
                          size: cameraIconSize,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: const BoxDecoration(
                            color: primaryPink,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add,
                            color: Colors.white,
                            size: plusIconSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.zevTr('addStory'),
                    style: TextStyle(
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w700,
                      color: textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Sponsored story
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SponsoredStoryScreen()),
              );
            },
            child: Padding(
              padding: EdgeInsets.only(right: itemSpacing),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: Colors.black,
                      child: Icon(
                        Icons.campaign_rounded,
                        color: Colors.amber,
                        size: cameraIconSize * 0.85,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.zevTr('sponsored'),
                    style: TextStyle(
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Active friends stories
          ...activeFriendStories.map((story) {
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoryViewerScreen(
                      userId: story.userId,
                      userName: story.userName,
                      userAvatar: story.userAvatar,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: EdgeInsets.only(right: itemSpacing),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryPink, Color(0xFFFF4081)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: FastCircleAvatar(
                        imageUrl: story.userAvatar,
                        radius: avatarRadius,
                        fallbackText: story.userName.isNotEmpty
                            ? story.userName[0]
                            : 'U',
                        backgroundColor: surfaceWhite,
                        textColor: primaryPink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: labelWidth,
                      child: Text(
                        story.userName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
