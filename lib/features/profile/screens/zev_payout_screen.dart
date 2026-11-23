import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/telegram_notification_service.dart';

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

  // 1 Coin = 0.01414 USD (e.g. 70 coins = $0.99 USD, 700 coins = $9.90 USD)
  static const double kUsdPerCoin = 0.0141428;
  static const double kEurPerUsd = 0.93;
  static const double kGbpPerUsd = 0.79;
  static const double kAfnPerUsd = 68.0;
  static const int kMinCoinsWithdrawal = 700; // ~$10 USD

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
  // SUBMIT PAYOUT REQUEST WITH TELEGRAM DISPATCH
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
        'Minimum withdrawal is $kMinCoinsWithdrawal Coins (~\$10.00 USD).',
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
      destinationAccount = accountDetails['iban']?.toString() ?? accountDetails['account_number']?.toString() ?? '';
    } else if (methodType == 'paypal') {
      destinationAccount = accountDetails['email']?.toString() ?? '';
    }

    final amountUsd = _calculateUsd(coinsToRedeem);
    final amountTarget = _calculateTargetAmount(coinsToRedeem, targetCurrency);
    final currSymbol = _getCurrencySymbol(targetCurrency);

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Text('💵', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'Confirm Withdrawal',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(0xFF0F172A),
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Destination ($accountTitle):',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destinationAccount,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Method: ${methodType.toUpperCase()} • 0% Platform Fee',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      // 1. Insert into payout_requests
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
        'status': 'pending',
      }).select().single();

      final requestId = insertRes['id']?.toString() ?? 'REQ-${DateTime.now().millisecondsSinceEpoch}';

      // 2. Deduct coins directly from profile
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

      _showToast('Payout request submitted! Admin will process your transfer.', isError: false);
      _loadData();
      _tabController.animateTo(2); // Jump to History tab
    } catch (e) {
      _showToast('Submission error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ===========================================================================
  // CANCEL & REFUND PENDING REQUEST
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Cancel Payout Request?",
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
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
              backgroundColor: const Color(0xFFEF4444),
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

      // 1. Mark request as cancelled/rejected
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
  // ADD NEW SAVED ACCOUNT MODAL (HESABPAY, CRYPTO, BANK, PAYPAL)
  // ===========================================================================
  void _showAddAccountSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddPayoutAccountModal(
        onAccountCreated: () {
          Navigator.pop(ctx);
          _loadData();
          _showToast('Account added and saved successfully!', isError: false);
        },
      ),
    );
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          onPressed: () => Navigator.pop(context, true),
        ),
        title: const Text(
          "Creator Cashout & Payouts",
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
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
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
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
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
          // 1. Balance Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
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
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "0% CASHOUT FEE",
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF059669)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _coinsBalance.toString(),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF064E3B)),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Coins",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF047857)),
                    ),
                    const Spacer(),
                    Text(
                      "≈ \$${_availableUsd.toStringAsFixed(2)} USD",
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF065F46)),
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
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
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
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3), width: 1.5),
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
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Color(0xFF0F172A)),
                          ),
                          Text(
                            "Tap to save HesabPay, Crypto wallet, Bank or PayPal",
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF64748B)),
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
              Color iconColor = const Color(0xFF10B981);
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
                iconColor = const Color(0xFF3B82F6);
                subtitle = "${acc['details']?['bank_name'] ?? 'Bank'} • IBAN: ${acc['details']?['iban'] ?? ''}";
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
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? const Color(0xFF10B981).withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
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
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Color(0xFF0F172A)),
                            ),
                            Text(
                              subtitle,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
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
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Min 700 coins",
                    ),
                  ),
                ),
                Text(
                  "Coins",
                  style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey[600]),
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
                _buildQuickChip("700 (~\$10)", 700),
                _buildQuickChip("1,750 (~\$25)", 1750),
                _buildQuickChip("3,500 (~\$50)", 3500),
                _buildQuickChip("7,000 (~\$100)", 7000),
                _buildQuickChip("All Coins", _coinsBalance),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 4. Live Conversion Preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Estimated Payout Value:",
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                    ),
                    Text(
                      "$currSymbol${convertedAmount.toStringAsFixed(2)} $targetCurrency",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "USD Equivalent:",
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                    Text(
                      "\$${usdEquivalent.toStringAsFixed(2)} USD",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
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
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 4,
              shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
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
        side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
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
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 48, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 12),
                  const Text(
                    "No Payout Accounts Saved Yet",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Save your HesabPay, Crypto wallet, Bank details or PayPal email to cash out your earnings seamlessly.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _showAddAccountSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
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
                  border: Border.all(color: const Color(0xFFE2E8F0)),
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
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Color(0xFF0F172A)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Text(
                            "$currency • ${methodType.toUpperCase()}",
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF059669)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (methodType == 'hesabpay') ...[
                      Text("Phone: ${details['phone_number'] ?? ''}", style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      Text("Name: ${details['account_name'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                    ] else if (methodType == 'crypto') ...[
                      Text("Network: ${details['network'] ?? 'TRC-20'}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      Text("Address: ${details['wallet_address'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                    ] else if (methodType == 'bank') ...[
                      Text("Bank: ${details['bank_name'] ?? ''} (${(details['region'] ?? 'Europe').toString().toUpperCase()})", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      Text("IBAN / Account: ${details['iban'] ?? details['account_number'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                      Text("Holder: ${details['account_holder'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                    ] else if (methodType == 'paypal') ...[
                      Text("Email: ${details['email'] ?? ''}", style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
                          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                          label: const Text("Remove", style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
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
            badgeBg = const Color(0xFFDCFCE7);
            badgeText = const Color(0xFF16A34A);
            statusLabel = "Completed";
          } else if (status == 'processing') {
            badgeBg = const Color(0xFFE0F2FE);
            badgeText = const Color(0xFF0284C7);
            statusLabel = "Processing";
          } else if (status == 'rejected') {
            badgeBg = const Color(0xFFFEE2E2);
            badgeText = const Color(0xFFDC2626);
            statusLabel = "Rejected / Refunded";
          } else {
            badgeBg = const Color(0xFFFEF3C7);
            badgeText = const Color(0xFFD97706);
            statusLabel = "Pending Review";
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "$method Payout",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A)),
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
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    if (coins > 0)
                      Text(
                        "$coins Coins",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFD97706)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Destination: $destination",
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
                if (status == 'pending') ...[
                  const Divider(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _cancelPayoutRequest(item),
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFEF4444)),
                      label: const Text("Cancel & Refund", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w800, fontSize: 12)),
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
// MODAL FOR CREATING & SAVING A PAYOUT ACCOUNT
// =============================================================================
class _AddPayoutAccountModal extends StatefulWidget {
  final VoidCallback onAccountCreated;

  const _AddPayoutAccountModal({required this.onAccountCreated});

  @override
  State<_AddPayoutAccountModal> createState() => _AddPayoutAccountModalState();
}

class _AddPayoutAccountModalState extends State<_AddPayoutAccountModal> {
  final _client = Supabase.instance.client;
  String _selectedType = 'hesabpay'; // hesabpay, crypto, bank, paypal

  // Common title
  final _titleController = TextEditingController();

  // HesabPay
  final _hesabPhoneController = TextEditingController();
  final _hesabNameController = TextEditingController();

  // Crypto
  String _cryptoNetwork = 'TRC-20 (Tron) - Low Fee / Recommended';
  final _cryptoAddressController = TextEditingController();
  final _cryptoMemoController = TextEditingController();

  // Bank
  String _bankRegion = 'Europe'; // Europe, USA, UK
  String _bankCurrency = 'EUR'; // EUR, USD, GBP
  final _bankNameController = TextEditingController();
  final _bankHolderController = TextEditingController();
  final _bankIbanController = TextEditingController();
  final _bankSwiftController = TextEditingController();
  final _bankRoutingController = TextEditingController();

  // PayPal
  String _paypalCurrency = 'USD';
  final _paypalEmailController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _hesabPhoneController.dispose();
    _hesabNameController.dispose();
    _cryptoAddressController.dispose();
    _cryptoMemoController.dispose();
    _bankNameController.dispose();
    _bankHolderController.dispose();
    _bankIbanController.dispose();
    _bankSwiftController.dispose();
    _bankRoutingController.dispose();
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

      if (_selectedType == 'hesabpay') {
        final phone = _hesabPhoneController.text.trim();
        final name = _hesabNameController.text.trim();
        if (phone.isEmpty) throw 'Please enter your HesabPay mobile phone number.';
        currency = 'AFN';
        details = {
          'phone_number': phone,
          'account_name': name,
        };
        defaultTitle = 'HesabPay ($phone)';
      } else if (_selectedType == 'crypto') {
        final address = _cryptoAddressController.text.trim();
        if (address.isEmpty) throw 'Please enter your crypto wallet address.';
        currency = 'USDT';
        details = {
          'network': _cryptoNetwork,
          'wallet_address': address,
          'memo_tag': _cryptoMemoController.text.trim(),
        };
        defaultTitle = 'Crypto (${_cryptoNetwork.split(' ').first})';
      } else if (_selectedType == 'bank') {
        final iban = _bankIbanController.text.trim();
        final bankName = _bankNameController.text.trim();
        final holder = _bankHolderController.text.trim();
        if (iban.isEmpty) throw 'Please enter IBAN / Account Number.';
        currency = _bankCurrency;
        details = {
          'region': _bankRegion,
          'bank_name': bankName,
          'account_holder': holder,
          'iban': iban,
          'swift_bic': _bankSwiftController.text.trim(),
          'routing_number': _bankRoutingController.text.trim(),
        };
        defaultTitle = '$bankName Bank ($_bankRegion)';
      } else if (_selectedType == 'paypal') {
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
        SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFFEF4444)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Add Payout Method",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF0F172A)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Method Selector (4 Segmented Tabs)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTypeTab('hesabpay', '📱 HesabPay (AFN)'),
                  _buildTypeTab('crypto', '⛓ Crypto (USDT)'),
                  _buildTypeTab('bank', '🏦 Bank Transfer'),
                  _buildTypeTab('paypal', '🅿️ PayPal'),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Fields Based on Selected Type
            if (_selectedType == 'hesabpay') ...[
              const Text("HesabPay Mobile Number (+93)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _hesabPhoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: "+93 79 123 4567",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 12),
              const Text("Account Holder Full Name", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _hesabNameController,
                decoration: InputDecoration(
                  hintText: "Enter full name registered in HesabPay",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
            ] else if (_selectedType == 'crypto') ...[
              const Text("Select Blockchain Network", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _cryptoNetwork,
                items: ZevPayoutScreen.kCryptoNetworks.map((net) => DropdownMenuItem(value: net, child: Text(net, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)))).toList(),
                onChanged: (v) => setState(() => _cryptoNetwork = v!),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 12),
              const Text("Wallet Address", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _cryptoAddressController,
                decoration: InputDecoration(
                  hintText: "Enter your wallet deposit address",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 12),
              const Text("Memo / Tag (Optional)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _cryptoMemoController,
                decoration: InputDecoration(
                  hintText: "Required for TON or Exchange deposits",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
            ] else if (_selectedType == 'bank') ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Bank Region", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _bankRegion,
                          items: const [
                            DropdownMenuItem(value: 'Europe', child: Text('Europe (SEPA)')),
                            DropdownMenuItem(value: 'USA', child: Text('USA (ACH/Wire)')),
                            DropdownMenuItem(value: 'UK', child: Text('UK (Sort Code)')),
                          ],
                          onChanged: (v) => setState(() {
                            _bankRegion = v!;
                            _bankCurrency = v == 'Europe' ? 'EUR' : (v == 'UK' ? 'GBP' : 'USD');
                          }),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Currency", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _bankCurrency,
                          items: const [
                            DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                            DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                            DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
                          ],
                          onChanged: (v) => setState(() => _bankCurrency = v!),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text("Bank Name", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _bankNameController,
                decoration: InputDecoration(
                  hintText: "e.g. Revolut, Wise, Chase, Barclays",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("Account Holder Name", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _bankHolderController,
                decoration: InputDecoration(
                  hintText: "Full name on account",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("IBAN / Account Number", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _bankIbanController,
                decoration: InputDecoration(
                  hintText: "IBAN or domestic account number",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("SWIFT / BIC / Routing Code (Optional)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _bankSwiftController,
                decoration: InputDecoration(
                  hintText: "Bank identifier code",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ] else if (_selectedType == 'paypal') ...[
              const Text("PayPal Currency", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
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
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("PayPal Email Address", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: _paypalEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "yourname@example.com",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],

            const SizedBox(height: 14),
            const Text("Account Custom Label (Optional)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: "e.g. My Personal HesabPay or Main Wallet",
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),

            const SizedBox(height: 22),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isSaving ? null : _saveAccount,
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Save Payout Method", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
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
          color: isSelected ? Colors.white : const Color(0xFF0F172A),
        ),
        selectedColor: const Color(0xFF0284C7),
        backgroundColor: const Color(0xFFF1F5F9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (_) => setState(() => _selectedType = type),
      ),
    );
  }
}
