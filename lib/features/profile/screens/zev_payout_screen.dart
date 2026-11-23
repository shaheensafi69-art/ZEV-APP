import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ZevPayoutScreen extends StatefulWidget {
  final double currentEarningsUsd;
  final int totalEarningsCoins;
  final int initialTabIndex;

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

  double _availableUsd = 0.0;
  int _earningsCoins = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Form State
  String _selectedMethod = 'PayPal'; // PayPal, USDT, Bank
  final _accountController = TextEditingController();
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();

  // History State
  List<Map<String, dynamic>> _payoutHistory = [];

  static const double kMinWithdrawalUsd = 10.0;

  @override
  void initState() {
    super.initState();
    _availableUsd = widget.currentEarningsUsd;
    _earningsCoins = widget.totalEarningsCoins;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _accountController.dispose();
    _amountController.dispose();
    _nameController.dispose();
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
          .select('earnings_usd, earnings_coins')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null && mounted) {
        setState(() {
          _availableUsd =
              (profile['earnings_usd'] as num?)?.toDouble() ?? 0.0;
          _earningsCoins =
              (profile['earnings_coins'] as num?)?.toInt() ?? 0;
        });
      }

      // 2. Fetch payout history
      final history = await _client
          .from('payout_requests')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _payoutHistory = List<Map<String, dynamic>>.from(history);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setAmount(double amount) {
    HapticFeedback.selectionClick();
    setState(() {
      _amountController.text = amount.toStringAsFixed(2);
    });
  }

  Future<void> _submitPayoutRequest() async {
    HapticFeedback.mediumImpact();
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _showToast('Please sign in to withdraw earnings.', isError: true);
      return;
    }

    final destination = _accountController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;

    if (destination.isEmpty) {
      _showToast('Please enter your destination account / address.', isError: true);
      return;
    }

    if (amount < kMinWithdrawalUsd) {
      _showToast(
        'Minimum withdrawal amount is \$${kMinWithdrawalUsd.toStringAsFixed(2)} USD.',
        isError: true,
      );
      return;
    }

    if (amount > _availableUsd) {
      _showToast(
        'Insufficient balance. You have \$${_availableUsd.toStringAsFixed(2)} USD available.',
        isError: true,
      );
      return;
    }

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
              'You are withdrawing \$${amount.toStringAsFixed(2)} USD via $_selectedMethod.',
              style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 12),
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
                    'Destination:',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold),
                  ),
                  Text(
                    destination,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Processing Time: 24 to 48 Hours',
                    style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      // 1. Insert payout request
      await _client.from('payout_requests').insert({
        'user_id': userId,
        'amount_usd': amount,
        'payout_method': _selectedMethod.toLowerCase(),
        'destination_account': destination,
        'status': 'pending',
      });

      // 2. Deduct earnings from profile
      await _client
          .from('profiles')
          .update({'earnings_usd': _availableUsd - amount})
          .eq('id', userId);

      _accountController.clear();
      _amountController.clear();

      _showToast('Withdrawal submitted! Funds will arrive within 24-48 hours.');
      await _loadData();

      // Switch to history tab
      if (mounted) {
        _tabController.animateTo(1);
      }
    } catch (e) {
      _showToast('Failed to process withdrawal: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _cancelPayout(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString();
    final amount = (request['amount_usd'] as num?)?.toDouble() ?? 0.0;
    final userId = _client.auth.currentUser?.id;

    if (requestId == null || userId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Cancel Withdrawal Request?'),
        content: Text(
          'Do you want to cancel this pending withdrawal of \$${amount.toStringAsFixed(2)} USD? The amount will be refunded immediately back to your balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Pending'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Request & Refund'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // Delete or mark cancelled
      await _client.from('payout_requests').delete().eq('id', requestId);

      // Refund to profile
      await _client
          .from('profiles')
          .update({'earnings_usd': _availableUsd + amount})
          .eq('id', userId);

      _showToast('\$${amount.toStringAsFixed(2)} USD refunded back to your balance.');
      await _loadData();
    } catch (e) {
      _showToast('Failed to cancel request: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      Text('💸'),
                      SizedBox(width: 6),
                      Text("Request Payout"),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('📑'),
                      SizedBox(width: 6),
                      Text("Payout History"),
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildWithdrawTab(),
                      _buildHistoryTab(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // TAB 1: Request Payout Form
  Widget _buildWithdrawTab() {
    final canWithdraw = _availableUsd >= kMinWithdrawalUsd;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Balance Card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  blurRadius: 18,
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
                      "Available Withdrawable Cash",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF065F46),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "40% CREATOR",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "\$${_availableUsd.toStringAsFixed(2)} USD",
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF064E3B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$_earningsCoins Diamonds / Livestream gift coins accumulated",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!canWithdraw) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Minimum payout threshold is \$${kMinWithdrawalUsd.toStringAsFixed(2)} USD. Earn more by going live!",
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF92400E),
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

          const SizedBox(height: 24),

          // Method Selector
          const Text(
            "Select Payout Method",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              _buildMethodCard('PayPal', 'PayPal', 'Instant - 24h', '💳'),
              const SizedBox(width: 8),
              _buildMethodCard('USDT', 'USDT (TRC-20)', 'Crypto Transfer', '🪙'),
              const SizedBox(width: 8),
              _buildMethodCard('Bank', 'Bank Wire', '1-3 Business Days', '🏦'),
            ],
          ),

          const SizedBox(height: 20),

          // Destination Input
          Text(
            _selectedMethod == 'PayPal'
                ? "PayPal Email Address"
                : _selectedMethod == 'USDT'
                    ? "USDT (TRC-20) Wallet Address"
                    : "IBAN / Bank Account & Full Name",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _accountController,
            decoration: InputDecoration(
              hintText: _selectedMethod == 'PayPal'
                  ? 'creator@example.com'
                  : _selectedMethod == 'USDT'
                      ? 'T... (TRC-20 Tether address)'
                      : 'IBAN / Swift + Account Holder Name',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Amount Input & Quick Chips
          const Text(
            "Withdrawal Amount (USD)",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '\$ ',
              prefixStyle: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A), fontSize: 16),
              hintText: '0.00',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Quick Preset Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildChip('\$10', 10.0),
              _buildChip('\$25', 25.0),
              _buildChip('\$50', 50.0),
              _buildChip('\$100', 100.0),
              _buildChip('Max (\$${_availableUsd.toStringAsFixed(2)})', _availableUsd),
            ],
          ),

          const SizedBox(height: 24),

          // Policy Guarantee Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Platform Withdrawal Fee", style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    Text("\$0.00 (0% Free)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  ],
                ),
                SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Processing Schedule", style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    Text("Within 24–48 Hours", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Submit Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canWithdraw ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: canWithdraw ? 4 : 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: canWithdraw && !_isSubmitting ? _submitPayoutRequest : null,
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Submit Payout Request",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard(String key, String title, String subtitle, String emoji) {
    final isSelected = _selectedMethod == key;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedMethod = key);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFECFDF5) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? const Color(0xFF065F46) : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, double amount) {
    return GestureDetector(
      onTap: () => _setAmount(amount),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }

  // TAB 2: Payout History & Live Status
  Widget _buildHistoryTab() {
    if (_payoutHistory.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF1F5F9),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                alignment: Alignment.center,
                child: const Text('📑', style: TextStyle(fontSize: 32)),
              ),
              const SizedBox(height: 16),
              const Text(
                "No Payout Requests Yet",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "When you submit a withdrawal from your 40% livestream earnings, track the status here in real time.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
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
          final amount = (item['amount_usd'] as num?)?.toDouble() ?? 0.0;
          final method = (item['payout_method'] ?? 'paypal').toString().toUpperCase();
          final destination = (item['destination_account'] ?? '').toString();
          final status = (item['status'] ?? 'pending').toString().toLowerCase();
          final createdAt = item['created_at'] != null
              ? DateTime.tryParse(item['created_at'].toString())
              : null;
          final adminNotes = item['admin_notes']?.toString();

          Color badgeBg;
          Color badgeText;
          String statusLabel;
          IconData statusIcon;

          switch (status) {
            case 'completed':
              badgeBg = const Color(0xFFECFDF5);
              badgeText = const Color(0xFF059669);
              statusLabel = 'Completed';
              statusIcon = Icons.check_circle_rounded;
              break;
            case 'approved':
            case 'processing':
              badgeBg = const Color(0xFFEFF6FF);
              badgeText = const Color(0xFF2563EB);
              statusLabel = 'Processing';
              statusIcon = Icons.sync_rounded;
              break;
            case 'rejected':
              badgeBg = const Color(0xFFFEF2F2);
              badgeText = const Color(0xFFDC2626);
              statusLabel = 'Declined';
              statusIcon = Icons.cancel_rounded;
              break;
            case 'pending':
            default:
              badgeBg = const Color(0xFFFFFBEB);
              badgeText = const Color(0xFFD97706);
              statusLabel = 'Under Review (24-48h)';
              statusIcon = Icons.schedule_rounded;
              break;
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
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
                        Text(
                          method == 'PAYPAL' ? '💳' : method == 'USDT' ? '🪙' : '🏦',
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          method,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "\$${amount.toStringAsFixed(2)} USD",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "To: $destination",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, color: badgeText, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: badgeText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        "${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}",
                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                  ],
                ),
                if (adminNotes != null && adminNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Text(
                      "Note: $adminNotes",
                      style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B)),
                    ),
                  ),
                ],
                if (status == 'pending') ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      onPressed: () => _cancelPayout(item),
                      icon: const Icon(Icons.close_rounded, size: 14),
                      label: const Text(
                        "Cancel & Refund",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                      ),
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
