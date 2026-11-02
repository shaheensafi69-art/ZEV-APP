import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/zev_theme.dart';
import '../models/feed_post_item.dart';

/// Next-Generation Instagram Stories Tray for ZEV.
/// Features vibrant Electric Cyan (#00D4FF) gradient rings and smooth horizontal scrolling.
class FeedStoriesTray extends StatelessWidget {
  final String myAvatarUrl;
  final List<ActiveFriendStory> stories;
  final VoidCallback? onAddStory;
  final ValueChanged<ActiveFriendStory>? onStoryTap;

  const FeedStoriesTray({
    super.key,
    required this.myAvatarUrl,
    required this.stories,
    this.onAddStory,
    this.onStoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      decoration: const BoxDecoration(
        color: ZevColors.white,
        border: Border(
          bottom: BorderSide(
            color: ZevColors.border,
            width: 0.8,
          ),
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (onAddStory != null) {
          onAddStory!();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Create Story will open camera/media picker."),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZevColors.softSurface,
                    border: Border.all(
                      color: ZevColors.border,
                      width: 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: myAvatarUrl.isNotEmpty
                        ? Image.network(
                            myAvatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.person_rounded,
                              size: 32,
                              color: ZevColors.textMuted,
                            ),
                          )
                        : const Icon(
                            Icons.person_rounded,
                            size: 32,
                            color: ZevColors.textMuted,
                          ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: ZevColors.primaryBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add,
                        size: 13,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              "Your story",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ZevColors.deepNavy,
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
            Container(
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [ZevColors.primaryBlue, ZevColors.secondaryBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(1.5),
                child: ClipOval(
                  child: story.avatarUrl.isNotEmpty
                      ? Image.network(
                          story.avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.person_rounded,
                            size: 30,
                            color: ZevColors.textMuted,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          size: 30,
                          color: ZevColors.textMuted,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              story.username,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ZevColors.deepNavy,
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
