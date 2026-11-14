import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/zev_ads_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../../feed/models/feed_post_item.dart';

/// 100% Light Clearmorphic ZEV Ads Manager & Monetization Console.
/// Allows creators & businesses to onboard as advertisers, boost existing posts
/// or upload new creatives to Cloudflare R2 (`zev/ads/`), configure targeting &
/// budgets, monitor live CTR/spend telemetry, pause/resume campaigns, and generate invoices.
class AdsManagerScreen extends StatefulWidget {
  final FeedPostItem? initialBoostPost;
  final int initialTabIndex;

  const AdsManagerScreen({
    super.key,
    this.initialBoostPost,
    this.initialTabIndex = 0,
  });

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdsManagerScreen()),
    );
  }

  static Future<void> openForPost(
    BuildContext context, {
    required FeedPostItem post,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdsManagerScreen(
          initialBoostPost: post,
          initialTabIndex: 1,
        ),
      ),
    );
  }

  @override
  State<AdsManagerScreen> createState() => _AdsManagerScreenState();
}

class _AdsManagerScreenState extends State<AdsManagerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _isLoading = true;
  String? _errorMsg;
  ZevAdsDashboardData _dashboard = const ZevAdsDashboardData(
    advertiser: null,
    campaigns: [],
    invoices: [],
  );

  // Onboarding / Business profile controllers
  final _bizNameCtrl = TextEditingController();
  final _bizWebsiteCtrl = TextEditingController();
  final _bizEmailCtrl = TextEditingController();
  bool _isSavingAdvertiser = false;

  // Campaign creation form state
  final _campaignNameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _ctaLabelCtrl = TextEditingController(text: 'Learn More');
  final _destinationUrlCtrl = TextEditingController();
  final _bidCtrl = TextEditingController(text: '2.50');
  final _dailyBudgetCtrl = TextEditingController(text: '15.00');
  final _totalBudgetCtrl = TextEditingController(text: '100.00');
  final _customCountriesCtrl = TextEditingController();

  String _objective = 'awareness';
  String _placement = 'feed';
  String _pricingModel = 'CPM';
  String _gender = 'all';
  int _dailyFrequencyCap = 3;
  final int _minCooldownSeconds = 300;
  RangeValues _ageRange = const RangeValues(18, 55);
  DateTime? _endsAt;

  final Set<String> _selectedCountries = <String>{};
  final Set<String> _selectedLanguages = <String>{'en'};
  final Set<String> _selectedInterests = <String>{};

  // Creative media & boosted post state
  String? _sourcePostId;
  FeedPostItem? _sourcePostPreview;
  String? _uploadedMediaUrl;
  String _mediaType = 'image';
  bool _isUploadingMedia = false;
  double _uploadProgress = 0.0;
  String? _uploadError;
  Uint8List? _localPreviewBytes;

  bool _isSubmittingCampaign = false;
  bool _isGeneratingInvoice = false;
  String? _selectedInvoiceCampaignId;
  final Set<String> _togglingCampaignIds = <String>{};

  static const List<String> _objectives = [
    'awareness',
    'traffic',
    'engagement',
    'conversions',
  ];

  static const List<String> _placements = [
    'feed',
    'story',
    'reel',
    'explore',
    'all',
  ];

  static const List<String> _pricingModels = ['CPM', 'CPC', 'CPA'];

  static const List<String> _ctaPresets = [
    'View Post',
    'Learn More',
    'Shop Now',
    'Sign Up',
    'Download',
    'Watch More',
    'Visit Site',
  ];

  static const List<String> _countryPresets = [
    'AF',
    'AE',
    'US',
    'GB',
    'CA',
    'DE',
    'TR',
    'IR',
  ];

  static const List<String> _languagePresets = ['en', 'fa', 'ps', 'ar', 'de'];

  static const List<String> _interestPresets = [
    'Tech',
    'Business',
    'Design & Art',
    'Photography',
    'Fitness',
    'Travel',
    'Music',
    'Education',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _titleCtrl.addListener(_onPreviewFieldChanged);
    _bodyCtrl.addListener(_onPreviewFieldChanged);
    _ctaLabelCtrl.addListener(_onPreviewFieldChanged);
    if (widget.initialBoostPost != null) {
      _applyBoostPost(widget.initialBoostPost!, notify: false);
    }
    unawaited(_loadDashboard());
  }

  void _onPreviewFieldChanged() {
    if (mounted && _tabCtrl.index == 1) {
      setState(() {});
    }
  }

  void _applyBoostPost(FeedPostItem post, {bool notify = true}) {
    final media = post.effectiveMediaItems;
    final primaryMedia = media.isNotEmpty ? media.first : null;
    final headline = post.title.trim().isNotEmpty
        ? post.title.trim()
        : (post.content.trim().isNotEmpty
            ? post.content.trim().split('\n').first.trim()
            : 'Featured by @${post.authorUsername}');
    final shortHeadline =
        headline.length > 90 ? '${headline.substring(0, 87)}...' : headline;
    final copy = post.content.trim().isNotEmpty
        ? post.content.trim()
        : (post.title.trim().isNotEmpty
            ? post.title.trim()
            : 'Check out this featured post on ZEV.');

    _sourcePostId = post.id;
    _sourcePostPreview = post;
    _campaignNameCtrl.text = 'Boost: $shortHeadline';
    _titleCtrl.text = shortHeadline;
    _bodyCtrl.text = copy;
    _destinationUrlCtrl.text = 'https://www.zevapp.com/post/${post.id}';
    _ctaLabelCtrl.text = 'View Post';
    _objective = 'engagement';
    _placement = 'feed';
    _localPreviewBytes = null;
    _uploadError = null;
    if (primaryMedia != null && primaryMedia.mediaUrl.trim().isNotEmpty) {
      _uploadedMediaUrl = primaryMedia.mediaUrl.trim();
      _mediaType =
          primaryMedia.mediaType.toLowerCase() == 'video' ? 'video' : 'image';
    } else {
      _uploadedMediaUrl = null;
      _mediaType = 'image';
    }

    if (notify && mounted) {
      setState(() {});
      _showSnack('Loaded post into ZEV Ads Builder.');
    }
  }

  void _clearBoostPost() {
    setState(() {
      _sourcePostId = null;
      _sourcePostPreview = null;
    });
  }

  Future<void> _openPostPickerSheet() async {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.72,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          decoration: const BoxDecoration(
            color: ZevColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZevColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Select a Post to Advertise',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose any of your previous ZEV posts to turn into a sponsored campaign.',
                style: TextStyle(
                  fontSize: 12,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<FeedPostItem>>(
                  future: ZevAdsService.instance.fetchMyPostsForBoost(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: ZevColors.primaryBlue,
                        ),
                      );
                    }
                    final posts = snap.data ?? const <FeedPostItem>[];
                    if (posts.isEmpty) {
                      return const Center(
                        child: Text(
                          'No published posts found yet. Create a post first!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ZevColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: posts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, idx) {
                        final p = posts[idx];
                        final thumb = p.effectiveMediaItems.isNotEmpty
                            ? p.effectiveMediaItems.first
                            : null;
                        final headline = p.title.trim().isNotEmpty
                            ? p.title.trim()
                            : (p.content.trim().isNotEmpty
                                ? p.content.trim()
                                : 'Post #${p.id.substring(0, 6)}');
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            _applyBoostPost(p);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: ZevColors.softSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _sourcePostId == p.id
                                    ? ZevColors.primaryBlue
                                    : ZevColors.border,
                                width: _sourcePostId == p.id ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: thumb != null
                                        ? (thumb.mediaType == 'video'
                                            ? Container(
                                                color: ZevColors.deepNavy,
                                                child: const Icon(
                                                  Icons.play_circle_filled_rounded,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : ZevCachedImage.feedPost(
                                                imageUrl: thumb.mediaUrl,
                                                fit: BoxFit.cover,
                                              ))
                                        : Container(
                                            color: ZevColors.white,
                                            child: const Icon(
                                              Icons.article_outlined,
                                              color: ZevColors.secondaryBlue,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        headline,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: ZevColors.deepNavy,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        p.createdAt.toIso8601String().substring(0, 10),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: ZevColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.campaign_rounded,
                                  color: ZevColors.secondaryBlue,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onPreviewFieldChanged);
    _bodyCtrl.removeListener(_onPreviewFieldChanged);
    _ctaLabelCtrl.removeListener(_onPreviewFieldChanged);
    _tabCtrl.dispose();
    _bizNameCtrl.dispose();
    _bizWebsiteCtrl.dispose();
    _bizEmailCtrl.dispose();
    _campaignNameCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _ctaLabelCtrl.dispose();
    _destinationUrlCtrl.dispose();
    _bidCtrl.dispose();
    _dailyBudgetCtrl.dispose();
    _totalBudgetCtrl.dispose();
    _customCountriesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }
    try {
      final data = await ZevAdsService.instance.fetchAdvertiserDashboard();
      if (!mounted) return;
      setState(() {
        _dashboard = data;
        _isLoading = false;
        if (data.advertiser != null) {
          _bizNameCtrl.text = data.advertiser!.businessName;
          _bizWebsiteCtrl.text = data.advertiser!.websiteUrl ?? '';
          _bizEmailCtrl.text = data.advertiser!.contactEmail ?? '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMsg = e.toString();
      });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ZevColors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isError
                ? ZevColors.errorRed.withValues(alpha: 0.4)
                : ZevColors.border,
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: isError ? ZevColors.errorRed : ZevColors.successGreen,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  color: ZevColors.deepNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAdvertiserProfile({bool closeModalOnSuccess = false}) async {
    final name = _bizNameCtrl.text.trim();
    if (name.length < 2) {
      _showSnack('Please enter your business or brand name.', isError: true);
      return;
    }

    setState(() => _isSavingAdvertiser = true);
    try {
      final saved = await ZevAdsService.instance.registerOrUpdateAdvertiser(
        businessName: name,
        website: _bizWebsiteCtrl.text.trim(),
        contactEmail: _bizEmailCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _isSavingAdvertiser = false);
      if (saved != null) {
        if (closeModalOnSuccess && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        await _loadDashboard();
        _showSnack('Advertiser profile saved.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingAdvertiser = false);
      _showSnack('Could not save advertiser profile: $e', isError: true);
    }
  }

  void _openEditAdvertiserSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
          decoration: const BoxDecoration(
            color: ZevColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ZevColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Advertiser Profile',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 14),
                _buildClearInput(
                  controller: _bizNameCtrl,
                  label: 'Business or Brand Name *',
                  hint: 'e.g. ZEV Studio',
                ),
                const SizedBox(height: 12),
                _buildClearInput(
                  controller: _bizWebsiteCtrl,
                  label: 'Website URL',
                  hint: 'https://yourbrand.com',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                _buildClearInput(
                  controller: _bizEmailCtrl,
                  label: 'Billing & Contact Email',
                  hint: 'ads@yourbrand.com',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _isSavingAdvertiser
                      ? null
                      : () => _saveAdvertiserProfile(closeModalOnSuccess: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZevColors.secondaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSavingAdvertiser
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Business Details',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadCreative({required bool isVideo}) async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      picked = isVideo
          ? await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(seconds: 60),
            )
          : await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              imageQuality: 88,
            );
    } catch (e) {
      _showSnack('Could not open media library: $e', isError: true);
      return;
    }

    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final rawName = picked.name;
    final ext = rawName.contains('.')
        ? rawName.split('.').last.toLowerCase()
        : (isVideo ? 'mp4' : 'jpg');

    if (!mounted) return;
    setState(() {
      _mediaType = isVideo ? 'video' : 'image';
      _localPreviewBytes = isVideo ? null : bytes;
      _isUploadingMedia = true;
      _uploadProgress = 0.05;
      _uploadError = null;
    });

    try {
      final url = await CloudflareStorageService.instance.upload(
        bucket: 'ads',
        path: 'creative_${DateTime.now().millisecondsSinceEpoch}.$ext',
        file: kIsWeb ? null : File(picked.path),
        bytes: bytes,
        compressImage: !isVideo,
        onProgress: (p) {
          if (mounted) {
            setState(() => _uploadProgress = p.clamp(0.05, 1.0));
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _uploadedMediaUrl = url;
        _isUploadingMedia = false;
        _uploadProgress = 1.0;
      });
      _showSnack('Creative uploaded to ZEV Cloud Storage.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingMedia = false;
        _uploadError = e.toString();
      });
      _showSnack('Creative upload failed: $e', isError: true);
    }
  }

  Future<void> _submitCampaign() async {
    if (_dashboard.advertiser == null) {
      _showSnack(
        'Please register your Business Name before launching a campaign.',
        isError: true,
      );
      return;
    }
    if (_isUploadingMedia) {
      _showSnack('Please wait for your creative upload to finish.', isError: true);
      return;
    }

    final name = _campaignNameCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final dest = _destinationUrlCtrl.text.trim();

    if (name.length < 3) {
      _showSnack('Enter a campaign name (at least 3 characters).', isError: true);
      return;
    }
    if (title.length < 3) {
      _showSnack('Enter a creative headline for your ad.', isError: true);
      return;
    }
    if (body.length < 2) {
      _showSnack(
        'Enter ad copy / description (at least 2 characters).',
        isError: true,
      );
      return;
    }
    final destUri = Uri.tryParse(dest);
    if (destUri == null ||
        !(destUri.scheme == 'https' || destUri.scheme == 'http') ||
        destUri.host.isEmpty) {
      _showSnack('Enter a valid destination URL (https://...).', isError: true);
      return;
    }

    final bid = double.tryParse(_bidCtrl.text.trim()) ?? 0;
    final dailyBudget = double.tryParse(_dailyBudgetCtrl.text.trim()) ?? 0;
    final totalBudget = double.tryParse(_totalBudgetCtrl.text.trim()) ?? 0;

    if (bid <= 0 || dailyBudget <= 0 || totalBudget < dailyBudget) {
      _showSnack(
        'Check bid & budgets: Total Budget must be at least Daily Budget.',
        isError: true,
      );
      return;
    }

    final extraCountries = _customCountriesCtrl.text
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty);
    final countries = {..._selectedCountries, ...extraCountries}.toList();

    setState(() => _isSubmittingCampaign = true);
    HapticFeedback.mediumImpact();

    try {
      await ZevAdsService.instance.createCampaign(
        name: name,
        objective: _objective,
        placement: _placement,
        pricingModel: _pricingModel,
        bidAmount: bid,
        dailyBudget: dailyBudget,
        totalBudget: totalBudget,
        title: title,
        body: body,
        mediaUrl: _uploadedMediaUrl,
        mediaType: _mediaType,
        ctaLabel: _ctaLabelCtrl.text.trim().isEmpty
            ? 'Learn More'
            : _ctaLabelCtrl.text.trim(),
        destinationUrl: dest,
        countries: countries,
        languages: _selectedLanguages.toList(),
        interests: _selectedInterests.toList(),
        minAge: _ageRange.start.round(),
        maxAge: _ageRange.end.round(),
        gender: _gender,
        dailyFrequencyCap: _dailyFrequencyCap,
        minCooldownSeconds: _minCooldownSeconds,
        endsAt: _endsAt,
        sourcePostId: _sourcePostId,
      );

      if (!mounted) return;
      _campaignNameCtrl.clear();
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _destinationUrlCtrl.clear();
      setState(() {
        _sourcePostId = null;
        _sourcePostPreview = null;
        _uploadedMediaUrl = null;
        _localPreviewBytes = null;
        _isSubmittingCampaign = false;
      });
      await _loadDashboard();
      if (!mounted) return;
      _tabCtrl.animateTo(0);
      _showSnack('Campaign submitted for admin review!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingCampaign = false);
      _showSnack('Could not create campaign: $e', isError: true);
    }
  }

  Future<void> _toggleCampaignPause(ZevAdCampaign campaign) async {
    final pause = campaign.status == 'active';
    setState(() => _togglingCampaignIds.add(campaign.id));
    HapticFeedback.lightImpact();

    try {
      await ZevAdsService.instance.toggleCampaignPause(
        campaignId: campaign.id,
        pause: pause,
      );
      await _loadDashboard();
      if (mounted) {
        _showSnack(pause ? 'Campaign paused.' : 'Campaign resumed.');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Could not update campaign: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _togglingCampaignIds.remove(campaign.id));
      }
    }
  }

  Future<void> _generateInvoice() async {
    if (_dashboard.advertiser == null) {
      _showSnack('Register your advertiser account first.', isError: true);
      return;
    }
    setState(() => _isGeneratingInvoice = true);
    HapticFeedback.lightImpact();

    try {
      await ZevAdsService.instance.generateInvoice(
        campaignId: _selectedInvoiceCampaignId,
      );
      await _loadDashboard();
      if (mounted) {
        setState(() => _isGeneratingInvoice = false);
        _showSnack('Invoice statement generated.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingInvoice = false);
        _showSnack('Could not generate invoice: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ZEV Ads Manager',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh_rounded, color: ZevColors.deepNavy),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 960 : double.infinity,
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 20 : 16,
                  ),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: ZevColors.white,
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(color: ZevColors.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildTabPill(0, 'Campaigns'),
                        _buildTabPill(1, 'Create Ad'),
                        _buildTabPill(2, 'Billing'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: const [
                            ZevSkeleton(width: double.infinity, height: 140),
                            SizedBox(height: 14),
                            ZevSkeleton(width: double.infinity, height: 180),
                            SizedBox(height: 14),
                            ZevSkeleton(width: double.infinity, height: 160),
                          ],
                        )
                      : _errorMsg != null
                      ? _buildErrorState()
                      : TabBarView(
                          controller: _tabCtrl,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _buildCampaignsTab(),
                            _buildCreateAdTab(),
                            _buildBillingTab(),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabPill(int index, String label) {
    final isSelected = _tabCtrl.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _tabCtrl.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isSelected ? ZevColors.brandGradient : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? Colors.white : ZevColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _clearCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 42,
                color: ZevColors.secondaryBlue,
              ),
              const SizedBox(height: 12),
              const Text(
                'Could not load Ads Manager',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMsg ?? 'Unknown network error.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadDashboard,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.secondaryBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: CAMPAIGNS & ANALYTICS
  // ===========================================================================
  Widget _buildCampaignsTab() {
    final adv = _dashboard.advertiser;
    final campaigns = _dashboard.campaigns;

    int totalImpr = 0;
    int totalClicks = 0;
    double totalSpend = 0;
    int activeCount = 0;
    for (final c in campaigns) {
      totalImpr += c.impressionsCount;
      totalClicks += c.clicksCount;
      totalSpend += c.spentAmount;
      if (c.status == 'active') activeCount++;
    }
    final avgCtr = totalImpr > 0 ? (totalClicks / totalImpr) * 100 : 0.0;

    return RefreshIndicator(
      color: ZevColors.primaryBlue,
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
        children: [
          if (adv == null)
            _buildOnboardingCard()
          else ...[
            // Clearmorphic Advertiser Status & Wallet Header
            _clearCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: ZevColors.brandGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              adv.businessName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                _statusPill(adv.status),
                                const SizedBox(width: 8),
                                if (adv.websiteUrl != null &&
                                    adv.websiteUrl!.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      adv.websiteUrl!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: ZevColors.textMuted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit Advertiser Profile',
                        onPressed: _openEditAdvertiserSheet,
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 20,
                          color: ZevColors.secondaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AVAILABLE AD CREDIT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: ZevColors.textMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '\$${adv.balance.toStringAsFixed(2)} ${adv.currency}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _tabCtrl.animateTo(1),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New Ad'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ZevColors.secondaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (adv.balance <= 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: ZevColors.warningAmber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ZevColors.warningAmber.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 17,
                            color: Color(0xFFB45309),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Add wallet credit to go live: approved campaigns automatically deliver once funded by ZEV Billing.',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildDeliveryPipelineCard(),
            const SizedBox(height: 14),

            // KPI Summary Grid
            Row(
              children: [
                Expanded(
                  child: _kpiTile(
                    label: 'Active',
                    value: '$activeCount',
                    icon: Icons.bolt_rounded,
                    color: ZevColors.successGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _kpiTile(
                    label: 'Impressions',
                    value: _compactInt(totalImpr),
                    icon: Icons.visibility_rounded,
                    color: const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _kpiTile(
                    label: 'CTR',
                    value: '${avgCtr.toStringAsFixed(1)}%',
                    icon: Icons.ads_click_rounded,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _kpiTile(
                    label: 'Spend',
                    value: '\$${totalSpend.toStringAsFixed(2)}',
                    icon: Icons.payments_outlined,
                    color: ZevColors.warningAmber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'YOUR CAMPAIGNS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ),

            if (campaigns.isEmpty)
              _clearCard(
                child: Column(
                  children: [
                    const Icon(
                      Icons.rocket_launch_outlined,
                      size: 38,
                      color: ZevColors.secondaryBlue,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No campaigns yet',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Create your first ZEV Feed, Story, Reel, or Explore campaign in under a minute.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () => _tabCtrl.animateTo(1),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('Create Campaign'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZevColors.primaryBlue,
                        foregroundColor: ZevColors.deepNavy,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...campaigns.map(_buildCampaignCard),
          ],
        ],
      ),
    );
  }

  Widget _buildOnboardingCard() {
    return _clearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: ZevColors.brandGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Become a ZEV Advertiser',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Reach creators across Feed, Stories, Reels & Explore.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildClearInput(
            controller: _bizNameCtrl,
            label: 'Business or Creator Brand Name *',
            hint: 'e.g. Ariana Crafts',
          ),
          const SizedBox(height: 12),
          _buildClearInput(
            controller: _bizWebsiteCtrl,
            label: 'Website or Store URL',
            hint: 'https://example.com',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          _buildClearInput(
            controller: _bizEmailCtrl,
            label: 'Contact & Billing Email',
            hint: 'billing@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isSavingAdvertiser ? null : _saveAdvertiserProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.secondaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isSavingAdvertiser
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Activate Advertiser Account',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryPipelineCard() {
    return _clearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: Color(0xFF0284C7),
              ),
              SizedBox(width: 6),
              Text(
                'HOW ZEV ADS DELIVERY WORKS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.textMuted,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pipelineStep('1', 'Boost / Create', 'Pick post or R2 ad'),
              const SizedBox(width: 8),
              _pipelineStep('2', 'Admin Review', 'Policy & wallet check'),
              const SizedBox(width: 8),
              _pipelineStep('3', 'Auto Delivery', 'Feed, Reels & Stories'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pipelineStep(String num, String title, String sub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ZevColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: ZevColors.brandGradient,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                num,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: ZevColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampaignCard(ZevAdCampaign c) {
    final progress = c.totalBudget > 0
        ? (c.spentAmount / c.totalBudget).clamp(0.0, 1.0)
        : 0.0;
    final canToggle = c.status == 'active' || c.status == 'paused';
    final isToggling = _togglingCampaignIds.contains(c.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _clearCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.creativeMediaUrl != null &&
                    c.creativeMediaUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: (c.creativeMediaType ?? 'image') == 'video'
                          ? Container(
                              color: ZevColors.softSurface,
                              child: const Icon(
                                Icons.play_circle_filled_rounded,
                                color: ZevColors.secondaryBlue,
                                size: 30,
                              ),
                            )
                          : ZevCachedImage.feedPost(
                              imageUrl: c.creativeMediaUrl!,
                              fit: BoxFit.cover,
                            ),
                    ),
                  )
                else
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: const Icon(
                      Icons.campaign_outlined,
                      color: ZevColors.secondaryBlue,
                      size: 28,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _statusPill(c.status),
                          if (c.isBoostedPost)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.rocket_launch_rounded,
                                    size: 11,
                                    color: Color(0xFF0284C7),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'BOOSTED POST',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0284C7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: ZevColors.softSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: ZevColors.border),
                            ),
                            child: Text(
                              '${c.placement.toUpperCase()} • ${c.pricingModel} \$${c.bidAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: ZevColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (canToggle)
                  isToggling
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Switch.adaptive(
                          value: c.status == 'active',
                          activeTrackColor: ZevColors.successGreen,
                          onChanged: (_) => _toggleCampaignPause(c),
                        ),
              ],
            ),
            if (c.creativeTitle != null && c.creativeTitle!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                c.creativeTitle!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.deepNavy,
                ),
              ),
            ],
            if (c.rejectionReason != null &&
                c.rejectionReason!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ZevColors.errorRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ZevColors.errorRed.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: ZevColors.errorRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Review Note: ${c.rejectionReason}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: ZevColors.errorRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spent \$${c.spentAmount.toStringAsFixed(2)} of \$${c.totalBudget.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.textSecondary,
                  ),
                ),
                Text(
                  'Today: \$${c.spentToday.toStringAsFixed(2)} / \$${c.dailyBudget.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ZevColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: ZevColors.softSurface,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  ZevColors.secondaryBlue,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _miniMetric('Impressions', _compactInt(c.impressionsCount)),
                _miniMetric('Clicks', _compactInt(c.clicksCount)),
                _miniMetric('CTR', '${c.ctrPercent.toStringAsFixed(2)}%'),
                _miniMetric('Freq Cap', '${c.dailyFrequencyCap}/day'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: CREATE CAMPAIGN BUILDER
  // ===========================================================================
  Widget _buildCreateAdTab() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        if (_dashboard.advertiser == null) ...[
          _buildOnboardingCard(),
          const SizedBox(height: 16),
        ],
        _buildBoostPostBannerCard(),
        const SizedBox(height: 14),
        _clearCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Campaign Setup',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 12),
              _buildClearInput(
                controller: _campaignNameCtrl,
                label: 'Campaign Name *',
                hint: 'e.g. Spring Collection Launch',
              ),
              const SizedBox(height: 12),
              const Text(
                'Objective',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _objectives
                    .map(
                      (o) => _selectChip(
                        label: o.toUpperCase(),
                        selected: _objective == o,
                        onTap: () => setState(() => _objective = o),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Placement',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _placements
                    .map(
                      (p) => _selectChip(
                        label: p.toUpperCase(),
                        selected: _placement == p,
                        onTap: () => setState(() => _placement = p),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Budget & Pricing
        _clearCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '2. Pricing, Budget & Delivery Caps',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: _pricingModels
                    .map(
                      (m) => _selectChip(
                        label: m,
                        selected: _pricingModel == m,
                        onTap: () => setState(() => _pricingModel = m),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildClearInput(
                      controller: _bidCtrl,
                      label: '$_pricingModel Bid (USD)',
                      hint: '2.50',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildClearInput(
                      controller: _dailyBudgetCtrl,
                      label: 'Daily Budget (\$)',
                      hint: '15.00',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildClearInput(
                      controller: _totalBudgetCtrl,
                      label: 'Total Budget (\$)',
                      hint: '100.00',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Frequency Cap: $_dailyFrequencyCap / user',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  Row(
                    children: [
                      _stepButton(
                        Icons.remove_rounded,
                        () {
                          if (_dailyFrequencyCap > 1) {
                            setState(() => _dailyFrequencyCap--);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      _stepButton(
                        Icons.add_rounded,
                        () {
                          if (_dailyFrequencyCap < 20) {
                            setState(() => _dailyFrequencyCap++);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'End Date: ${_endsAt == null ? 'Run until budget spent' : _endsAt!.toIso8601String().substring(0, 10)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.textSecondary,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endsAt ?? now.add(const Duration(days: 14)),
                        firstDate: now.add(const Duration(days: 1)),
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (picked != null && mounted) {
                        setState(() => _endsAt = picked);
                      }
                    },
                    child: const Text('Pick End Date'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Ad Creative
        _clearCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '3. Ad Creative (R2 Media)',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUploadingMedia
                          ? null
                          : () => _pickAndUploadCreative(isVideo: false),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Upload Image'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ZevColors.deepNavy,
                        side: const BorderSide(color: ZevColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUploadingMedia
                          ? null
                          : () => _pickAndUploadCreative(isVideo: true),
                      icon: const Icon(Icons.videocam_outlined, size: 18),
                      label: const Text('Upload Video'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ZevColors.deepNavy,
                        side: const BorderSide(color: ZevColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isUploadingMedia) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _uploadProgress,
                  backgroundColor: ZevColors.softSurface,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    ZevColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Uploading creative ${(100 * _uploadProgress).round()}%...',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ],
              if (_uploadError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _uploadError!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.errorRed,
                  ),
                ),
              ],
              if (_uploadedMediaUrl != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ZevColors.softSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ZevColors.border),
                  ),
                  child: Row(
                    children: [
                      if (_localPreviewBytes != null && _mediaType == 'image')
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _localPreviewBytes!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                          ),
                        )
                      else if (_uploadedMediaUrl != null && _mediaType == 'image')
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: ZevCachedImage.feedPost(
                              imageUrl: _uploadedMediaUrl!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 40,
                          color: ZevColors.secondaryBlue,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _sourcePostId != null
                              ? 'Post media attached and ready for promotion'
                              : 'Creative uploaded and ready for delivery',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _uploadedMediaUrl = null;
                            _localPreviewBytes = null;
                          });
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: ZevColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildClearInput(
                controller: _titleCtrl,
                label: 'Headline Title *',
                hint: 'Handcrafted Designs Built For Creators',
              ),
              const SizedBox(height: 10),
              _buildClearInput(
                controller: _bodyCtrl,
                label: 'Ad Copy / Description *',
                hint: 'Tell viewers what makes your offer stand out...',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _buildClearInput(
                controller: _destinationUrlCtrl,
                label: 'Destination URL *',
                hint: 'https://yourbrand.com/offer',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 10),
              _buildClearInput(
                controller: _ctaLabelCtrl,
                label: 'Call-To-Action Button Text',
                hint: 'Learn More',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _ctaPresets
                    .map(
                      (cta) => _selectChip(
                        label: cta,
                        selected: _ctaLabelCtrl.text.trim() == cta,
                        onTap: () => setState(() => _ctaLabelCtrl.text = cta),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. Audience Targeting
        _clearCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '4. Audience Targeting',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Target Countries (leave unselected for Global)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _countryPresets
                    .map(
                      (c) => _selectChip(
                        label: c,
                        selected: _selectedCountries.contains(c),
                        onTap: () => setState(() {
                          if (!_selectedCountries.remove(c)) {
                            _selectedCountries.add(c);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              _buildClearInput(
                controller: _customCountriesCtrl,
                label: 'Extra Country Codes (comma-separated)',
                hint: 'e.g. FR, NL, SE',
              ),
              const SizedBox(height: 12),
              const Text(
                'Languages',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _languagePresets
                    .map(
                      (l) => _selectChip(
                        label: l.toUpperCase(),
                        selected: _selectedLanguages.contains(l),
                        onTap: () => setState(() {
                          if (!_selectedLanguages.remove(l)) {
                            _selectedLanguages.add(l);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Interests & Categories',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _interestPresets
                    .map(
                      (interest) => _selectChip(
                        label: interest,
                        selected: _selectedInterests.contains(interest),
                        onTap: () => setState(() {
                          if (!_selectedInterests.remove(interest)) {
                            _selectedInterests.add(interest);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                'Age Range: ${_ageRange.start.round()} – ${_ageRange.end.round() >= 65 ? '65+' : _ageRange.end.round()}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.deepNavy,
                ),
              ),
              RangeSlider(
                values: _ageRange,
                min: 13,
                max: 65,
                divisions: 52,
                activeColor: ZevColors.secondaryBlue,
                onChanged: (v) => setState(() => _ageRange = v),
              ),
              const SizedBox(height: 6),
              Row(
                children: ['all', 'female', 'male']
                    .map(
                      (g) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _selectChip(
                          label: g.toUpperCase(),
                          selected: _gender == g,
                          onTap: () => setState(() => _gender = g),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildLiveAdPreviewCard(),
        const SizedBox(height: 18),

        ElevatedButton(
          onPressed: _isSubmittingCampaign ? null : _submitCampaign,
          style: ElevatedButton.styleFrom(
            backgroundColor: ZevColors.secondaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: _isSubmittingCampaign
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _sourcePostId != null
                      ? 'Submit Boosted Post for Review'
                      : 'Submit Campaign for Review',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBoostPostBannerCard() {
    if (_sourcePostId != null) {
      final post = _sourcePostPreview;
      final thumbUrl = _uploadedMediaUrl;
      return _clearCard(
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 52,
                height: 52,
                child: thumbUrl != null && thumbUrl.isNotEmpty
                    ? (_mediaType == 'video'
                        ? Container(
                            color: ZevColors.deepNavy,
                            child: const Icon(
                              Icons.play_circle_filled_rounded,
                              color: Colors.white,
                            ),
                          )
                        : ZevCachedImage.feedPost(
                            imageUrl: thumbUrl,
                            fit: BoxFit.cover,
                          ))
                    : Container(
                        color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                        child: const Icon(
                          Icons.rocket_launch_rounded,
                          color: Color(0xFF0284C7),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PROMOTING PREVIOUS POST',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0284C7),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    post != null && post.title.trim().isNotEmpty
                        ? post.title.trim()
                        : (_titleCtrl.text.trim().isNotEmpty
                            ? _titleCtrl.text.trim()
                            : 'Post #${_sourcePostId!.substring(0, 6)}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const Text(
                    'Pre-filled from your post. You can customize anything below.',
                    style: TextStyle(
                      fontSize: 11,
                      color: ZevColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _openPostPickerSheet,
              child: const Text('Change'),
            ),
            IconButton(
              tooltip: 'Clear linked post',
              onPressed: _clearBoostPost,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: ZevColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return _clearCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ZevColors.primaryBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              color: Color(0xFF0284C7),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Advertise a Previous Post',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Or fill the form below to build a custom creative from scratch.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _openPostPickerSheet,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0284C7),
              side: BorderSide(
                color: ZevColors.primaryBlue.withValues(alpha: 0.45),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Pick Post',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveAdPreviewCard() {
    final brandName = _dashboard.advertiser?.businessName ??
        (_bizNameCtrl.text.trim().isNotEmpty
            ? _bizNameCtrl.text.trim()
            : 'Your Brand');
    final headline = _titleCtrl.text.trim().isNotEmpty
        ? _titleCtrl.text.trim()
        : 'Your Sponsored Headline';
    final copy = _bodyCtrl.text.trim().isNotEmpty
        ? _bodyCtrl.text.trim()
        : 'Preview of how your ZEV Sponsored Ad will appear in users’ feeds.';
    final cta = _ctaLabelCtrl.text.trim().isNotEmpty
        ? _ctaLabelCtrl.text.trim()
        : 'Learn More';

    return _clearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 16,
                color: Color(0xFF0284C7),
              ),
              SizedBox(width: 6),
              Text(
                'LIVE AD PREVIEW',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.textMuted,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ZevColors.border, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Sponsored',
                          style: TextStyle(
                            color: Color(0xFF0284C7),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          brandName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ZevColors.deepNavy,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _sourcePostId != null ? 'Promoted Post' : 'ZEV Ads',
                        style: const TextStyle(
                          color: ZevColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_localPreviewBytes != null && _mediaType == 'image')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 150,
                        child: Image.memory(
                          _localPreviewBytes!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                else if (_uploadedMediaUrl != null &&
                    _uploadedMediaUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 150,
                        child: _mediaType == 'video'
                            ? Container(
                                color: ZevColors.deepNavy,
                                child: const Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              )
                            : ZevCachedImage.feedPost(
                                imageUrl: _uploadedMediaUrl!,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        copy,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ZevColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          gradient: ZevColors.brandGradientHorizontal,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            cta,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 3: BILLING & INVOICES
  // ===========================================================================
  Widget _buildBillingTab() {
    final adv = _dashboard.advertiser;
    final invoices = _dashboard.invoices;
    final campaigns = _dashboard.campaigns;

    return RefreshIndicator(
      color: ZevColors.primaryBlue,
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
        children: [
          _clearCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ADVERTISER WALLET',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.textMuted,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  adv != null
                      ? '\$${adv.balance.toStringAsFixed(2)} ${adv.currency}'
                      : '\$0.00 USD',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ad spend is deducted atomically per served impression/click/conversion. Wallet top-ups are verified and credited by ZEV Billing Admins.',
                  style: TextStyle(
                    fontSize: 12,
                    color: ZevColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                if (campaigns.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedInvoiceCampaignId,
                    decoration: InputDecoration(
                      labelText: 'Invoice Scope',
                      filled: true,
                      fillColor: ZevColors.softSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: ZevColors.border),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Unbilled / Account Spend'),
                      ),
                      ...campaigns.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(
                            c.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedInvoiceCampaignId = v),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isGeneratingInvoice ? null : _generateInvoice,
                    icon: _isGeneratingInvoice
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('Generate Invoice Statement'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.secondaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'INVOICE HISTORY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ZevColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (invoices.isEmpty)
            _clearCard(
              child: const Column(
                children: [
                  Icon(
                    Icons.receipt_outlined,
                    size: 34,
                    color: ZevColors.textMuted,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No invoices generated yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ],
              ),
            )
          else
            ...invoices.map(
              (inv) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _clearCard(
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inv.invoiceNumber,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              inv.createdAt.length >= 10
                                  ? inv.createdAt.substring(0, 10)
                                  : inv.createdAt,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: ZevColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${inv.amount.toStringAsFixed(2)} ${inv.currency}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _statusPill(inv.status),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LIGHT CLEARMORPHISM HELPERS
  // ===========================================================================
  Widget _clearCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ZevColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildClearInput({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: ZevColors.deepNavy,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: ZevColors.textMuted,
              fontSize: 12.5,
            ),
            filled: true,
            fillColor: ZevColors.softSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: ZevColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: ZevColors.primaryBlue,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _selectChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          gradient: selected ? ZevColors.brandGradient : null,
          color: selected ? null : ZevColors.softSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.transparent : ZevColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : ZevColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ZevColors.border),
        ),
        child: Icon(icon, size: 17, color: ZevColors.deepNavy),
      ),
    );
  }

  Widget _kpiTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZevColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ZevColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: ZevColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final s = status.toLowerCase();
    Color fg = const Color(0xFF0284C7);
    if (s == 'active' || s == 'approved' || s == 'paid') {
      fg = ZevColors.successGreen;
    } else if (s == 'rejected' || s == 'suspended' || s == 'void') {
      fg = ZevColors.errorRed;
    } else if (s == 'pending_review' || s == 'pending' || s == 'paused') {
      fg = ZevColors.warningAmber;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: fg,
        ),
      ),
    );
  }

  String _compactInt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
