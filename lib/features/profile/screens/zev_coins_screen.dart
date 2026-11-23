import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'zev_payout_screen.dart';

class ZevCoinsScreen extends StatefulWidget {
  final Map<String, dynamic>? userProfile;
  final int initialTabIndex;

  const ZevCoinsScreen({super.key, this.userProfile, this.initialTabIndex = 0});

  static Future<void> open(
    BuildContext context, {
    Map<String, dynamic>? userProfile,
    int initialTab = 0,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ZevCoinsScreen(
          userProfile: userProfile,
          initialTabIndex: initialTab,
        ),
      ),
    );
  }

  @override
  State<ZevCoinsScreen> createState() => _ZevCoinsScreenState();
}

class _ZevCoinsScreenState extends State<ZevCoinsScreen>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;

  int _coinsBalance = 0;
  double _earningsUsd = 0.0;
  int _creatorEarningsCoins = 0;
  bool _isLoading = true;

  List<Map<String, dynamic>> _coinPackages = [];
  List<Map<String, dynamic>> _recentGifts = [];
  List<Map<String, dynamic>> _pendingPayouts = [];

  static const String kCoinsWebUrl = 'https://pay.zevapp.com';

  // Standard fallback packages matching web portal
  static const List<Map<String, dynamic>> kDefaultPackages = [
    {
      'id': 'tier_70',
      'coins': 70,
      'price_usd': 0.99,
      'discount_pct': 0,
      'badge': null,
    },
    {
      'id': 'tier_350',
      'coins': 350,
      'price_usd': 4.79,
      'discount_pct': 5,
      'badge': null,
    },
    {
      'id': 'tier_700',
      'coins': 700,
      'price_usd': 9.49,
      'discount_pct': 10,
      'badge': 'MOST POPULAR',
    },
    {
      'id': 'tier_1400',
      'coins': 1400,
      'price_usd': 18.49,
      'discount_pct': 15,
      'badge': 'CREATOR CHOICE',
    },
    {
      'id': 'tier_3500',
      'coins': 3500,
      'price_usd': 44.99,
      'discount_pct': 20,
      'badge': 'VIP STREAMER',
    },
    {
      'id': 'tier_7000',
      'coins': 7000,
      'price_usd': 84.99,
      'discount_pct': 25,
      'badge': 'ELITE PRO',
    },
    {
      'id': 'tier_17500',
      'coins': 17500,
      'price_usd': 199.99,
      'discount_pct': 30,
      'badge': 'MAX SAVINGS',
    },
  ];

  @override
  void initState() {
    super.initState();
    _coinPackages = List.from(kDefaultPackages);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _fetchBalances();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBalances() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch user wallet balances from profiles
      final res = await _client
          .from('profiles')
          .select('coins_balance, earnings_usd, earnings_coins')
          .eq('id', userId)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _coinsBalance = (res['coins_balance'] as num?)?.toInt() ?? 0;
          _earningsUsd = (res['earnings_usd'] as num?)?.toDouble() ?? 0.0;
          _creatorEarningsCoins = (res['earnings_coins'] as num?)?.toInt() ?? 0;
        });
      }

      // 2. Fetch active coin packages from database
      try {
        final pkgs = await _client
            .from('coin_packages')
            .select('*')
            .eq('is_active', true)
            .order('coins', ascending: true);

        if (pkgs.isNotEmpty && mounted) {
          setState(() {
            _coinPackages = List<Map<String, dynamic>>.from(pkgs);
          });
        }
      } catch (_) {
        // Fallback to kDefaultPackages is already set
      }

      // 3. Fetch received gifts ledger
      try {
        final gifts = await _client
            .from('gift_transactions')
            .select(
              '*, sender:profiles!gift_transactions_sender_id_fkey(username, avatar_url, first_name)',
            )
            .eq('receiver_id', userId)
            .order('created_at', ascending: false)
            .limit(20);

        if (mounted) {
          setState(() {
            _recentGifts = List<Map<String, dynamic>>.from(gifts);
          });
        }
      } catch (_) {}

      // 4. Fetch pending payout requests
      try {
        final payouts = await _client
            .from('payout_requests')
            .select('*')
            .eq('user_id', userId)
            .inFilter('status', ['pending', 'processing'])
            .order('created_at', ascending: false);

        if (mounted) {
          setState(() {
            _pendingPayouts = List<Map<String, dynamic>>.from(payouts);
          });
        }
      } catch (_) {}

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openWebPortal(String url, {String? packageId, int? coins}) async {
    HapticFeedback.lightImpact();
    final uid = _client.auth.currentUser?.id;
    final uri = Uri.parse(url);
    final params = Map<String, String>.from(uri.queryParameters);

    if (uid != null && uid.isNotEmpty) {
      params['uid'] = uid;
    }
    if (packageId != null && packageId.isNotEmpty) {
      params['package_id'] = packageId;
    }
    if (coins != null && coins > 0) {
      params['coins'] = coins.toString();
    }

    final targetUrl = uri.replace(queryParameters: params).toString();

    try {
      final launched = await launchUrlString(
        targetUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Could not open browser. Please visit pay.zevapp.com directly.",
            ),
            backgroundColor: Color(0xFF0F172A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Redirect error: $e"),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _navigateToPayout({int initialTab = 0}) async {
    final changed = await ZevPayoutScreen.open(
      context,
      currentEarningsUsd: _earningsUsd,
      totalEarningsCoins: _creatorEarningsCoins,
      initialTab: initialTab,
    );
    if (changed == true || mounted) {
      _fetchBalances();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "ZEV Wallet & Coins",
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF64748B),
              size: 22,
            ),
            tooltip: "Refresh Balance",
            onPressed: () {
              HapticFeedback.lightImpact();
              _fetchBalances();
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: const Color(0xFF0F172A),
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🪙'),
                      SizedBox(width: 6),
                      Text("Coins Balance"),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('💵'),
                      SizedBox(width: 6),
                      Text("Creator Cash (USD)"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 680 : double.infinity,
            ),
            child: TabBarView(
              controller: _tabController,
              children: [_buildCoinsTab(), _buildEarningsTab()],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. COINS TAB: User Virtual Coins (For Gifting & Tips)
  // ===========================================================================
  Widget _buildCoinsTab() {
    return RefreshIndicator(
      color: const Color(0xFFD97706),
      onRefresh: _fetchBalances,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coins Balance Card (Gold Amber Clearmorphic)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text('🪙', style: TextStyle(fontSize: 34)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Virtual Coins Balance",
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        )
                      : Text(
                          _coinsBalance.toString(),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF78350F),
                            letterSpacing: -1,
                          ),
                        ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFFFCD34D),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          color: Color(0xFFD97706),
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Available for Livestream Gifts & Tips",
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Primary Fast Top-Up Action Button
            GestureDetector(
              onTap: () => _openWebPortal(kCoinsWebUrl),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D4FF), Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded, color: Color(0xFF080D1A), size: 24),
                    SizedBox(width: 8),
                    Text(
                      "Recharge Coins on Web (0% Fee)",
                      style: TextStyle(
                        color: Color(0xFF080D1A),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Packages Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Select Coin Package",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Text(
                    "0% APP STORE FEES",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF059669),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Packages Grid (2 Columns)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _coinPackages.length + 1, // +1 for Custom Amount tile
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
              itemBuilder: (context, index) {
                // Last item: Custom Amount
                if (index == _coinPackages.length) {
                  return _buildCustomPackageCard();
                }

                final pkg = _coinPackages[index];
                return _buildPackageCard(pkg);
              },
            ),

            const SizedBox(height: 20),

            // Benefits & Security Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: Color(0xFF0284C7),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Why top up on ZEV Web Portal?",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "• 0% App Store 30% surcharge — get up to 30% more coins for your money.\n"
                    "• Pay securely with Visa, Mastercard, PayPal & Crypto (USDT TRC-20).\n"
                    "• Instant credit to your ZEV account with 256-Bit SSL encryption.",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF475569),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageCard(Map<String, dynamic> pkg) {
    final packageId = pkg['id']?.toString() ?? '';
    final coins = (pkg['coins'] as num?)?.toInt() ?? 0;
    final priceUsd = (pkg['price_usd'] as num?)?.toDouble() ?? 0.0;
    final discountPct = (pkg['discount_pct'] as num?)?.toInt() ?? 0;
    final badge = pkg['badge'] as String?;

    Color badgeColor = const Color(0xFF0284C7);
    if (badge == 'MOST POPULAR') {
      badgeColor = const Color(0xFFEF4444);
    } else if (badge == 'CREATOR CHOICE') {
      badgeColor = const Color(0xFF8B5CF6);
    } else if (badge == 'VIP STREAMER') {
      badgeColor = const Color(0xFF3B82F6);
    } else if (badge == 'ELITE PRO') {
      badgeColor = const Color(0xFFF59E0B);
    } else if (badge == 'MAX SAVINGS') {
      badgeColor = const Color(0xFF10B981);
    }

    return GestureDetector(
      onTap: () => _openWebPortal(
        kCoinsWebUrl,
        packageId: packageId,
        coins: coins,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: badge != null
                ? badgeColor.withValues(alpha: 0.4)
                : const Color(0xFFE2E8F0),
            width: badge != null ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: badge != null
                  ? badgeColor.withValues(alpha: 0.08)
                  : const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text('🪙', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "$coins",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        color: badgeColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "\$${priceUsd.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (discountPct > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Save $discountPct%",
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomPackageCard() {
    return GestureDetector(
      onTap: () => _openWebPortal(kCoinsWebUrl),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFCBD5E1),
            style: BorderStyle.solid,
            width: 1.5,
          ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text('✨', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text(
                  "Custom",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            Text(
              "Any Amount\nFlexible >",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. CREATOR CASH TAB: Real USD Earnings (from 40% gift cut) & Cashout
  // ===========================================================================
  Widget _buildEarningsTab() {
    return RefreshIndicator(
      color: const Color(0xFF10B981),
      onRefresh: _fetchBalances,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pending Payout Notice Banner (if any)
            if (_pendingPayouts.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      color: Color(0xFFD97706),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Payout Request Pending",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          Text(
                            "${_pendingPayouts.length} request(s) under review. Tap to check status.",
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _navigateToPayout(initialTab: 1),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB45309),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text(
                        "View",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Earnings Balance Card (Emerald Clearmorphic)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF34D399), Color(0xFF10B981)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text('💵', style: TextStyle(fontSize: 34)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Creator Withdrawable Earnings",
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF065F46),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF059669),
                            ),
                          ),
                        )
                      : Text(
                          "\$${_earningsUsd.toStringAsFixed(2)} USD",
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF064E3B),
                            letterSpacing: -1,
                          ),
                        ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF6EE7B7),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      "$_creatorEarningsCoins Diamonds / Gift Coins Received",
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Primary Withdraw Button -> Opens ZevPayoutScreen (Tab 0)
            GestureDetector(
              onTap: () => _navigateToPayout(initialTab: 0),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.payments_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      "Withdraw Cash (PayPal / USDT / Bank)",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Secondary Button: View Payout History & Status -> Opens ZevPayoutScreen (Tab 1)
            OutlinedButton.icon(
              onPressed: () => _navigateToPayout(initialTab: 1),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text(
                "View Payout History & Status",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 40% / 60% TikTok Accounting Transparency Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.pie_chart_outline_rounded,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "40% Creator Revenue Share",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "• 40% Creator Share: You earn 40% real cash value for every gift received in your live streams.\n"
                    "• 60% Platform Share: Reinvested into ultra-low latency 4K livestreaming, Agora servers, and safety.\n"
                    "• Minimum withdrawal threshold is \$10.00 USD with 0% platform withdrawal fee.",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF475569),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Text("💡", style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Example: 70 Coins (~\$0.99 USD) = \$0.40 USD deposited to your cash earnings.",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Recent Received Gifts List
            const Text(
              "Recent Gifts Received",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            if (_recentGifts.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Center(
                  child: Text(
                    "No gifts received yet. Start a livestream to earn!",
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                  ),
                ),
              )
            else
              ..._recentGifts.map((gift) {
                final sender = gift['sender'] as Map<String, dynamic>?;
                final senderName =
                    sender?['username'] ?? sender?['first_name'] ?? 'Viewer';
                final giftName = gift['gift_name'] ?? 'Gift';
                final giftEmoji = gift['gift_emoji'] ?? '🎁';
                final coins = gift['coins_amount'] ?? 0;
                final creatorUsd =
                    (gift['creator_usd'] as num?)?.toDouble() ?? 0.0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Text(giftEmoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$giftName from @$senderName",
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              "$coins Coins sent",
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "+\$${creatorUsd.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
