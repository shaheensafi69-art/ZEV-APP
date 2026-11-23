import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/telegram_notification_service.dart';
import '../../../core/theme/zev_theme.dart';

class ZevPayoutScreen extends StatefulWidget {
  final double currentEarningsUsd;
  final int totalEarningsCoins;
  final int initialTabIndex;

  // Crypto Networks Available
  static const List<String> kCryptoNetworks = [
    'TRC-20 (Tron) - Low Fee / Recommended',
    'ERC-20 (Ethereum)',
    'BEP-20 (BNB Smart Chain)',
    'Solana (SOL)',
    'TON Network',
    'Polygon (MATIC)',
  ];

  const ZevPayoutScreen({
    super.key,
    this.currentEarningsUsd = 0.0,
    this.totalEarningsCoins = 0,
    this.initialTabIndex = 0,
  });

  static Future<bool?> open(
    BuildContext context, {
    double currentEarningsUsd = 0.0,
    int totalEarningsCoins = 0,
    int initialTab = 0,
  }) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ZevPayoutScreen(
          currentEarningsUsd: currentEarningsUsd,
          totalEarningsCoins: totalEarningsCoins,
          initialTabIndex: initialTab,
        ),
      ),
    );
  }

  @override
  State<ZevPayoutScreen> createState() => _ZevPayoutScreenState();
}

