import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../core/theme/zev_theme.dart';
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

  List<Map<String, dynamic>> _recentGifts = [];
  List<Map<String, dynamic>> _pendingPayouts = [];

  static const String kCoinsWebUrl = 'https://pay.zevapp.com';

  @override
  void initState() {
    super.initState();
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

      // 2. Fetch received gifts ledger
      try {
        final gifts = await _client
            .from('gift_transactions')
            .select(
              '*, sender:profiles!gift_transactions_sender_id_fkey(username, avatar_url, first_name)',
            )
            .eq('receiver_id', userId)
            .order('created_at', ascending: false)
            .limit(15);

        if (mounted) {
          setState(() {
            _recentGifts = List<Map<String, dynamic>>.from(gifts);
          });
        }
      } catch (_) {}

      // 3. Fetch active payout requests
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

  Future<void> _openWebPortal() async {
    HapticFeedback.lightImpact();
    final uid = _client.auth.currentUser?.id;
    final uri = Uri.parse(kCoinsWebUrl);
    final params = Map<String, String>.from(uri.queryParameters);

    if (uid != null && uid.isNotEmpty) {
      params['uid'] = uid;
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
            content: Text("Could not open browser. Please visit pay.zevapp.com"),
            backgroundColor: ZevColors.deepNavy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Redirect error: $e"),
            backgroundColor: ZevColors.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _navigateToPayout({int initialTab = 0}) async {
    final changed = await ZevPayoutScreen.open(
      context,
      currentEarningsUsd: _earningsUsd,
      totalEarningsCoins: _coinsBalance,
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
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
          "ZEV Wallet & Coins",
          style: TextStyle(
            color: ZevColors.deepNavy,
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
              color: ZevColors.textMuted,
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
              color: const Color(0xFFEDF2F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: ZevColors.deepNavy,
              unselectedLabelColor: ZevColors.textMuted,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🪙'),
                      SizedBox(width: 6),
                      Text("Virtual Coins"),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('💎'),
                      SizedBox(width: 6),
                      Text("Creator Cashout"),
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
              maxWidth: isDesktop ? 640 : double.infinity,
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
  // 1. COINS TAB: Clean, informational, with Web Recharge button (NO package grid)
  // ===========================================================================
  Widget _buildCoinsTab() {
    return RefreshIndicator(
      color: ZevColors.primaryBlue,
      onRefresh: _fetchBalances,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Clearmorphic ZEV Coins Balance Card
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.primaryBlue.withValues(alpha: 0.09),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFF59E0B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text('🪙', style: TextStyle(fontSize: 38)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Virtual Coins Balance",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.textMuted,
                      letterSpacing: 0.5,
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
                              color: ZevColors.primaryBlue,
                            ),
                          ),
                        )
                      : Text(
                          _coinsBalance.toString(),
                          style: const TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                            letterSpacing: -1.2,
                          ),
                        ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF0284C7),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "≈ \$${(_coinsBalance * 0.01414).toStringAsFixed(2)} USD • Ready for Live Gifts & Tips",
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 2. Primary Web Recharge Action Button
            GestureDetector(
              onTap: _openWebPortal,
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [ZevColors.primaryBlue, Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.38),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded, color: ZevColors.deepNavy, size: 26),
                    SizedBox(width: 8),
                    Text(
                      "Recharge Coins on ZEV Web (0% Fee)",
                      style: TextStyle(
                        color: ZevColors.deepNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),

            // 3. Information & Benefits Clearmorphic Cards (As requested: معلومات کامل بدون لیست بسته‌ها)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ZevColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.stars_rounded, color: Color(0xFF0284C7), size: 22),
                      SizedBox(width: 10),
                      Text(
                        "How ZEV Coins Work",
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    icon: Icons.card_giftcard_rounded,
                    title: "Livestream Gifting & Tipping",
                    desc: "Send animated virtual gifts in live video and audio streams to support your favorite creators.",
                  ),
                  const Divider(height: 20, color: Color(0xFFF1F5F9)),
                  _buildInfoItem(
                    icon: Icons.percent_rounded,
                    title: "0% App Store Commissions on Web",
                    desc: "By topping up on pay.zevapp.com, you bypass Apple and Google's 30% cut and receive up to 30% more coins for your money.",
                  ),
                  const Divider(height: 20, color: Color(0xFFF1F5F9)),
                  _buildInfoItem(
                    icon: Icons.account_balance_wallet_rounded,
                    title: "Instant Global Payment Methods",
                    desc: "Securely pay with Credit/Debit Cards (Visa & Mastercard), PayPal, and Crypto (USDT TRC-20, BTC, TON, Solana).",
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 4. Quick Link to Creator Cashout
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: ZevColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF2F7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.payments_rounded,
                      color: ZevColors.deepNavy,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Are you a Live Creator?",
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                        Text(
                          "Convert received gift coins into cash and withdraw via Bank, HesabPay, Crypto or PayPal.",
                          style: TextStyle(
                            fontSize: 11.5,
                            color: ZevColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _navigateToPayout(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.deepNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                    child: const Text("Payout Hub"),
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

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF0284C7), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: ZevColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. CREATOR CASHOUT TAB: Withdrawable Earnings & Direct Payout Access
  // ===========================================================================
  Widget _buildEarningsTab() {
    return RefreshIndicator(
      color: ZevColors.primaryBlue,
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
                  color: const Color(0xFFFEF3C7),
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
                            "Payout Request In Progress",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          Text(
                            "${_pendingPayouts.length} request(s) under admin review. Tap to check status.",
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _navigateToPayout(initialTab: 2),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB45309),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text(
                        "Track",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Clearmorphic Creator Withdrawable Card
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.primaryBlue.withValues(alpha: 0.09),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [ZevColors.primaryBlue, Color(0xFF0284C7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text('💎', style: TextStyle(fontSize: 36)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Creator Withdrawable Earnings",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.textMuted,
                      letterSpacing: 0.5,
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
                              color: ZevColors.primaryBlue,
                            ),
                          ),
                        )
                      : Text(
                          "\$${_earningsUsd.toStringAsFixed(2)} USD",
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                            letterSpacing: -1.2,
                          ),
                        ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: Text(
                      "$_coinsBalance Coins Available (All-time: $_creatorEarningsCoins)",
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
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
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [ZevColors.deepNavy, Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, color: ZevColors.primaryBlue, size: 24),
                    SizedBox(width: 10),
                    Text(
                      "Withdraw Earnings (Bank, HesabPay, Crypto)",
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

            // Secondary Button: View Payout History & Saved Accounts
            OutlinedButton.icon(
              onPressed: () => _navigateToPayout(initialTab: 2),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text(
                "View Payout History & Track Status",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ZevColors.deepNavy,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            const SizedBox(height: 22),

            // 40% / 60% TikTok Accounting Transparency Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ZevColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
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
                        color: Color(0xFF0284C7),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "40% Creator Revenue Share",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "• 40% Direct Creator Share: You receive 40% of the coins sent to you directly into your wallet.\n"
                    "• Spend or Cash Out: Use your coins directly in the app or cash them out to your bank account, HesabPay, crypto wallet or PayPal.\n"
                    "• 60% Platform Share: Reinvested into ultra-low latency 4K livestreaming, Agora servers, and global payments.",
                    style: TextStyle(
                      fontSize: 12,
                      color: ZevColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Recent Received Gifts List
            const Text(
              "Recent Received Gifts",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 10),
            if (_recentGifts.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ZevColors.border),
                ),
                child: const Center(
                  child: Text(
                    "No gifts received yet. Start a livestream to earn!",
                    style: TextStyle(fontSize: 12.5, color: ZevColors.textMuted),
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
                final receiverCoins = gift['receiver_coins'] ?? (coins * 0.4).floor();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ZevColors.border),
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
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            Text(
                              "$coins Coins sent (You received $receiverCoins Coins)",
                              style: const TextStyle(
                                fontSize: 11,
                                color: ZevColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "+$receiverCoins 🪙",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0284C7),
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
