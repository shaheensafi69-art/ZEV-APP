import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zev_app/core/services/feed_algorithm_service.dart';
import 'package:zev_app/core/services/zev_ads_service.dart';
import 'package:zev_app/core/utils/text_direction_helper.dart';
import 'package:zev_app/core/widgets/zev_video_thumbnail.dart';
import 'package:zev_app/features/feed/models/feed_post_item.dart';
import 'package:zev_app/features/reels/models/reel_item.dart';

void main() {
  group('TextDirectionHelper', () {
    test('detects Persian/Dari/Arabic text as RTL', () {
      expect(TextDirectionHelper.isRtl('سلام دوستان عزیز'), isTrue);
      expect(
        TextDirectionHelper.getDirection('پلتفرم اجتماعی ZEV'),
        TextDirection.rtl,
      );
      expect(
        TextDirectionHelper.getTextAlign('تست راست به چپ'),
        TextAlign.right,
      );
    });

    test('detects English text as LTR and handles empty input', () {
      expect(TextDirectionHelper.isRtl('Hello ZEV World'), isFalse);
      expect(
        TextDirectionHelper.getDirection('Hello ZEV World'),
        TextDirection.ltr,
      );
      expect(
        TextDirectionHelper.getTextAlign('Hello ZEV World'),
        TextAlign.left,
      );
      expect(TextDirectionHelper.isRtl(null), isFalse);
      expect(TextDirectionHelper.isRtl('   '), isFalse);
    });
  });

  group('FeedPostItem & ReelItem models', () {
    test('FeedPostItem parses media carousel sorted by sort_order, collabs, tags, draft & scheduled fields', () {
      final item = FeedPostItem.fromRpcMap({
        'id': 'post-1',
        'student_id': 'user-a',
        'author_username': 'creator_one',
        'author_first_name': 'Safi',
        'author_last_name': 'Dev',
        'author_avatar_url': '',
        'author_is_verified': true,
        'title': 'Launch Day',
        'content': 'Hello #ZEV @friend https://zevapp.com',
        'created_at': '2026-11-12T08:00:00Z',
        'likes_count': 42,
        'is_liked_by_me': true,
        'comments_count': 7,
        'reposts_count': 3,
        'location': 'Kabul',
        'is_draft': true,
        'scheduled_at': '2026-11-20T10:00:00Z',
        'media_items': [
          {
            'id': 'm2',
            'media_type': 'image',
            'media_url': '/tmp/slide2.png',
            'sort_order': 1,
          },
          {
            'id': 'm1',
            'media_type': 'image',
            'media_url': '/tmp/slide1.png',
            'sort_order': 0,
          },
        ],
        'collaborator_profiles': [
          {
            'id': 'u2',
            'username': 'collab_user',
            'first_name': 'Collab',
            'last_name': 'One',
            'is_verified': true,
          },
        ],
        'tagged_profiles': [
          {
            'id': 'u3',
            'username': 'tagged_a',
            'first_name': 'Tagged',
            'last_name': 'A',
          },
          {
            'id': 'u4',
            'username': 'tagged_b',
            'first_name': 'Tagged',
            'last_name': 'B',
          },
        ],
      });

      expect(item.id, 'post-1');
      expect(item.authorFullName, 'Safi Dev');
      expect(item.effectiveMediaUrls, ['/tmp/slide1.png', '/tmp/slide2.png']);
      expect(item.imageUrl, '/tmp/slide1.png');
      expect(item.collaborators.length, 1);
      expect(item.collaborators.first.username, 'collab_user');
      expect(item.taggedUsers.length, 2);
      expect(item.location, 'Kabul');
      expect(item.isDraft, isTrue);
      expect(item.scheduledAt, isNotNull);

      final updated = item.copyWith(isDraft: false, likesCount: 43);
      expect(updated.isDraft, isFalse);
      expect(updated.likesCount, 43);
      expect(updated.collaborators.length, 1);
    });

    test('FeedPostItem falls back to legacy imageUrl when media_items is empty', () {
      final item = FeedPostItem(
        id: 'p-legacy',
        authorId: 'u1',
        authorUsername: 'alice',
        authorFullName: 'Alice',
        authorAvatar: '',
        title: '',
        content: 'Legacy image',
        imageUrl: '/tmp/legacy.jpg',
        createdAt: DateTime.utc(2026, 11, 12),
      );
      expect(item.effectiveMediaUrls, ['/tmp/legacy.jpg']);
    });

    test('ReelItem parses RPC map and copyWith works cleanly', () {
      final reel = ReelItem.fromRpcMap({
        'id': 'reel-1',
        'user_id': 'u-9',
        'author_username': 'filmmaker',
        'author_first_name': 'Aria',
        'author_last_name': 'Khan',
        'author_is_verified': true,
        'video_url': 'https://cdn.zevapp.com/reels/demo.mp4',
        'title': 'Behind the scenes',
        'duration_seconds': 24,
        'views_count': 1200,
        'likes_count': 80,
        'comments_count': 9,
        'created_at': '2026-11-12T06:00:00Z',
      });

      expect(reel.id, 'reel-1');
      expect(reel.authorFullName, 'Aria Khan');
      expect(reel.durationSeconds, 24);
      final liked = reel.copyWith(isLikedByMe: true, likesCount: 81);
      expect(liked.isLikedByMe, isTrue);
      expect(liked.likesCount, 81);
    });
  });

  group('FeedAlgorithmService', () {
    setUp(() {
      FeedAlgorithmService.instance.resetSessionSignals();
    });

    FeedPostItem makePost(
      String id,
      String authorId, {
      int likes = 0,
      int comments = 0,
      bool followed = false,
      Duration age = const Duration(minutes: 10),
    }) {
      return FeedPostItem(
        id: id,
        authorId: authorId,
        authorUsername: authorId,
        authorFullName: authorId,
        authorAvatar: '',
        title: 'Post $id',
        content: 'Sample content #tech',
        imageUrl: '',
        createdAt: DateTime.now().subtract(age),
        likesCount: likes,
        commentsCount: comments,
        isAuthorFollowed: followed,
      );
    }

    test('mixPosts filters suppressed posts and suppressed authors', () {
      final algo = FeedAlgorithmService.instance;
      algo.recordNegativeFeedback(postId: 'p2');
      algo.recordNegativeFeedback(authorId: 'bad_author', suppressAuthor: true);

      final result = algo.mixPosts([
        makePost('p1', 'author1'),
        makePost('p2', 'author2'),
        makePost('p3', 'bad_author'),
        makePost('p4', 'author3'),
      ]);

      expect(result.map((e) => e.id).toList(), isNot(contains('p2')));
      expect(result.map((e) => e.id).toList(), isNot(contains('p3')));
      expect(result.length, 2);
    });

    test('mixPosts disperses consecutive posts from the same author', () {
      final algo = FeedAlgorithmService.instance;
      final posts = [
        makePost('a1', 'authorA', likes: 500, comments: 100),
        makePost('a2', 'authorA', likes: 450, comments: 90),
        makePost('b1', 'authorB', likes: 1, comments: 0),
        makePost('c1', 'authorC', likes: 1, comments: 0),
      ];

      final mixed = algo.mixPosts(posts);
      expect(mixed.length, 4);
      for (int i = 1; i < mixed.length; i++) {
        expect(mixed[i].authorId == 'authorA' && mixed[i - 1].authorId == 'authorA', isFalse);
      }
    });

    test('mixReels drops suppressed reels and ranks active engagement higher', () {
      final algo = FeedAlgorithmService.instance;
      algo.recordNegativeFeedback(reelId: 'r-bad');

      final now = DateTime.now();
      final reels = [
        ReelItem(
          id: 'r-bad',
          userId: 'u1',
          authorUsername: 'u1',
          authorFullName: 'U1',
          authorAvatar: '',
          isVerified: false,
          videoUrl: 'v1.mp4',
          title: 'Bad',
          createdAt: now,
        ),
        ReelItem(
          id: 'r-top',
          userId: 'u2',
          authorUsername: 'u2',
          authorFullName: 'U2',
          authorAvatar: '',
          isVerified: true,
          videoUrl: 'v2.mp4',
          title: 'Top',
          likesCount: 250,
          commentsCount: 40,
          viewsCount: 4000,
          isAuthorFollowed: true,
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
        ReelItem(
          id: 'r-low',
          userId: 'u3',
          authorUsername: 'u3',
          authorFullName: 'U3',
          authorAvatar: '',
          isVerified: false,
          videoUrl: 'v3.mp4',
          title: 'Low',
          likesCount: 0,
          createdAt: now.subtract(const Duration(days: 5)),
        ),
      ];

      final mixed = algo.mixReels(reels);
      expect(mixed.map((r) => r.id).toList(), isNot(contains('r-bad')));
      expect(mixed.length, 2);
      expect(mixed.first.id, 'r-top');
    });
  });

  group('ZevAds models', () {
    test('ZevSponsoredAd detects video creatives and ZevAdCampaign computes CTR', () {
      final ad = ZevSponsoredAd.fromJson({
        'campaign_id': 'cmp-1',
        'creative_id': 'cr-1',
        'business_name': 'ZEV Studio',
        'placement': 'reels',
        'pricing_model': 'CPC',
        'bid_amount': 0.25,
        'title': 'Try Pro',
        'body': 'Grow faster',
        'media_url': 'https://cdn.zevapp.com/ads/promo.mp4',
        'media_type': 'video',
        'cta_label': 'Install',
        'destination_url': 'https://zevapp.com',
      });

      expect(ad.isVideo, isTrue);
      expect(ad.placement, 'reels');
      expect(ad.bidAmount, 0.25);

      final camp = ZevAdCampaign.fromJson({
        'id': 'cmp-1',
        'name': 'Spring',
        'impressions_count': 2000,
        'clicks_count': 50,
        'conversions_count': 5,
        'status': 'active',
      });
      expect(camp.ctrPercent, closeTo(2.5, 0.001));
    });
  });

  group('ZevVideoThumbnail helpers', () {
    test('detects video URLs even with query strings and fragments', () {
      expect(
        ZevVideoThumbnail.isVideoUrl(
          'https://cdn.zevapp.com/reels/clip.MP4?token=abc#t=2',
        ),
        isTrue,
      );
      expect(
        ZevVideoThumbnail.isVideoUrl('https://cdn.zevapp.com/feed/video.mov'),
        isTrue,
      );
      expect(
        ZevVideoThumbnail.isVideoUrl('https://cdn.zevapp.com/reels/thumb.jpg'),
        isFalse,
      );
      expect(
        ZevVideoThumbnail.isValidImageThumbUrl(
          'https://cdn.zevapp.com/reels/thumb.webp?v=1',
        ),
        isTrue,
      );
      expect(
        ZevVideoThumbnail.isValidImageThumbUrl(
          'https://cdn.zevapp.com/reels/clip.mp4',
        ),
        isFalse,
      );
      expect(ZevVideoThumbnail.isValidImageThumbUrl(''), isFalse);
    });

    test('FeedPostItem.effectiveMediaItems preserves video metadata and thumbnailUrl', () {
      final post = FeedPostItem.fromRpcMap({
        'id': 'post-vid-1',
        'student_id': 'u1',
        'author_username': 'creator',
        'created_at': '2026-11-12T08:00:00Z',
        'media_items': [
          {
            'id': 'vm-1',
            'media_type': 'video',
            'media_url': 'https://cdn.zevapp.com/posts/vid.mp4',
            'thumbnail_url': 'https://cdn.zevapp.com/posts/thumb.jpg',
            'duration_seconds': 18,
            'sort_order': 0,
          },
        ],
      });
      expect(post.effectiveMediaItems.length, 1);
      expect(post.effectiveMediaItems.first.mediaType, 'video');
      expect(
        post.effectiveMediaItems.first.thumbnailUrl,
        'https://cdn.zevapp.com/posts/thumb.jpg',
      );
      expect(post.effectiveMediaItems.first.durationSeconds, 18);
    });
  });
}