class _ZevPayoutScreenState extends State<ZevPayoutScreen>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;

  int _coinsBalance = 0;
  double _availableUsd = 0.0;
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Saved Payout Accounts
  List<Map<String, dynamic>> _savedAccounts = [];
  Map<String, dynamic>? _selectedAccount;

  // History State
  List<Map<String, dynamic>> _payoutHistory = [];

  // Payout Form Inputs
  final _coinsController = TextEditingController(text: '700');
  String _activeCurrency = 'USD'; // USD, EUR, GBP, AFN

  // Standard Mathematical Conversion Rates
  // 70 Coins = $0.99 USD => 1 Coin = 0.014142857 USD
  static const double kUsdPerCoin = 0.014142857;
  static const double kEurPerUsd = 0.93;
  static const double kGbpPerUsd = 0.79;
  static const double kAfnPerUsd = 68.0;
  static const int kMinCoinsWithdrawal = 700; // ~$9.90 USD

  @override
  void initState() {
    super.initState();
    _availableUsd = widget.currentEarningsUsd;
    _coinsBalance = widget.totalEarningsCoins;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _coinsController.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _coinsController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch live user coins and earnings
      final profileRes = await _client
          .from('profiles')
          .select('coins_balance, earnings_usd, earnings_coins')
          .eq('id', user.id)
          .maybeSingle();

      if (profileRes != null) {
        _coinsBalance = (profileRes['coins_balance'] as num?)?.toInt() ?? 0;
        _availableUsd = (profileRes['earnings_usd'] as num?)?.toDouble() ?? 0.0;
      }

      // 2. Fetch saved payout methods
      final methodsRes = await _client
          .from('user_payout_methods')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      _savedAccounts = List<Map<String, dynamic>>.from(methodsRes);
      if (_savedAccounts.isNotEmpty && _selectedAccount == null) {
        _selectedAccount = _savedAccounts.first;
        _activeCurrency = _selectedAccount?['currency'] ?? 'USD';
      }

      // 3. Fetch payout history
      final historyRes = await _client
          .from('payout_requests')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(30);

      _payoutHistory = List<Map<String, dynamic>>.from(historyRes);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _calculateUsd(int coins) => coins * kUsdPerCoin;

  double _calculateTargetAmount(int coins, String currency) {
    final usd = _calculateUsd(coins);
    switch (currency) {
      case 'EUR':
        return usd * kEurPerUsd;
      case 'GBP':
        return usd * kGbpPerUsd;
      case 'AFN':
        return usd * kAfnPerUsd;
      case 'USD':
      default:
        return usd;
    }
  }

  String _getCurrencySymbol(String currency) {
    switch (currency) {
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'AFN':
        return 'AFN ';
      case 'USD':
      default:
        return '\$';
    }
  }

  void _setCoinAmount(int coins) {
    HapticFeedback.selectionClick();
    setState(() {
      _coinsController.text = coins.toString();
    });
  }

  // ===========================================================================
  // SUBMIT PAYOUT REQUEST WITH ATOMIC DEDUCTION & TELEGRAM BROADCAST
  // ===========================================================================
  Future<void> _submitPayoutRequest() async {
    HapticFeedback.mediumImpact();
    final user = _client.auth.currentUser;
    if (user == null) {
      _showToast('Please sign in to withdraw earnings.', isError: true);
      return;
    }

    if (_selectedAccount == null) {
      _showToast('Please select or add a payout destination account.', isError: true);
      return;
    }

    final coinsToRedeem = int.tryParse(_coinsController.text.trim()) ?? 0;

    if (coinsToRedeem < kMinCoinsWithdrawal) {
      _showToast(
        'Minimum withdrawal is $kMinCoinsWithdrawal Coins (~\$9.90 USD).',
        isError: true,
      );
      return;
    }

    if (coinsToRedeem > _coinsBalance) {
      _showToast(
        'Insufficient coins. You have $_coinsBalance coins available.',
        isError: true,
      );
      return;
    }

    final methodType = (_selectedAccount!['method_type'] ?? 'paypal').toString().toLowerCase();
    final targetCurrency = (_selectedAccount!['currency'] ?? 'USD').toString().toUpperCase();
    final accountDetails = Map<String, dynamic>.from(_selectedAccount!['details'] ?? {});
    final accountTitle = _selectedAccount!['account_title'] ?? 'Primary Account';

    String destinationAccount = '';
    if (methodType == 'hesabpay') {
      destinationAccount = accountDetails['phone_number']?.toString() ?? '';
    } else if (methodType == 'crypto') {
      destinationAccount = accountDetails['wallet_address']?.toString() ?? '';
    } else if (methodType == 'bank') {
      destinationAccount = accountDetails['iban']?.toString() ??
          accountDetails['account_number']?.toString() ??
          '';
    } else if (methodType == 'paypal') {
      destinationAccount = accountDetails['email']?.toString() ?? '';
    }

    final amountUsd = _calculateUsd(coinsToRedeem);
    final amountTarget = _calculateTargetAmount(coinsToRedeem, targetCurrency);
    final currSymbol = _getCurrencySymbol(targetCurrency);

    // Confirmation Glass Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.94),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
          ),
          title: const Text(
            "Confirm Payout Request",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: ZevColors.deepNavy,
              letterSpacing: -0.2,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "You are requesting cash out for $coinsToRedeem Coins.",
                style: const TextStyle(fontSize: 13.5, color: ZevColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00D4FF).withValues(alpha: 0.12),
                      const Color(0xFF536DFE).withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.35)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Receive Amount:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ZevColors.textMuted)),
                        Text(
                          "$currSymbol${amountTarget.toStringAsFixed(2)} $targetCurrency",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0284C7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("USD Value:", style: TextStyle(fontSize: 11.5, color: ZevColors.textMuted)),
                        Text("\$${amountUsd.toStringAsFixed(2)} USD", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.deepNavy)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Destination:", style: TextStyle(fontSize: 11.5, color: ZevColors.textMuted)),
                        Text(accountTitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.deepNavy)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "⚠️ $coinsToRedeem coins will be deducted immediately from your balance. The ZEV admin will review and process your transfer.",
                style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309), height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF080D1A), Color(0xFF1E293B)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Confirm & Withdraw", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      // 1. Atomic Coin Deduction from user profile
      final newCoins = _coinsBalance - coinsToRedeem;
      final newUsd = (_availableUsd - amountUsd).clamp(0.0, double.infinity);

      await _client.from('profiles').update({
        'coins_balance': newCoins,
        'earnings_usd': newUsd,
      }).eq('id', user.id);

      // 2. Insert payout request in database (Status: 'processing')
      final insertRes = await _client.from('payout_requests').insert({
        'user_id': user.id,
        'amount_usd': amountUsd,
        'coins_deducted': coinsToRedeem,
        'target_currency': targetCurrency,
        'amount_target_currency': amountTarget,
        'payout_method': methodType,
        'destination_account': destinationAccount.isNotEmpty ? destinationAccount : accountTitle,
        'payout_method_id': _selectedAccount?['id'],
        'account_details': accountDetails,
        'status': 'processing',
      }).select().single();

      final requestId = insertRes['id']?.toString() ?? 'REQ_${DateTime.now().millisecondsSinceEpoch}';

      // 3. Dispatch Instant Telegram Alert to @zevpayout_bot
      try {
        String username = 'User';
        String fullName = 'Creator';
        final userProfile = await _client.from('profiles').select('username, first_name, last_name').eq('id', user.id).maybeSingle();
        if (userProfile != null) {
          username = userProfile['username'] ?? userProfile['first_name'] ?? 'Creator';
          fullName = '${userProfile['first_name'] ?? ''} ${userProfile['last_name'] ?? ''}'.trim();
          if (fullName.isEmpty) fullName = username;
        }

        await TelegramNotificationService.sendPayoutRequestNotification(
          requestId: requestId,
          userId: user.id,
          username: username,
          fullName: fullName,
          coinsDeducted: coinsToRedeem,
          amountUsd: amountUsd,
          targetCurrency: targetCurrency,
          amountTargetCurrency: amountTarget,
          payoutMethod: methodType,
          destinationAccount: destinationAccount.isNotEmpty ? destinationAccount : accountTitle,
          accountDetails: accountDetails,
        );
      } catch (tgErr) {
        debugPrint('[Telegram Dispatch Warning] $tgErr');
      }

      _showToast('Payout request placed in processing! Admin will transfer funds.', isError: false);
      _loadData();
      _tabController.animateTo(2); // Switch to History tab
    } catch (e) {
      _showToast('Submission error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ===========================================================================
  // CANCEL & REFUND PENDING / PROCESSING REQUEST
  // ===========================================================================
  Future<void> _cancelPayoutRequest(Map<String, dynamic> request) async {
    HapticFeedback.mediumImpact();
    final reqId = request['id'];
    final coins = (request['coins_deducted'] as num?)?.toInt() ?? 0;
    final amountUsd = (request['amount_usd'] as num?)?.toDouble() ?? 0.0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
          ),
          title: const Text(
            "Cancel Payout Request?",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: ZevColors.deepNavy),
          ),
          content: Text(
            "Cancelling this request will immediately refund ${coins > 0 ? '$coins Coins' : '\$$amountUsd USD'} back to your wallet.",
            style: const TextStyle(color: ZevColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Keep Request"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.errorRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Yes, Cancel & Refund"),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      // 1. Mark request as rejected
      await _client
          .from('payout_requests')
          .update({'status': 'rejected', 'admin_notes': 'Cancelled by user.'})
          .eq('id', reqId);

      // 2. Refund coins and USD back to profiles
      await _client.from('profiles').update({
        'coins_balance': _coinsBalance + (coins > 0 ? coins : (amountUsd / kUsdPerCoin).round()),
        'earnings_usd': _availableUsd + amountUsd,
      }).eq('id', user.id);

      _showToast("Request cancelled and refunded successfully.", isError: false);
      _loadData();
    } catch (e) {
      _showToast("Cancel error: $e", isError: true);
    }
  }

  // ===========================================================================
  // EXCLUSIVE CLEARMORPHIC DRAWER FOR ADDING SAVED ACCOUNT
  // ===========================================================================
  void _showAddAccountSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _ClearmorphicAddAccountDrawer(
        onAccountCreated: () {
          Navigator.pop(ctx);
          _loadData();
          _showToast('Payout account saved successfully!', isError: false);
        },
      ),
    );
  }

  Future<void> _deleteAccount(String id) async {
    HapticFeedback.lightImpact();
    final del = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
          ),
          title: const Text("Delete Account?", style: TextStyle(fontWeight: FontWeight.w900, color: ZevColors.deepNavy)),
          content: const Text("Are you sure you want to remove this saved payout method?", style: TextStyle(color: ZevColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.errorRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Delete"),
            ),
          ],
        ),
      ),
    );
    if (del == true) {
      await _client.from('user_payout_methods').delete().eq('id', id);
      _loadData();
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? ZevColors.errorRed : const Color(0xFF0284C7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(114),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AppBar(
              backgroundColor: Colors.white.withValues(alpha: 0.75),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ZevColors.deepNavy,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context, true),
              ),
              title: const Text(
                "Creator Cashout & Payouts",
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
                  icon: const Icon(Icons.refresh_rounded, color: ZevColors.textMuted, size: 22),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _loadData();
                  },
                ),
                const SizedBox(width: 4),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.60),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.white, Color(0xFFF8FAFC)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.40),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: ZevColors.deepNavy,
                    unselectedLabelColor: ZevColors.textMuted,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    tabs: const [
                      Tab(text: "Withdraw Coins"),
                      Tab(text: "Saved Accounts"),
                      Tab(text: "Payout History"),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Ambient Layer with Mesh Glow Blobs for true Clearmorphism Refraction
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF3F7FC),
                    Color(0xFFE9F0F8),
                    Color(0xFFF5F9FD),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: -40,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00D4FF).withValues(alpha: 0.16),
                    const Color(0xFF00D4FF).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF536DFE).withValues(alpha: 0.14),
                    const Color(0xFF536DFE).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // Main View Content
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isDesktop ? 680 : double.infinity),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: ZevColors.primaryBlue))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildWithdrawTab(),
                          _buildSavedAccountsTab(),
                          _buildHistoryTab(),
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
  // TAB 1: WITHDRAW COINS & CASHOUT
  // ===========================================================================
  Widget _buildWithdrawTab() {
    final coinsToRedeem = int.tryParse(_coinsController.text.trim()) ?? 0;
    final targetCurrency = _selectedAccount != null ? (_selectedAccount!['currency'] ?? 'USD') : _activeCurrency;
    final convertedAmount = _calculateTargetAmount(coinsToRedeem, targetCurrency);
    final usdEquivalent = _calculateUsd(coinsToRedeem);
    final currSymbol = _getCurrencySymbol(targetCurrency);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Clearmorphic Balance Header Card
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.88),
                      Colors.white.withValues(alpha: 0.62),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Available Withdrawable Balance",
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ZevColors.textMuted),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF00D4FF).withValues(alpha: 0.15),
                                const Color(0xFF536DFE).withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.35)),
                          ),
                          child: const Text(
                            "0% CASHOUT FEE",
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0284C7)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _coinsBalance.toString(),
                          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: ZevColors.deepNavy, letterSpacing: -1),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Coins",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0284C7)),
                        ),
                        const Spacer(),
                        Text(
                          "≈ \$${_availableUsd.toStringAsFixed(2)} USD",
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 22),

          // 2. Select Payout Destination Account
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Payout Destination Account",
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: ZevColors.deepNavy, letterSpacing: -0.2),
              ),
              GestureDetector(
                onTap: _showAddAccountSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 15, color: Color(0xFF0284C7)),
                      SizedBox(width: 2),
                      Text("+ Add", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: Color(0xFF0284C7))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_savedAccounts.isEmpty)
            GestureDetector(
              onTap: _showAddAccountSheet,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.85),
                          Colors.white.withValues(alpha: 0.60),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.35), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0284C7), size: 28),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "No Saved Payout Account Found",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: ZevColors.deepNavy),
                              ),
                              Text(
                                "Tap to add UK/US/EU Bank, HesabPay, Crypto or PayPal",
                                style: TextStyle(fontSize: 11.5, color: ZevColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: ZevColors.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            ..._savedAccounts.map((acc) {
              final isSelected = _selectedAccount?['id'] == acc['id'];
              final methodType = (acc['method_type'] ?? 'paypal').toString().toLowerCase();
              final currency = acc['currency'] ?? 'USD';

              IconData iconData = Icons.payments_rounded;
              Color iconColor = const Color(0xFF0284C7);
              String subtitle = '';

              if (methodType == 'hesabpay') {
                iconData = Icons.phone_android_rounded;
                iconColor = const Color(0xFFEF4444);
                subtitle = "HesabPay • ${acc['details']?['phone_number'] ?? ''}";
              } else if (methodType == 'crypto') {
                iconData = Icons.currency_bitcoin_rounded;
                iconColor = const Color(0xFFF59E0B);
                subtitle = "${acc['details']?['network'] ?? 'Crypto'} • ${acc['details']?['wallet_address'] ?? ''}";
              } else if (methodType == 'bank') {
                iconData = Icons.account_balance_rounded;
                iconColor = const Color(0xFF536DFE);
                final cur = acc['details']?['currency'] ?? currency;
                if (cur == 'GBP') {
                  subtitle = "${acc['details']?['bank_name'] ?? 'UK Bank'} • Sort: ${acc['details']?['sort_code'] ?? ''}";
                } else if (cur == 'USD') {
                  subtitle = "${acc['details']?['bank_name'] ?? 'US Bank'} • Routing: ${acc['details']?['routing_number'] ?? ''}";
                } else {
                  subtitle = "${acc['details']?['bank_name'] ?? 'EU Bank'} • IBAN: ${acc['details']?['iban'] ?? ''}";
                }
              } else if (methodType == 'paypal') {
                iconData = Icons.payment_rounded;
                iconColor = const Color(0xFF0284C7);
                subtitle = "PayPal • ${acc['details']?['email'] ?? ''}";
              }

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedAccount = acc;
                    _activeCurrency = currency;
                  });
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [
                                  Colors.white.withValues(alpha: 0.95),
                                  const Color(0xFFF0F9FF),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.82),
                                  Colors.white.withValues(alpha: 0.55),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF00D4FF) : Colors.white.withValues(alpha: 0.9),
                          width: isSelected ? 1.8 : 1.2,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF00D4FF).withValues(alpha: 0.20),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  iconColor.withValues(alpha: 0.18),
                                  iconColor.withValues(alpha: 0.06),
                                ],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                            ),
                            child: Icon(iconData, color: iconColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  acc['account_title'] ?? 'Saved Account',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: ZevColors.deepNavy),
                                ),
                                Text(
                                  subtitle,
                                  style: const TextStyle(fontSize: 11, color: ZevColors.textMuted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              currency,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: isSelected ? const Color(0xFF00D4FF) : const Color(0xFFCBD5E1),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

          const SizedBox(height: 18),

          // 3. Amount Input (Coins to Convert)
          const Text(
            "Coins to Convert & Withdraw",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text('🪙', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _coinsController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Min 700 coins",
                      hintStyle: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ),
                const Text(
                  "Coins",
                  style: TextStyle(fontWeight: FontWeight.w800, color: ZevColors.textMuted),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Quick Chip Amounts
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildQuickChip("700 (~\$9.90)", 700),
                _buildQuickChip("1,750 (~\$24.75)", 1750),
                _buildQuickChip("3,500 (~\$49.50)", 3500),
                _buildQuickChip("7,000 (~\$99.00)", 7000),
                _buildQuickChip("All Coins", _coinsBalance),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 4. Live Conversion Preview Box
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.88),
                      Colors.white.withValues(alpha: 0.62),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Estimated Payout Value:",
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ZevColors.textSecondary),
                        ),
                        Text(
                          "$currSymbol${convertedAmount.toStringAsFixed(2)} $targetCurrency",
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF0284C7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "USD Equivalent:",
                          style: TextStyle(fontSize: 11.5, color: ZevColors.textMuted),
                        ),
                        Text(
                          "\$${usdEquivalent.toStringAsFixed(2)} USD",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.deepNavy),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 5. Clearmorphic Submit Button
          GestureDetector(
            onTap: _isSubmitting ? null : _submitPayoutRequest,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF080D1A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.70),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.38),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Color(0xFF00D4FF), strokeWidth: 2.5),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, color: Color(0xFF00D4FF), size: 20),
                          SizedBox(width: 8),
                          Text(
                            "Submit Payout Request",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, int coins) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _setCoinAmount(coins),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: SAVED ACCOUNTS HUB (SCREENSHOT 2 REWRITE)
  // ===========================================================================
  Widget _buildSavedAccountsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Your Saved Payout Accounts",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: ZevColors.deepNavy, letterSpacing: -0.2),
              ),
              // Clearmorphic Add Button
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showAddAccountSheet();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D4FF), Color(0xFF0284C7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 4),
                      Text("Add Account", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_savedAccounts.isEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.85),
                        Colors.white.withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF00D4FF).withValues(alpha: 0.15),
                              const Color(0xFF0284C7).withValues(alpha: 0.05),
                            ],
                          ),
                          border: Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.account_balance_wallet_outlined, size: 32, color: Color(0xFF0284C7)),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "No Payout Accounts Saved Yet",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: ZevColors.deepNavy),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Save your HesabPay, Crypto wallet, Bank details or PayPal email to cash out your earnings seamlessly.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: ZevColors.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: _showAddAccountSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF080D1A), Color(0xFF1E293B)]),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.6), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D4FF).withValues(alpha: 0.3),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Text("Save New Account", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._savedAccounts.map((acc) {
              final id = acc['id'];
              final methodType = (acc['method_type'] ?? 'paypal').toString().toLowerCase();
              final title = acc['account_title'] ?? 'Account';
              final currency = acc['currency'] ?? 'USD';
              final details = Map<String, dynamic>.from(acc['details'] ?? {});

              IconData methodIcon;
              Color methodColor;
              String methodDisplay;

              if (methodType == 'hesabpay') {
                methodIcon = Icons.phone_android_rounded;
                methodColor = const Color(0xFFEF4444);
                methodDisplay = "HesabPay (AFN)";
              } else if (methodType == 'crypto') {
                methodIcon = Icons.currency_bitcoin_rounded;
                methodColor = const Color(0xFFF59E0B);
                methodDisplay = "Crypto (USDT)";
              } else if (methodType == 'bank') {
                methodIcon = Icons.account_balance_rounded;
                methodColor = const Color(0xFF536DFE);
                methodDisplay = "Bank Transfer";
              } else {
                methodIcon = Icons.payment_rounded;
                methodColor = const Color(0xFF0284C7);
                methodDisplay = "PayPal";
              }

              return ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.88),
                          Colors.white.withValues(alpha: 0.62),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.95),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.07),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        methodColor.withValues(alpha: 0.18),
                                        methodColor.withValues(alpha: 0.06),
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: methodColor.withValues(alpha: 0.35),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Icon(methodIcon, size: 22, color: methodColor),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: ZevColors.deepNavy,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      methodDisplay,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: ZevColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Clearmorphic Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF00D4FF).withValues(alpha: 0.15),
                                    const Color(0xFF536DFE).withValues(alpha: 0.08),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFF00D4FF).withValues(alpha: 0.40),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                "$currency • ${methodType.toUpperCase()}",
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0284C7),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Frosted Details Container (NO ugly black line!)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (methodType == 'hesabpay') ...[
                                _buildDetailRow("Phone", details['phone_number'] ?? ''),
                                const SizedBox(height: 4),
                                _buildDetailRow("Account Holder", details['account_name'] ?? ''),
                              ] else if (methodType == 'crypto') ...[
                                _buildDetailRow("Network", details['network'] ?? 'TRC-20'),
                                const SizedBox(height: 4),
                                _buildDetailRow("Wallet Address", details['wallet_address'] ?? ''),
                                if (details['memo'] != null && details['memo'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _buildDetailRow("Memo / Tag", details['memo']),
                                ],
                              ] else if (methodType == 'bank') ...[
                                if ((details['currency'] ?? currency) == 'GBP') ...[
                                  _buildDetailRow("Bank", "${details['bank_name'] ?? ''} (UK Faster Payments)"),
                                  const SizedBox(height: 4),
                                  _buildDetailRow("Sort Code", details['sort_code'] ?? ''),
                                  const SizedBox(height: 4),
                                  _buildDetailRow("Account Number", details['account_number'] ?? ''),
                                ] else if ((details['currency'] ?? currency) == 'USD') ...[
                                  _buildDetailRow("Bank", "${details['bank_name'] ?? ''} (US ACH/Fedwire)"),
                                  const SizedBox(height: 4),
                                  _buildDetailRow("ABA Routing", details['routing_number'] ?? ''),
                                  const SizedBox(height: 4),
                                  _buildDetailRow("Account", "${details['account_number'] ?? ''} (${details['account_type'] ?? 'Checking'})"),
                                ] else ...[
                                  _buildDetailRow("Bank", "${details['bank_name'] ?? ''} (SEPA Europe)"),
                                  const SizedBox(height: 4),
                                  _buildDetailRow("IBAN", details['iban'] ?? ''),
                                  const SizedBox(height: 4),
                                  _buildDetailRow("SWIFT / BIC", details['swift_bic'] ?? ''),
                                ],
                                const SizedBox(height: 4),
                                _buildDetailRow("Account Holder", details['account_holder'] ?? ''),
                              ] else if (methodType == 'paypal') ...[
                                _buildDetailRow("PayPal Email", details['email'] ?? ''),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Action Row with Elegant Glass Remove Pill
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () => _deleteAccount(id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFEF4444)),
                                    SizedBox(width: 4),
                                    Text(
                                      "Remove",
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFEF4444),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ZevColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: PAYOUT HISTORY
  // ===========================================================================
  Widget _buildHistoryTab() {
    if (_payoutHistory.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(40),
          children: const [
            Center(
              child: Text(
                "No payout requests submitted yet.",
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _payoutHistory.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _payoutHistory[index];
          final coins = (item['coins_deducted'] as num?)?.toInt() ?? 0;
          final amountUsd = (item['amount_usd'] as num?)?.toDouble() ?? 0.0;
          final targetCurrency = (item['target_currency'] ?? 'USD').toString();
          final amountTarget = (item['amount_target_currency'] as num?)?.toDouble() ?? amountUsd;
          final method = (item['payout_method'] ?? 'paypal').toString().toUpperCase();
          final destination = (item['destination_account'] ?? '').toString();
          final status = (item['status'] ?? 'pending').toString().toLowerCase();
          final createdAt = item['created_at'] != null
              ? DateTime.tryParse(item['created_at'].toString())
              : null;

          Color badgeBg;
          Color badgeText;
          String statusLabel;

          if (status == 'completed' || status == 'paid') {
            badgeBg = const Color(0xFFE0F2FE);
            badgeText = const Color(0xFF0284C7);
            statusLabel = "Completed / Paid";
          } else if (status == 'processing') {
            badgeBg = const Color(0xFFFEF3C7);
            badgeText = const Color(0xFFD97706);
            statusLabel = "In Processing";
          } else if (status == 'rejected') {
            badgeBg = const Color(0xFFFEE2E2);
            badgeText = ZevColors.errorRed;
            statusLabel = "Rejected / Refunded";
          } else {
            badgeBg = const Color(0xFFFEF3C7);
            badgeText = const Color(0xFFD97706);
            statusLabel = "Pending Review";
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.88),
                      Colors.white.withValues(alpha: 0.62),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "$method Payout",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: ZevColors.deepNavy),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: badgeText),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${amountTarget.toStringAsFixed(2)} $targetCurrency",
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
                        ),
                        if (coins > 0)
                          Text(
                            "$coins Coins",
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0284C7)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Destination: $destination",
                      style: const TextStyle(fontSize: 12, color: ZevColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Requested: ${createdAt.toLocal().toString().substring(0, 16)}",
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                    if (status == 'pending' || status == 'processing') ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => _cancelPayoutRequest(item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel_outlined, size: 14, color: ZevColors.errorRed),
                                SizedBox(width: 4),
                                Text("Cancel & Refund", style: TextStyle(color: ZevColors.errorRed, fontWeight: FontWeight.w800, fontSize: 11.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// CLEARMORPHIC DRAWER: ADD SAVED PAYOUT METHOD (SCREENSHOT 1 REWRITE)
// =============================================================================
class _ClearmorphicAddAccountDrawer extends StatefulWidget {
  final VoidCallback onAccountCreated;

  const _ClearmorphicAddAccountDrawer({required this.onAccountCreated});

  @override
  State<_ClearmorphicAddAccountDrawer> createState() => _ClearmorphicAddAccountDrawerState();
}

class _ClearmorphicAddAccountDrawerState extends State<_ClearmorphicAddAccountDrawer> {
  final _client = Supabase.instance.client;
  String _selectedType = 'bank'; // bank, hesabpay, crypto, paypal

  // Common title
  final _titleController = TextEditingController();

  // Dynamic International Banking State
  String _bankCurrency = 'GBP'; // 'GBP', 'USD', 'EUR'
  final _bankNameController = TextEditingController();
  final _bankHolderController = TextEditingController();

  // GBP Fields
  final _ukSortCodeController = TextEditingController();
  final _ukAccountNumberController = TextEditingController();

  // USD Fields
  final _usRoutingNumberController = TextEditingController();
  final _usAccountNumberController = TextEditingController();
  String _usAccountType = 'Checking';

  // EUR Fields
  final _euIbanController = TextEditingController();
  final _euSwiftBicController = TextEditingController();

  // HesabPay State
  final _hesabPhoneController = TextEditingController();
  final _hesabNameController = TextEditingController();

  // Crypto State
  String _cryptoNetwork = 'TRC-20 (Tron) - Low Fee / Recommended';
  final _cryptoAddressController = TextEditingController();
  final _cryptoMemoController = TextEditingController();

  // PayPal State
  String _paypalCurrency = 'USD';
  final _paypalEmailController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bankNameController.dispose();
    _bankHolderController.dispose();
    _ukSortCodeController.dispose();
    _ukAccountNumberController.dispose();
    _usRoutingNumberController.dispose();
    _usAccountNumberController.dispose();
    _euIbanController.dispose();
    _euSwiftBicController.dispose();
    _hesabPhoneController.dispose();
    _hesabNameController.dispose();
    _cryptoAddressController.dispose();
    _cryptoMemoController.dispose();
    _paypalEmailController.dispose();
    super.dispose();
  }

  Future<void> _saveAccount() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      String currency = 'USD';
      Map<String, dynamic> details = {};
      String defaultTitle = '';

      if (_selectedType == 'bank') {
        final bankName = _bankNameController.text.trim();
        final holder = _bankHolderController.text.trim();
        currency = _bankCurrency;

        if (holder.isEmpty) throw 'Please enter the Account Holder Name.';
        if (bankName.isEmpty) throw 'Please enter the Bank Name.';

        if (_bankCurrency == 'GBP') {
          final sortCode = _ukSortCodeController.text.trim().replaceAll(' ', '');
          final accNum = _ukAccountNumberController.text.trim().replaceAll(' ', '');

          if (sortCode.isEmpty || sortCode.length < 6) {
            throw 'Please enter a valid 6-digit UK Sort Code (e.g. 12-34-56).';
          }
          if (accNum.isEmpty || accNum.length != 8) {
            throw 'Please enter a valid 8-digit UK Account Number.';
          }

          details = {
            'region': 'UK',
            'currency': 'GBP',
            'bank_name': bankName,
            'account_holder': holder,
            'sort_code': sortCode,
            'account_number': accNum,
          };
          defaultTitle = '$bankName UK ($sortCode)';
        } else if (_bankCurrency == 'USD') {
          final routing = _usRoutingNumberController.text.trim().replaceAll(' ', '');
          final accNum = _usAccountNumberController.text.trim().replaceAll(' ', '');

          if (routing.isEmpty || routing.length != 9) {
            throw 'Please enter a valid 9-digit ABA Routing Transit Number.';
          }
          if (accNum.isEmpty || accNum.length < 4) {
            throw 'Please enter a valid US Account Number.';
          }

          details = {
            'region': 'USA',
            'currency': 'USD',
            'bank_name': bankName,
            'account_holder': holder,
            'routing_number': routing,
            'account_number': accNum,
            'account_type': _usAccountType,
          };
          defaultTitle = '$bankName US ($accNum)';
        } else {
          final iban = _euIbanController.text.trim().replaceAll(' ', '').toUpperCase();
          final swift = _euSwiftBicController.text.trim().replaceAll(' ', '').toUpperCase();

          if (iban.isEmpty || iban.length < 15) {
            throw 'Please enter a valid European IBAN (e.g. DE89...).';
          }
          if (swift.isEmpty || (swift.length != 8 && swift.length != 11)) {
            throw 'Please enter a valid SWIFT/BIC code (8 or 11 characters).';
          }

          details = {
            'region': 'EU',
            'currency': 'EUR',
            'bank_name': bankName,
            'account_holder': holder,
            'iban': iban,
            'swift_bic': swift,
          };
          defaultTitle = '$bankName EU (${iban.substring(0, 4)}...)';
        }
      } else if (_selectedType == 'hesabpay') {
        final phone = _hesabPhoneController.text.trim();
        final name = _hesabNameController.text.trim();
        currency = 'AFN';

        if (phone.isEmpty || phone.length < 9) {
          throw 'Please enter a valid Afghan phone number registered with HesabPay.';
        }
        if (name.isEmpty) {
          throw 'Please enter the Account Holder name.';
        }

        details = {
          'phone_number': phone,
          'account_name': name,
          'currency': 'AFN',
        };
        defaultTitle = 'HesabPay ($phone)';
      } else if (_selectedType == 'crypto') {
        final address = _cryptoAddressController.text.trim();
        final memo = _cryptoMemoController.text.trim();
        currency = 'USD';

        if (address.isEmpty || address.length < 10) {
          throw 'Please enter a valid USDT crypto wallet address.';
        }

        details = {
          'network': _cryptoNetwork,
          'wallet_address': address,
          'memo': memo.isNotEmpty ? memo : null,
          'currency': 'USD',
        };
        final shortAddr = address.length > 8 ? '${address.substring(0, 4)}...${address.substring(address.length - 4)}' : address;
        defaultTitle = 'Crypto $shortAddr (${_cryptoNetwork.split(' ').first})';
      } else if (_selectedType == 'paypal') {
        final email = _paypalEmailController.text.trim();
        currency = _paypalCurrency;

        if (email.isEmpty || !email.contains('@')) {
          throw 'Please enter a valid PayPal account email address.';
        }

        details = {
          'email': email,
          'currency': _paypalCurrency,
        };
        defaultTitle = 'PayPal ($email)';
      }

      final customTitle = _titleController.text.trim();

      await _client.from('user_payout_methods').insert({
        'user_id': user.id,
        'method_type': _selectedType,
        'account_title': customTitle.isNotEmpty ? customTitle : defaultTitle,
        'currency': currency,
        'details': details,
        'is_default': true,
      });

      widget.onAccountCreated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: ZevColors.errorRed),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: ZevColors.deepNavy,
        letterSpacing: -0.1,
      ),
    );
  }

  Widget _buildClearmorphicInput({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(
          color: ZevColors.deepNavy,
          fontWeight: FontWeight.w800,
          fontSize: 13.5,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF00D4FF), width: 1.8),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeTab(String type, String emoji, String label) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedType = type);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF080D1A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.85),
                    Colors.white.withValues(alpha: 0.55),
                  ],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00D4FF)
                : Colors.white.withValues(alpha: 0.9),
            width: isSelected ? 1.6 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_circle_rounded, color: Color(0xFF00D4FF), size: 16),
              const SizedBox(width: 6),
            ],
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? Colors.white : ZevColors.deepNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencySegment(String cur, String label) {
    final isSelected = _bankCurrency == cur;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _bankCurrency = cur);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Colors.white, Color(0xFFF8FAFC)],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.4))
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? ZevColors.deepNavy : ZevColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPayPalCurrencyChip(String cur, String label) {
    final isSelected = _paypalCurrency == cur;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _paypalCurrency = cur);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Colors.white, Color(0xFFF8FAFC)],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.4))
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? ZevColors.deepNavy : ZevColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.96),
                const Color(0xFFF8FAFC).withValues(alpha: 0.94),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.98),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.20),
                blurRadius: 40,
                offset: const Offset(0, -10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drawer Drag Handle
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header & Glass Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Add Payout Method",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        color: ZevColors.deepNavy,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: ZevColors.deepNavy),
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Method Selector Chips (4 Clearmorphic Capsules)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildTypeTab('bank', '🏦', 'Bank Transfer'),
                      _buildTypeTab('hesabpay', '📱', 'HesabPay (AFN)'),
                      _buildTypeTab('crypto', '⛓', 'Crypto (USDT)'),
                      _buildTypeTab('paypal', '🅿️', 'PayPal'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // =============================================================
                // 1. BANK TRANSFER
                // =============================================================
                if (_selectedType == 'bank') ...[
                  // Dynamic Currency Segment
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0).withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    child: Row(
                      children: [
                        _buildCurrencySegment('GBP', '🇬🇧 GBP (UK)'),
                        _buildCurrencySegment('USD', '🇺🇸 USD (USA)'),
                        _buildCurrencySegment('EUR', '🇪🇺 EUR (Europe)'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildFieldLabel("Bank Name"),
                  const SizedBox(height: 6),
                  _buildClearmorphicInput(
                    controller: _bankNameController,
                    hintText: _bankCurrency == 'GBP'
                        ? "e.g. Barclays, HSBC, Monzo, Revolut"
                        : _bankCurrency == 'USD'
                            ? "e.g. Chase, Bank of America, Wells Fargo"
                            : "e.g. Deutsche Bank, BNP Paribas, Santander",
                  ),
                  const SizedBox(height: 12),

                  _buildFieldLabel("Account Holder Full Name"),
                  const SizedBox(height: 6),
                  _buildClearmorphicInput(
                    controller: _bankHolderController,
                    hintText: "Full legal name as registered on bank account",
                  ),
                  const SizedBox(height: 12),

                  // IF GBP
                  if (_bankCurrency == 'GBP') ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel("UK Sort Code"),
                              const SizedBox(height: 6),
                              _buildClearmorphicInput(
                                controller: _ukSortCodeController,
                                hintText: "XX-XX-XX",
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel("UK Account Number (8 Digits)"),
                              const SizedBox(height: 6),
                              _buildClearmorphicInput(
                                controller: _ukAccountNumberController,
                                hintText: "12345678",
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF0284C7)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Transferred natively via UK Faster Payments (same-day settlement).",
                            style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ]

                  // IF USD
                  else if (_bankCurrency == 'USD') ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel("ABA Routing (9 Digits)"),
                              const SizedBox(height: 6),
                              _buildClearmorphicInput(
                                controller: _usRoutingNumberController,
                                hintText: "021000021",
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel("Account Type"),
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00D4FF).withValues(alpha: 0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _usAccountType,
                                  items: const [
                                    DropdownMenuItem(value: 'Checking', child: Text('Checking (جاری)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                                    DropdownMenuItem(value: 'Savings', child: Text('Savings (پس‌انداز)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                                  ],
                                  onChanged: (v) => setState(() => _usAccountType = v!),
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildFieldLabel("US Bank Account Number"),
                    const SizedBox(height: 6),
                    _buildClearmorphicInput(
                      controller: _usAccountNumberController,
                      hintText: "Enter checking or savings account number",
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF0284C7)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Transferred natively via US Fedwire or ACH Direct Deposit.",
                            style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ]

                  // IF EUR
                  else if (_bankCurrency == 'EUR') ...[
                    _buildFieldLabel("European IBAN (International Bank Account Number)"),
                    const SizedBox(height: 6),
                    _buildClearmorphicInput(
                      controller: _euIbanController,
                      hintText: "DE89 3704 0044 0532 0130 00",
                    ),
                    const SizedBox(height: 12),
                    _buildFieldLabel("SWIFT / BIC Code (8 or 11 characters)"),
                    const SizedBox(height: 6),
                    _buildClearmorphicInput(
                      controller: _euSwiftBicController,
                      hintText: "DEUTDEDDXXX",
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF0284C7)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Transferred natively via SEPA (Single Euro Payments Area).",
                            style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ]

                // =============================================================
                // 2. HESABPAY (AFN)
                // =============================================================
                else if (_selectedType == 'hesabpay') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFEF4444).withValues(alpha: 0.12),
                          const Color(0xFFEF4444).withValues(alpha: 0.04),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: Color(0xFFEF4444), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Direct AFN payouts to your Afghan HesabPay mobile wallet.",
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF991B1B), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFieldLabel("HesabPay Registered Phone Number"),
                  const SizedBox(height: 6),
                  _buildClearmorphicInput(
                    controller: _hesabPhoneController,
                    hintText: "079XXXXXXX or +93 7X XXX XXXX",
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _buildFieldLabel("Account Holder Full Name (as in HesabPay)"),
                  const SizedBox(height: 6),
                  _buildClearmorphicInput(
                    controller: _hesabNameController,
                    hintText: "Full name registered on HesabPay",
                  ),
                ]

                // =============================================================
                // 3. CRYPTO (USDT Multi-Chain)
                // =============================================================
                else if (_selectedType == 'crypto') ...[
                  _buildFieldLabel("Select Blockchain Network (USDT)"),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: DropdownButtonFormField<String>(
                      initialValue: _cryptoNetwork,
                      isExpanded: true,
                      items: ZevPayoutScreen.kCryptoNetworks
                          .map((net) => DropdownMenuItem(
                                value: net,
                                child: Text(net, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _cryptoNetwork = v!),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFieldLabel("Your USDT Wallet Address"),
                  const SizedBox(height: 6),
                  _buildClearmorphicInput(
                    controller: _cryptoAddressController,
                    hintText: "Enter your wallet deposit address",
                  ),
                  const SizedBox(height: 12),
                  _buildFieldLabel("Destination Tag / Memo (Optional)"),
                  const SizedBox(height: 6),
                  _buildClearmorphicInput(
                    controller: _cryptoMemoController,
                    hintText: "Leave blank if not required by your wallet/exchange",
                  ),
                ]

                // =============================================================
                // 4. PAYPAL
                // =============================================================
                else if (_selectedType == 'paypal') ...[
                  _buildFieldLabel("Select PayPal Payout Currency"),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0).withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    child: Row(
                      children: [
                        _buildPayPalCurrencyChip('USD', '\$ USD'),
                        _buildPayPalCurrencyChip('EUR', '€ EUR'),
                        _buildPayPalCurrencyChip('GBP', '£ GBP'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFieldLabel("PayPal Account Email"),
                  const SizedBox(height: 6),
                  _buildClearmorphicInput(
                    controller: _paypalEmailController,
                    hintText: "your.email@example.com",
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],

                const SizedBox(height: 14),

                // Common Custom Label / Nickname
                _buildFieldLabel("Custom Label / Nickname (Optional)"),
                const SizedBox(height: 6),
                _buildClearmorphicInput(
                  controller: _titleController,
                  hintText: "e.g. My UK Revolut or Primary HesabPay",
                ),

                const SizedBox(height: 24),

                // Clearmorphic Save Action Button
                GestureDetector(
                  onTap: _isSaving ? null : _saveAccount,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF080D1A), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.70),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.38),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Color(0xFF00D4FF), strokeWidth: 2.5),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_outlined, color: Color(0xFF00D4FF), size: 18),
                                SizedBox(width: 8),
                                Text(
                                  "Save Payout Account",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
