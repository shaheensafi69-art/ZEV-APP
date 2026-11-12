import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

class ZevSponsoredAd {
  final String campaignId;
  final String creativeId;
  final String businessName;
  final String placement;
  final String pricingModel;
  final double bidAmount;
  final String title;
  final String body;
  final String mediaUrl;
  final String mediaType;
  final String ctaLabel;
  final String destinationUrl;

  const ZevSponsoredAd({
    required this.campaignId,
    required this.creativeId,
    required this.businessName,
    required this.placement,
    required this.pricingModel,
    required this.bidAmount,
    required this.title,
    required this.body,
    required this.mediaUrl,
    required this.mediaType,
    required this.ctaLabel,
    required this.destinationUrl,
  });

  bool get isVideo =>
      mediaType.toLowerCase() == 'video' ||
      mediaUrl.toLowerCase().contains('.mp4') ||
      mediaUrl.toLowerCase().contains('.mov') ||
      mediaUrl.toLowerCase().contains('.webm');

  factory ZevSponsoredAd.fromJson(Map<String, dynamic> json) {
    return ZevSponsoredAd(
      campaignId: (json['campaign_id'] ?? json['campaignId'] ?? '').toString(),
      creativeId: (json['creative_id'] ?? json['creativeId'] ?? '').toString(),
      businessName:
          (json['business_name'] ?? json['businessName'] ?? 'Sponsored Partner')
              .toString(),
      placement: (json['placement'] ?? 'feed').toString().toLowerCase(),
      pricingModel: (json['pricing_model'] ?? 'CPM').toString().toUpperCase(),
      bidAmount: (json['bid_amount'] as num?)?.toDouble() ?? 0.0,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      mediaUrl: (json['media_url'] ?? json['mediaUrl'] ?? '').toString(),
      mediaType: (json['media_type'] ?? json['mediaType'] ?? 'image')
          .toString()
          .toLowerCase(),
      ctaLabel: (json['cta_label'] ?? json['ctaLabel'] ?? 'Learn More')
          .toString(),
      destinationUrl:
          (json['destination_url'] ?? json['destinationUrl'] ?? '').toString(),
    );
  }
}

class ZevAdvertiserProfile {
  final String id;
  final String userId;
  final String businessName;
  final String? websiteUrl;
  final String? contactEmail;
  final String status;
  final double balance;
  final String currency;

  const ZevAdvertiserProfile({
    required this.id,
    required this.userId,
    required this.businessName,
    this.websiteUrl,
    this.contactEmail,
    required this.status,
    required this.balance,
    required this.currency,
  });

  factory ZevAdvertiserProfile.fromJson(Map<String, dynamic> json) {
    return ZevAdvertiserProfile(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      businessName: (json['business_name'] ?? '').toString(),
      websiteUrl: json['website_url']?.toString(),
      contactEmail: json['contact_email']?.toString(),
      status: (json['status'] ?? 'pending').toString().toLowerCase(),
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] ?? 'USD').toString(),
    );
  }
}

class ZevAdCampaign {
  final String id;
  final String name;
  final String objective;
  final String placement;
  final String pricingModel;
  final double bidAmount;
  final double dailyBudget;
  final double totalBudget;
  final double spentAmount;
  final double spentToday;
  final int dailyFrequencyCap;
  final int minCooldownSeconds;
  final int impressionsCount;
  final int clicksCount;
  final int conversionsCount;
  final String status;
  final String? rejectionReason;
  final String? creativeTitle;
  final String? creativeBody;
  final String? creativeMediaUrl;
  final String? creativeMediaType;
  final String? creativeCtaLabel;
  final String? creativeDestinationUrl;
  final String createdAt;

