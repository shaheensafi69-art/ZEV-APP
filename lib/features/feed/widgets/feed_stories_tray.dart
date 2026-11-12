import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../models/feed_post_item.dart';

/// Next-Generation Instagram Stories Tray for ZEV.
/// Features vibrant Electric Cyan (#00D4FF) and Close Friends emerald rings
/// plus muted seen rings and Light Clearmorphism styling.
class FeedStoriesTray extends StatelessWidget {
  final String myAvatarUrl;
  final ActiveFriendStory? myActiveStory;
  final List<ActiveFriendStory> stories;
  final VoidCallback? onAddStory;
  final ValueChanged<ActiveFriendStory>? onStoryTap;

  const FeedStoriesTray({
    super.key,
    required this.myAvatarUrl,
    this.myActiveStory,
    required this.stories,
    this.onAddStory,
    this.onStoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      height: 112,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: stories.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildMyStoryItem(context);
          }
          final story = stories[index - 1];
          return _buildFriendStoryItem(context, story);
        },
      ),
    );
  }

  Widget _buildMyStoryItem(BuildContext context) {
    final activeStory = myActiveStory;
    final hasActive = activeStory != null && activeStory.storiesCount > 0;

    void handleAddStory() {
      HapticFeedback.lightImpact();
      if (onAddStory != null) {
        onAddStory!();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Create Story will open camera/media picker.",
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    Widget avatarInner = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF1F5F9),
        border: Border.all(
          color: Colors.white,
          width: 2.0,
        ),
        boxShadow: hasActive
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
                const BoxShadow(
                  color: Colors.white,
                  blurRadius: 6,
                  offset: Offset(0, -2),
                ),
              ],
      ),
      child: myAvatarUrl.isNotEmpty
          ? ZevCachedImage.avatar(
              imageUrl: myAvatarUrl,
              size: 60,
            )
          : const Center(
              child: Icon(
                Icons.person_rounded,
                size: 32,
                color: ZevColors.textMuted,
              ),
            ),
    );

    if (hasActive) {
      final isCloseFriend = activeStory.hasCloseFriendStory;
      final isUnseen = activeStory.hasUnseen;
      avatarInner = Container(
        width: 60,
        height: 60,
        padding: EdgeInsets.all(isUnseen ? 2.4 : 1.8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isUnseen
              ? LinearGradient(
                  colors: isCloseFriend
                      ? const [Color(0xFF10B981), Color(0xFF00D4FF)]
                      : const [
                          Color(0xFF00D4FF),
                          Color(0xFF536DFE),
                          Color(0xFFA60F93),
                        ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                )
              : null,
          color: isUnseen ? null : const Color(0xFFCBD5E1),
        ),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(1.5),
          child: avatarInner,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (hasActive && onStoryTap != null) {
          onStoryTap!(activeStory);
        } else {
          handleAddStory();
        }
      },
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                avatarInner,
                Positioned(
                  bottom: -1,
                  right: -1,
                  child: GestureDetector(
                    onTap: handleAddStory,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4FF), Color(0xFF0095F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.45),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hasActive ? "Your story" : "Your story",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: hasActive ? FontWeight.w800 : FontWeight.w700,
                color: hasActive ? ZevColors.deepNavy : ZevColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendStoryItem(BuildContext context, ActiveFriendStory story) {
    final bool isUnseen = story.hasUnseen;
    final bool isCloseFriend = story.hasCloseFriendStory;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (onStoryTap != null) {
          onStoryTap!(story);
        }
      },
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: EdgeInsets.all(isUnseen ? 2.5 : 1.8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isUnseen
                        ? LinearGradient(
                            colors: isCloseFriend
                                ? const [Color(0xFF10B981), Color(0xFF00D4FF)]
                                : const [
                                    Color(0xFFFBAA47),
                                    Color(0xFFD91A46),
                                    Color(0xFFA60F93),
                                  ],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          )
                        : null,
                    color: isUnseen ? null : const Color(0xFFCBD5E1),
                    boxShadow: isUnseen
                        ? [
                            BoxShadow(
                              color: (isCloseFriend
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFD91A46))
                                  .withValues(alpha: 0.24),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: story.avatarUrl.isNotEmpty
                        ? ZevCachedImage.avatar(
                            imageUrl: story.avatarUrl,
                            size: 58,
                          )
                        : const Center(
                            child: Icon(
                              Icons.person_rounded,
                              size: 30,
                              color: ZevColors.textMuted,
                            ),
                          ),
                  ),
                ),
                if (isCloseFriend)
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.star_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              story.username,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isUnseen ? FontWeight.w700 : FontWeight.w600,
                color: isUnseen ? ZevColors.deepNavy : ZevColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
