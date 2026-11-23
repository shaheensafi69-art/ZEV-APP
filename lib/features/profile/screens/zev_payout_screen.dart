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
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch latest profile balances
      final profile = await _client
          .from('profiles')
          .select('coins_balance, earnings_usd, earnings_coins')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null && mounted) {
        final coins = (profile['coins_balance'] as num?)?.toInt() ?? 0;
        final usd = (profile['earnings_usd'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          _coinsBalance = coins;
          _availableUsd = usd > 0 ? usd : (coins * kUsdPerCoin);
        });
      }

      // 2. Fetch saved payout methods
      final methods = await _client
          .from('user_payout_methods')
          .select('*')
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      // 3. Fetch payout history
      final history = await _client
          .from('payout_requests')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        final accountsList = List<Map<String, dynamic>>.from(methods);
        setState(() {
          _savedAccounts = accountsList;
          if (_selectedAccount == null && accountsList.isNotEmpty) {
            _selectedAccount = accountsList.first;
            _activeCurrency = _selectedAccount!['currency'] ?? 'USD';
          }
          _payoutHistory = List<Map<String, dynamic>>.from(history);
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

    // Clearmorphic Confirmation Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: const Row(
          children: [
            Text('💎', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'Confirm Withdrawal',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: ZevColors.deepNavy,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are converting $coinsToRedeem Coins into $currSymbol${amountTarget.toStringAsFixed(2)} $targetCurrency (~\$${amountUsd.toStringAsFixed(2)} USD).',
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155), height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ZevColors.softSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ZevColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Destination ($accountTitle):',
                    style: const TextStyle(fontSize: 11, color: ZevColors.textMuted, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destinationAccount,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: ZevColors.deepNavy),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Method: ${methodType.toUpperCase()} • 0% Platform Fee',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: ZevColors.textMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.deepNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Cashout', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      // 1. Insert into payout_requests with status 'processing'
      final insertRes = await _client.from('payout_requests').insert({
        'user_id': user.id,
        'coins_deducted': coinsToRedeem,
        'amount_usd': amountUsd,
        'target_currency': targetCurrency,
        'amount_target_currency': amountTarget,
        'payout_method': methodType,
        'destination_account': destinationAccount,
        'account_details': accountDetails,
        'payout_method_id': _selectedAccount!['id'],
        'status': 'processing',
      }).select().single();

      final requestId = insertRes['id']?.toString() ?? 'REQ-${DateTime.now().millisecondsSinceEpoch}';

      // 2. Atomically deduct coins from profile
      final newCoinsBalance = (_coinsBalance - coinsToRedeem).clamp(0, 999999999);
      final newEarningsUsd = (_availableUsd - amountUsd).clamp(0.0, 999999999.0);

      await _client.from('profiles').update({
        'coins_balance': newCoinsBalance,
        'earnings_usd': newEarningsUsd,
      }).eq('id', user.id);

      // 3. Fetch user profile names for telegram dispatch
      final profileData = await _client
          .from('profiles')
          .select('username, first_name, last_name')
          .eq('id', user.id)
          .maybeSingle();

      final username = profileData?['username'] ?? 'User';
      final fullName = "${profileData?['first_name'] ?? ''} ${profileData?['last_name'] ?? ''}".trim();

      // 4. Dispatch Telegram Bot Notification to @zevpayout_bot
      try {
        await TelegramNotificationService.sendPayoutRequestNotification(
          requestId: requestId,
          userId: user.id,
          username: username,
          fullName: fullName.isNotEmpty ? fullName : username,
          coinsDeducted: coinsToRedeem,
          amountUsd: amountUsd,
          targetCurrency: targetCurrency,
          amountTargetCurrency: amountTarget,
          payoutMethod: methodType,
          destinationAccount: destinationAccount,
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
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "Cancel Payout Request?",
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: ZevColors.deepNavy),
        ),
        content: Text(
          "Cancelling this request will immediately refund ${coins > 0 ? '$coins Coins' : '\$$amountUsd USD'} back to your wallet.",
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
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, Cancel & Refund"),
          ),
        ],
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
      builder: (ctx) => _ClearmorphicAddAccountDrawer(
        onAccountCreated: () {
          Navigator.pop(ctx);
          _loadData();
          _showToast('Payout account saved successfully!', isError: false);
        },
      ),
    );
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
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
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
      body: SafeArea(
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Clearmorphic Balance Header Card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.08),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(8),
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
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
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

          const SizedBox(height: 22),

          // 2. Select Payout Account
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Payout Destination Account",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
              ),
              TextButton.icon(
                onPressed: _showAddAccountSheet,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text("+ Add Account", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_savedAccounts.isEmpty)
            GestureDetector(
              onTap: _showAddAccountSheet,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.35), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0284C7), size: 30),
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
                            "Tap to save HesabPay, Crypto wallet, Bank details or PayPal",
                            style: TextStyle(fontSize: 11.5, color: ZevColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: ZevColors.textMuted),
                  ],
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
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0284C7) : ZevColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? const Color(0xFF0284C7).withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
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
                          color: const Color(0xFFF1F5F9),
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
                        color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                        size: 22,
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 18),

          // 3. Amount Input (Coins to Cash)
          const Text(
            "Coins to Convert & Withdraw",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                const Text('🪙', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _coinsController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Min 700 coins",
                    ),
                  ),
                ),
                Text(
                  "Coins",
                  style: const TextStyle(fontWeight: FontWeight.w800, color: ZevColors.textMuted),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Quick Chip Amounts
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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

          // 4. Live Conversion Preview
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ZevColors.border),
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

          const SizedBox(height: 24),

          // 5. Submit Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.deepNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 3,
            ),
            onPressed: _isSubmitting ? null : _submitPayoutRequest,
            child: _isSubmitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Submit Payout Request",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ],
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
      child: ActionChip(
        label: Text(label),
        labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
        backgroundColor: Colors.white,
        side: const BorderSide(color: ZevColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onPressed: () => _setCoinAmount(coins),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: SAVED ACCOUNTS HUB
  // ===========================================================================
  Widget _buildSavedAccountsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Your Saved Payout Accounts",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
              ),
              ElevatedButton.icon(
                onPressed: _showAddAccountSheet,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text("Add Account"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_savedAccounts.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ZevColors.border),
              ),
              child: Column(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 48, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 12),
                  const Text(
                    "No Payout Accounts Saved Yet",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: ZevColors.deepNavy),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Save your HesabPay, Crypto wallet, Bank details or PayPal email to cash out your earnings seamlessly.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: ZevColors.textMuted),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _showAddAccountSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.deepNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("Save New Account", style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            )
          else
            ..._savedAccounts.map((acc) {
              final id = acc['id'];
              final methodType = (acc['method_type'] ?? 'paypal').toString().toLowerCase();
              final title = acc['account_title'] ?? 'Account';
              final currency = acc['currency'] ?? 'USD';
              final details = Map<String, dynamic>.from(acc['details'] ?? {});

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ZevColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
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
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: ZevColors.deepNavy),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBAE6FD)),
                          ),
                          child: Text(
                            "$currency • ${methodType.toUpperCase()}",
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF0284C7)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (methodType == 'hesabpay') ...[
                      Text("Phone: ${details['phone_number'] ?? ''}", style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                      Text("Name: ${details['account_name'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: ZevColors.textMuted)),
                    ] else if (methodType == 'crypto') ...[
                      Text("Network: ${details['network'] ?? 'TRC-20'}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      Text("Address: ${details['wallet_address'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: ZevColors.textMuted)),
                    ] else if (methodType == 'bank') ...[
                      if ((details['currency'] ?? currency) == 'GBP') ...[
                        Text("Bank: ${details['bank_name'] ?? ''} (UK Faster Payments)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                        Text("Sort Code: ${details['sort_code'] ?? ''} • Account: ${details['account_number'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: ZevColors.textMuted)),
                      ] else if ((details['currency'] ?? currency) == 'USD') ...[
                        Text("Bank: ${details['bank_name'] ?? ''} (US ACH/Fedwire)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                        Text("ABA Routing: ${details['routing_number'] ?? ''} • Account: ${details['account_number'] ?? ''} (${details['account_type'] ?? 'Checking'})", style: const TextStyle(fontSize: 11.5, color: ZevColors.textMuted)),
                      ] else ...[
                        Text("Bank: ${details['bank_name'] ?? ''} (SEPA Europe)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                        Text("IBAN: ${details['iban'] ?? ''} • SWIFT: ${details['swift_bic'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: ZevColors.textMuted)),
                      ],
                      Text("Holder: ${details['account_holder'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: ZevColors.textMuted)),
                    ] else if (methodType == 'paypal') ...[
                      Text("Email: ${details['email'] ?? ''}", style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                    ],
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final del = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Delete Account?"),
                                content: const Text("Are you sure you want to remove this saved payout method?"),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: ZevColors.errorRed),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text("Delete", style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            if (del == true) {
                              await _client.from('user_payout_methods').delete().eq('id', id);
                              _loadData();
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: ZevColors.errorRed),
                          label: const Text("Remove", style: TextStyle(color: ZevColors.errorRed, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
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

          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ZevColors.border),
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
                  const Divider(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _cancelPayoutRequest(item),
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: ZevColors.errorRed),
                      label: const Text("Cancel & Refund", style: TextStyle(color: ZevColors.errorRed, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// EXCLUSIVE CLEARMORPHIC DRAWER WITH AUTOMATIC INTERNATIONAL BANKING LOGIC
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

  // ---------------------------------------------------------------------------
  // 1. DYNAMIC INTERNATIONAL BANKING STATE
  // Automatically switches fields based on currency: GBP, USD, EUR
  // ---------------------------------------------------------------------------
  String _bankCurrency = 'GBP'; // 'GBP', 'USD', 'EUR'
  final _bankNameController = TextEditingController();
  final _bankHolderController = TextEditingController();

  // GBP Fields (United Kingdom)
  final _ukSortCodeController = TextEditingController();
  final _ukAccountNumberController = TextEditingController();

  // USD Fields (United States)
  final _usRoutingNumberController = TextEditingController();
  final _usAccountNumberController = TextEditingController();
  String _usAccountType = 'Checking'; // Checking or Savings

  // EUR Fields (Europe SEPA)
  final _euIbanController = TextEditingController();
  final _euSwiftBicController = TextEditingController();

  // ---------------------------------------------------------------------------
  // 2. HESABPAY STATE (AFN Only)
  // ---------------------------------------------------------------------------
  final _hesabPhoneController = TextEditingController();
  final _hesabNameController = TextEditingController();

  // ---------------------------------------------------------------------------
  // 3. CRYPTO STATE (USDT Multi-Chain)
  // ---------------------------------------------------------------------------
  String _cryptoNetwork = 'TRC-20 (Tron) - Low Fee / Recommended';
  final _cryptoAddressController = TextEditingController();
  final _cryptoMemoController = TextEditingController();

  // ---------------------------------------------------------------------------
  // 4. PAYPAL STATE
  // ---------------------------------------------------------------------------
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

      // -----------------------------------------------------------------------
      // 1. BANK TRANSFER (GBP, USD, EUR International Specs)
      // -----------------------------------------------------------------------
      if (_selectedType == 'bank') {
        final bankName = _bankNameController.text.trim();
        final holder = _bankHolderController.text.trim();
        currency = _bankCurrency;

        if (holder.isEmpty) throw 'Please enter the Account Holder Name.';
        if (bankName.isEmpty) throw 'Please enter the Bank Name.';

        if (_bankCurrency == 'GBP') {
          // UK Banking Validation: 6-digit Sort Code, 8-digit Account Number
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
          // US Banking Validation: 9-digit ABA Routing, Account Number, Type
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
          defaultTitle = '$bankName US ($_usAccountType)';
        } else if (_bankCurrency == 'EUR') {
          // Europe SEPA Validation: IBAN + SWIFT/BIC
          final iban = _euIbanController.text.trim().replaceAll(' ', '').toUpperCase();
          final swift = _euSwiftBicController.text.trim().replaceAll(' ', '').toUpperCase();

          if (iban.isEmpty || iban.length < 15) {
            throw 'Please enter a valid European IBAN (e.g. DE..., FR..., ES...).';
          }
          if (swift.isEmpty || (swift.length != 8 && swift.length != 11)) {
            throw 'Please enter a valid 8 or 11 character SWIFT/BIC Code.';
          }

          details = {
            'region': 'Europe',
            'currency': 'EUR',
            'bank_name': bankName,
            'account_holder': holder,
            'iban': iban,
            'swift_bic': swift,
          };
          defaultTitle = '$bankName EU (IBAN)';
        }
      }

      // -----------------------------------------------------------------------
      // 2. HESABPAY (AFN)
      // -----------------------------------------------------------------------
      else if (_selectedType == 'hesabpay') {
        final phone = _hesabPhoneController.text.trim();
        final name = _hesabNameController.text.trim();
        if (phone.isEmpty) throw 'Please enter your HesabPay mobile phone number.';
        currency = 'AFN';
        details = {
          'phone_number': phone,
          'account_name': name,
          'currency': 'AFN',
        };
        defaultTitle = 'HesabPay ($phone)';
      }

      // -----------------------------------------------------------------------
      // 3. CRYPTO (USDT Multi-Chain)
      // -----------------------------------------------------------------------
      else if (_selectedType == 'crypto') {
        final address = _cryptoAddressController.text.trim();
        if (address.isEmpty || address.length < 20) throw 'Please enter a valid crypto wallet address.';
        currency = 'USDT';
        details = {
          'network': _cryptoNetwork,
          'wallet_address': address,
          'memo_tag': _cryptoMemoController.text.trim(),
          'currency': 'USDT',
        };
        defaultTitle = 'Crypto (${_cryptoNetwork.split(' ').first})';
      }

      // -----------------------------------------------------------------------
      // 4. PAYPAL
      // -----------------------------------------------------------------------
      else if (_selectedType == 'paypal') {
        final email = _paypalEmailController.text.trim();
        if (email.isEmpty || !email.contains('@')) throw 'Please enter a valid PayPal email address.';
        currency = _paypalCurrency;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drawer Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Add Payout Method",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: ZevColors.deepNavy),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: ZevColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Top Method Selector (4 Segmented Chips)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTypeTab('bank', '🏦 Bank Transfer'),
                  _buildTypeTab('hesabpay', '📱 HesabPay (AFN)'),
                  _buildTypeTab('crypto', '⛓ Crypto (USDT)'),
                  _buildTypeTab('paypal', '🅿️ PayPal'),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // =================================================================
            // 1. DYNAMIC BANK TRANSFER SECTION
            // =================================================================
            if (_selectedType == 'bank') ...[
              // Currency Switcher: GBP, USD, EUR
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
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

              // Common Bank Name & Holder
              const Text("Bank Name", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _bankNameController,
                decoration: InputDecoration(
                  hintText: _bankCurrency == 'GBP'
                      ? "e.g. Barclays, HSBC, Monzo, Revolut"
                      : _bankCurrency == 'USD'
                          ? "e.g. Chase, Bank of America, Wells Fargo"
                          : "e.g. Deutsche Bank, BNP Paribas, Santander",
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
              const SizedBox(height: 12),

              const Text("Account Holder Full Name", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _bankHolderController,
                decoration: InputDecoration(
                  hintText: "Full legal name as registered on bank account",
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
              const SizedBox(height: 12),

              // ---------------------------------------------------------------
              // IF GBP: UK SORT CODE + 8-DIGIT ACCOUNT NUMBER
              // ---------------------------------------------------------------
              if (_bankCurrency == 'GBP') ...[
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("UK Sort Code", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _ukSortCodeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: "XX-XX-XX",
                              filled: true,
                              fillColor: ZevColors.softSurface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                            ),
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
                          const Text("UK Account Number (8 Digits)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _ukAccountNumberController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: "12345678",
                              filled: true,
                              fillColor: ZevColors.softSurface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "ℹ️ Transferred natively via UK Faster Payments (same-day settlement).",
                  style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                ),
              ]

              // ---------------------------------------------------------------
              // IF USD: 9-DIGIT ABA ROUTING + ACCOUNT NUMBER + ACCOUNT TYPE
              // ---------------------------------------------------------------
              else if (_bankCurrency == 'USD') ...[
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("ABA Routing (9 Digits)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _usRoutingNumberController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: "021000021",
                              filled: true,
                              fillColor: ZevColors.softSurface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                            ),
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
                          const Text("Account Type", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _usAccountType,
                            items: const [
                              DropdownMenuItem(value: 'Checking', child: Text('Checking (جاری)')),
                              DropdownMenuItem(value: 'Savings', child: Text('Savings (پس‌انداز)')),
                            ],
                            onChanged: (v) => setState(() => _usAccountType = v!),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: ZevColors.softSurface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text("US Bank Account Number", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _usAccountNumberController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "Enter checking or savings account number",
                    filled: true,
                    fillColor: ZevColors.softSurface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "ℹ️ Transferred natively via US Fedwire or ACH Direct Deposit.",
                  style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                ),
              ]

              // ---------------------------------------------------------------
              // IF EUR: SEPA IBAN + SWIFT/BIC
              // ---------------------------------------------------------------
              else if (_bankCurrency == 'EUR') ...[
                const Text("European IBAN (International Bank Account Number)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _euIbanController,
                  decoration: InputDecoration(
                    hintText: "DE89 3704 0044 0532 0130 00",
                    filled: true,
                    fillColor: ZevColors.softSurface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text("SWIFT / BIC Code (8 or 11 characters)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _euSwiftBicController,
                  decoration: InputDecoration(
                    hintText: "DEUTDEDDXXX",
                    filled: true,
                    fillColor: ZevColors.softSurface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "ℹ️ Transferred natively via SEPA Instant Euro Credit Transfer.",
                  style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                ),
              ],
            ]

            // =================================================================
            // 2. HESABPAY (AFN)
            // =================================================================
            else if (_selectedType == 'hesabpay') ...[
              const Text("HesabPay Registered Phone Number (+93)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _hesabPhoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: "+93 79 123 4567",
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("Account Holder Full Name", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _hesabNameController,
                decoration: InputDecoration(
                  hintText: "Full name registered on HesabPay account",
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "ℹ️ Payout will be sent directly in Afghanis (AFN) to your HesabPay mobile wallet.",
                style: TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
              ),
            ]

            // =================================================================
            // 3. CRYPTO (USDT MULTI-CHAIN)
            // =================================================================
            else if (_selectedType == 'crypto') ...[
              const Text("Select Blockchain Network", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _cryptoNetwork,
                items: ZevPayoutScreen.kCryptoNetworks.map((net) => DropdownMenuItem(value: net, child: Text(net, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)))).toList(),
                onChanged: (v) => setState(() => _cryptoNetwork = v!),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("Wallet Deposit Address", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _cryptoAddressController,
                decoration: InputDecoration(
                  hintText: "Enter your wallet deposit address",
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("Memo / Tag (Optional)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _cryptoMemoController,
                decoration: InputDecoration(
                  hintText: "Required for exchange accounts (e.g. Binance/Bybit memo)",
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
            ]

            // =================================================================
            // 4. PAYPAL
            // =================================================================
            else if (_selectedType == 'paypal') ...[
              const Text("PayPal Currency", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _paypalCurrency,
                items: const [
                  DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                  DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                  DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
                ],
                onChanged: (v) => setState(() => _paypalCurrency = v!),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("PayPal Account Email", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _paypalEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "name@example.com",
                  filled: true,
                  fillColor: ZevColors.softSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
                ),
              ),
            ],

            const SizedBox(height: 14),
            const Text("Custom Label / Nickname (Optional)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ZevColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: "e.g. My UK Revolut or Primary HesabPay",
                filled: true,
                fillColor: ZevColors.softSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ZevColors.border)),
              ),
            ),

            const SizedBox(height: 24),

            // Save Action Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.deepNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isSaving ? null : _saveAccount,
              child: _isSaving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Save Payout Account", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeTab(String type, String label) {
    final isSelected = _selectedType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: isSelected ? Colors.white : ZevColors.deepNavy,
        ),
        selectedColor: ZevColors.deepNavy,
        backgroundColor: const Color(0xFFF1F5F9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (_) => setState(() => _selectedType = type),
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? ZevColors.deepNavy : ZevColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