  const ZevAdCampaign({
    required this.id,
    required this.name,
    required this.objective,
    required this.placement,
    required this.pricingModel,
    required this.bidAmount,
    required this.dailyBudget,
    required this.totalBudget,
    required this.spentAmount,
    required this.spentToday,
    required this.dailyFrequencyCap,
    required this.minCooldownSeconds,
    required this.impressionsCount,
    required this.clicksCount,
    required this.conversionsCount,
    required this.status,
    this.rejectionReason,
    this.creativeTitle,
    this.creativeBody,
    this.creativeMediaUrl,
    this.creativeMediaType,
    this.creativeCtaLabel,
    this.creativeDestinationUrl,
    required this.createdAt,
  });

  double get ctrPercent =>
      impressionsCount > 0 ? (clicksCount / impressionsCount) * 100.0 : 0.0;

  factory ZevAdCampaign.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> creative = {};
    final rawCreatives = json['creatives'] ?? json['ad_creatives'];
    if (rawCreatives is List && rawCreatives.isNotEmpty && rawCreatives.first is Map) {
      creative = Map<String, dynamic>.from(rawCreatives.first as Map);
    } else if (json['creative'] is Map) {
      creative = Map<String, dynamic>.from(json['creative'] as Map);
    }

    return ZevAdCampaign(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      objective: (json['objective'] ?? 'awareness').toString(),
      placement: (json['placement'] ?? 'feed').toString(),
      pricingModel: (json['pricing_model'] ?? 'CPM').toString().toUpperCase(),
      bidAmount: (json['bid_amount'] as num?)?.toDouble() ?? 0.0,
      dailyBudget: (json['daily_budget'] as num?)?.toDouble() ?? 0.0,
      totalBudget: (json['total_budget'] as num?)?.toDouble() ?? 0.0,
      spentAmount: (json['spent_amount'] as num?)?.toDouble() ?? 0.0,
      spentToday: (json['spent_today'] as num?)?.toDouble() ?? 0.0,
      dailyFrequencyCap: (json['daily_frequency_cap'] as num?)?.toInt() ?? 3,
      minCooldownSeconds:
          (json['min_cooldown_seconds'] as num?)?.toInt() ?? 300,
      impressionsCount: (json['impressions_count'] as num?)?.toInt() ?? 0,
      clicksCount: (json['clicks_count'] as num?)?.toInt() ?? 0,
      conversionsCount: (json['conversions_count'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? 'pending_review').toString().toLowerCase(),
      rejectionReason: json['rejection_reason']?.toString(),
      creativeTitle: (json['creative_title'] ?? creative['title'])?.toString(),
      creativeBody: (json['creative_body'] ?? creative['body'])?.toString(),
      creativeMediaUrl:
          (json['creative_media_url'] ?? creative['media_url'])?.toString(),
      creativeMediaType:
          (json['creative_media_type'] ?? creative['media_type'])?.toString(),
      creativeCtaLabel:
          (json['creative_cta_label'] ?? creative['cta_label'])?.toString(),
      creativeDestinationUrl:
          (json['creative_destination_url'] ?? creative['destination_url'])
              ?.toString(),
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}

class ZevAdInvoice {
  final String id;
  final String invoiceNumber;
  final String? campaignId;
  final double amount;
  final String currency;
  final String status;
  final String createdAt;

  const ZevAdInvoice({
    required this.id,
    required this.invoiceNumber,
    this.campaignId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
  });

  factory ZevAdInvoice.fromJson(Map<String, dynamic> json) {
    return ZevAdInvoice(
      id: (json['id'] ?? '').toString(),
      invoiceNumber: (json['invoice_number'] ?? '').toString(),
      campaignId: json['campaign_id']?.toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] ?? 'USD').toString(),
      status: (json['status'] ?? 'issued').toString().toLowerCase(),
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}

class ZevAdsDashboardData {
  final ZevAdvertiserProfile? advertiser;
  final List<ZevAdCampaign> campaigns;
  final List<ZevAdInvoice> invoices;

  const ZevAdsDashboardData({
    required this.advertiser,
    required this.campaigns,
    required this.invoices,
  });
}

/// Client service for ZEV Internal Ad Network (`/api/v1/ads/*`) with session
/// slot caching, idempotent impression deduplication, and Ads Manager operations.
class ZevAdsService {
  ZevAdsService._();
  static final ZevAdsService instance = ZevAdsService._();

  final Map<String, ZevSponsoredAd?> _slotAdCache = <String, ZevSponsoredAd?>{};
  final Set<String> _recordedImpressionKeys = <String>{};

  static String buildImpressionIdempotencyKey({
    required String slotKey,
    required String campaignId,
  }) =>
      'imp_${slotKey}_$campaignId';

  static String buildClickIdempotencyKey({
    required String slotKey,
    required String campaignId,
    required int timestampMs,
  }) =>
      'click_${slotKey}_${campaignId}_$timestampMs';

  void clearSlotCache() {
    _slotAdCache.clear();
  }

  /// Marks an impression key locally as recorded; returns `true` only the first
  /// time in the current session so widget rebuilds cannot spam `/api/v1/ads/track`.
  bool claimSessionImpressionKey(String idempotencyKey) {
    return _recordedImpressionKeys.add(idempotencyKey);
  }

  /// Fetches an eligible ZEV Sponsored Ad for a placement + stable [slotKey].
  Future<ZevSponsoredAd?> fetchEligibleAd({
    required String placement,
    required String slotKey,
    String? country,
    String? interest,
    bool forceRefresh = false,
  }) async {
    final normalizedSlot = '$placement:$slotKey';
    if (!forceRefresh && _slotAdCache.containsKey(normalizedSlot)) {
      return _slotAdCache[normalizedSlot];
    }

    try {
      final res = await ApiClient.instance.get(
        '/api/v1/ads/serve',
        queryParameters: {
          'placement': placement,
          if (country != null && country.isNotEmpty) 'country': country,
          if (interest != null && interest.isNotEmpty) 'interest': interest,
        },
        requireAuth: false,
        attachOptionalAuth: true,
      );

      final rawAd = res['ad'];
      if (rawAd is Map) {
        final ad = ZevSponsoredAd.fromJson(Map<String, dynamic>.from(rawAd));
        if (ad.campaignId.isNotEmpty) {
          _slotAdCache[normalizedSlot] = ad;
          return ad;
        }
      }
      _slotAdCache[normalizedSlot] = null;
      return null;
    } catch (e) {
      debugPrint('[ZevAdsService] fetchEligibleAd notice ($placement): $e');
      return null;
    }
  }

  /// Records one impression per (slotKey, campaignId) per session.
  Future<void> recordImpressionOnce({
    required String slotKey,
    required ZevSponsoredAd ad,
  }) async {
    if (ad.campaignId.isEmpty) return;
    final key = buildImpressionIdempotencyKey(
      slotKey: slotKey,
      campaignId: ad.campaignId,
    );
    if (!claimSessionImpressionKey(key)) return;

    try {
      await ApiClient.instance.post(
        '/api/v1/ads/track',
        data: {
          'eventType': 'impression',
          'campaignId': ad.campaignId,
          if (ad.creativeId.isNotEmpty) 'creativeId': ad.creativeId,
          'placement': ad.placement,
          'idempotencyKey': key,
        },
        requireAuth: false,
        attachOptionalAuth: true,
      );
    } catch (e) {
      debugPrint('[ZevAdsService] impression track notice: $e');
    }
  }

  /// Records click and opens safe external http(s) URL.
  Future<void> openAdDestination({
    required String slotKey,
    required ZevSponsoredAd ad,
  }) async {
    final clickKey = buildClickIdempotencyKey(
      slotKey: slotKey,
      campaignId: ad.campaignId,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    if (ad.campaignId.isNotEmpty) {
      unawaited(
        ApiClient.instance
            .post(
              '/api/v1/ads/track',
              data: {
                'eventType': 'click',
                'campaignId': ad.campaignId,
                if (ad.creativeId.isNotEmpty) 'creativeId': ad.creativeId,
                'placement': ad.placement,
                'idempotencyKey': clickKey,
              },
              requireAuth: false,
              attachOptionalAuth: true,
            )
            .catchError((_) => <String, dynamic>{}),
      );
    }

    final uri = Uri.tryParse(ad.destinationUrl.trim());
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<ZevAdsDashboardData> fetchAdvertiserDashboard() async {
    final res = await ApiClient.instance.get('/api/v1/ads/campaigns');

    ZevAdvertiserProfile? adv;
    if (res['advertiser'] is Map) {
      adv = ZevAdvertiserProfile.fromJson(
        Map<String, dynamic>.from(res['advertiser'] as Map),
      );
    }

    final rawCampaigns = (res['campaigns'] as List?) ?? const [];
    final campaigns = rawCampaigns
        .whereType<Map>()
        .map((m) => ZevAdCampaign.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    final rawInvoices = (res['invoices'] as List?) ?? const [];
    final invoices = rawInvoices
        .whereType<Map>()
        .map((m) => ZevAdInvoice.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return ZevAdsDashboardData(
      advertiser: adv,
      campaigns: campaigns,
      invoices: invoices,
    );
  }

  Future<ZevAdvertiserProfile?> registerOrUpdateAdvertiser({
    required String businessName,
    String? website,
    String? contactEmail,
  }) async {
    final res = await ApiClient.instance.post(
      '/api/v1/ads/campaigns',
      data: {
        'action': 'register_advertiser',
        'businessName': businessName.trim(),
        if (website != null && website.trim().isNotEmpty) 'website': website.trim(),
        if (contactEmail != null && contactEmail.trim().isNotEmpty)
          'contactEmail': contactEmail.trim(),
      },
    );

    if (res['advertiser'] is Map) {
      return ZevAdvertiserProfile.fromJson(
        Map<String, dynamic>.from(res['advertiser'] as Map),
      );
    }
    return null;
  }

  Future<Map<String, dynamic>> createCampaign({
    required String name,
    required String objective,
    required String placement,
    required String pricingModel,
    required double bidAmount,
    required double dailyBudget,
    required double totalBudget,
    required String title,
    required String body,
    String? mediaUrl,
    String mediaType = 'image',
    String ctaLabel = 'Learn More',
    required String destinationUrl,
    List<String> countries = const [],
    List<String> languages = const [],
    List<String> interests = const [],
    int minAge = 13,
    int maxAge = 99,
    String gender = 'all',
    int dailyFrequencyCap = 3,
    int minCooldownSeconds = 300,
    DateTime? endsAt,
  }) async {
    return ApiClient.instance.post(
      '/api/v1/ads/campaigns',
      data: {
        'action': 'create_campaign',
        'name': name.trim(),
        'objective': objective,
        'placement': placement,
        'pricingModel': pricingModel,
        'bidAmount': bidAmount,
        'dailyBudget': dailyBudget,
        'totalBudget': totalBudget,
        'title': title.trim(),
        'body': body.trim(),
        if (mediaUrl != null && mediaUrl.trim().isNotEmpty) 'mediaUrl': mediaUrl.trim(),
        'mediaType': mediaType,
        'ctaLabel': ctaLabel.trim().isEmpty ? 'Learn More' : ctaLabel.trim(),
        'destinationUrl': destinationUrl.trim(),
        'countries': countries,
        'languages': languages,
        'interests': interests,
        'minAge': minAge,
        'maxAge': maxAge,
        'gender': gender,
        'dailyFrequencyCap': dailyFrequencyCap,
        'minCooldownSeconds': minCooldownSeconds,
        if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> toggleCampaignPause({
    required String campaignId,
    required bool pause,
  }) async {
    await ApiClient.instance.patch(
      '/api/v1/ads/campaigns',
      data: {
        'campaignId': campaignId,
        'pause': pause,
      },
    );
  }

  Future<Map<String, dynamic>> generateInvoice({String? campaignId}) async {
    return ApiClient.instance.post(
      '/api/v1/ads/campaigns',
      data: {
        'action': 'generate_invoice',
        if (campaignId != null && campaignId.isNotEmpty) 'campaignId': campaignId,
      },
    );
  }
}
