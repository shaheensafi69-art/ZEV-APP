import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
          _isLoading = false;
        });
      }

      // Fetch received gifts ledger
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
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openWebPortal(String url) async {
    HapticFeedback.lightImpact();
    final uid = _client.auth.currentUser?.id;
    final uri = Uri.parse(url);
    final targetUrl = (uid != null && uid.isNotEmpty)
        ? uri
              .replace(queryParameters: {...uri.queryParameters, 'uid': uid})
              .toString()
        : url;

    try {
      final launched = await launchUrlString(
        targetUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Could not open browser. Please visit pay.zevapp.com",
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

  void _showWithdrawModal() {
    if (_earningsUsd < 10.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Minimum withdrawal is \$10.00 USD. Your current balance is \$${_earningsUsd.toStringAsFixed(2)} USD.",
          ),
          backgroundColor: const Color(0xFF0F172A),
        ),
      );
      return;
    }

    final methodController = TextEditingController(text: 'PayPal');
    final accountController = TextEditingController();
    final amountController = TextEditingController(
      text: _earningsUsd.toStringAsFixed(2),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Cash Out Earnings",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Available: \$${_earningsUsd.toStringAsFixed(2)} USD (40% Creator Share)",
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Payout Method",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: methodController.text,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'PayPal',
                    child: Text('PayPal (Email)'),
                  ),
                  DropdownMenuItem(
                    value: 'USDT',
                    child: Text('USDT (TRC-20 Address)'),
                  ),
                  DropdownMenuItem(
                    value: 'Bank',
                    child: Text('Bank Wire / IBAN'),
                  ),
                ],
                onChanged: (v) =>
                    setModalState(() => methodController.text = v ?? 'PayPal'),
              ),
              const SizedBox(height: 14),
              const Text(
                "Destination Account / Address",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: accountController,
                decoration: InputDecoration(
                  hintText: methodController.text == 'PayPal'
                      ? 'name@example.com'
                      : 'Enter wallet or IBAN',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Amount (USD)",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  final destination = accountController.text.trim();
                  final amount =
                      double.tryParse(amountController.text.trim()) ?? 0.0;
                  if (destination.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please enter destination account."),
                      ),
                    );
                    return;
                  }
                  if (amount < 10.0 || amount > _earningsUsd) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Amount must be between \$10.00 and \$${_earningsUsd.toStringAsFixed(2)}",
                        ),
                      ),
                    );
                    return;
                  }

                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  try {
                    await _client.from('payout_requests').insert({
                      'user_id': _client.auth.currentUser!.id,
                      'amount_usd': amount,
                      'payout_method': methodController.text.toLowerCase(),
                      'destination_account': destination,
                      'status': 'pending',
                    });

                    // Deduct from profile
                    await _client
                        .from('profiles')
                        .update({'earnings_usd': _earningsUsd - amount})
                        .eq('id', _client.auth.currentUser!.id);

                    _fetchBalances();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Withdrawal request submitted! Processing within 24-48 hours.",
                        ),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text("Payout error: $e")),
                    );
                  }
                },
                child: const Text(
                  "Confirm Withdrawal",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              maxWidth: isDesktop ? 600 : double.infinity,
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

  // 1. COINS TAB: User Virtual Coins (For Gifting)
  Widget _buildCoinsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
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
                const SizedBox(height: 16),
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
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF78350F),
                          letterSpacing: -1,
                        ),
                      ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFFCD34D),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    "Available for Livestream Gifts & Tips",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Primary Recharge Action Button
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
                    "Recharge Coins (0% Fee)",
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

          const SizedBox(height: 20),

          // Benefits Card
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
                      size: 18,
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
                  "• No App Store 30% surcharge — get up to 30% extra coins.\n"
                  "• Pay securely with Visa, Mastercard, PayPal & Crypto (USDT).\n"
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
        ],
      ),
    );
  }

  // 2. CREATOR CASH TAB: Real USD Earnings (from 40% gift cut)
  Widget _buildEarningsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                const SizedBox(height: 16),
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
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF064E3B),
                          letterSpacing: -1,
                        ),
                      ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
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

          const SizedBox(height: 20),

          // Primary Withdraw Button
          GestureDetector(
            onTap: _showWithdrawModal,
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
                      size: 18,
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
                  "• 60% Platform Share: Reinvested into ultra-low latency 4K livestreaming, Agora servers, payment processing, and safety.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF475569),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
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
                          "Example: 70 Coins (~\$1.00 USD) = \$0.40 USD deposited to your cash earnings.",
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
        ],
      ),
    );
  }
}
