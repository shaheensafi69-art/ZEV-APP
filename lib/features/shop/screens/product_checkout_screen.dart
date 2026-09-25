import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/telegram_order_service.dart';
import '../../../core/theme/app_theme_service.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/widgets/responsive_layout.dart';

class ProductCheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final String initialCurrency;

  const ProductCheckoutScreen({
    super.key,
    required this.product,
    required this.initialCurrency,
  });

  @override
  State<ProductCheckoutScreen> createState() => _ProductCheckoutScreenState();
}

class _ProductCheckoutScreenState extends State<ProductCheckoutScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late String _selectedCurrency;
  String _selectedPaymentMethod = 'HesabPay'; // 'HesabPay' or 'AtomaPay'

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _txRefController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _isSubmitting = false;

  static const String hesabPayPhone = '+93796040415';
  static const String atomaPayPhone = '+93773449567';

  @override
  void initState() {
    super.initState();
    _selectedCurrency = widget.initialCurrency;
    _prefillUser();
  }

  void _prefillUser() {
    final user = supabase.auth.currentUser;
    if (user != null) {
      _nameController.text = user.userMetadata?['full_name'] ?? '';
      _contactController.text = user.phone ?? user.email ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _txRefController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get _sellingPrice =>
      (widget.product['selling_price'] as num?)?.toDouble() ?? 0.0;

  double get _costPrice =>
      (widget.product['cost_price'] as num?)?.toDouble() ?? 0.0;

  // Multilingual translations for checkout screen delegating to central 19-language ZevStrings
  String _t(String key) {
    return context.zevTr(key);
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final user = supabase.auth.currentUser;
      final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
      final localPriceStr =
          CurrencyService.instance.format(_sellingPrice, _selectedCurrency);

      final orderPayload = {
        'payment_method': _selectedPaymentMethod,
        'receiver_phone':
            _selectedPaymentMethod == 'HesabPay' ? hesabPayPhone : atomaPayPhone,
        'buyer_name': _nameController.text.trim(),
        'buyer_contact': _contactController.text.trim(),
        'transaction_ref': _txRefController.text.trim(),
        'note': _noteController.text.trim(),
        'currency': _selectedCurrency,
        'local_price_formatted': localPriceStr,
        'product_name': widget.product['name'],
      };

      // 1. Record order in reseller_orders table
      try {
        await supabase.from('reseller_orders').insert({
          'student_id': user?.id,
          'product_id': widget.product['id'],
          'external_order_id': orderId,
          'cost_price': _costPrice,
          'selling_price': _sellingPrice,
          'currency': _selectedCurrency,
          'payload': orderPayload,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (dbErr) {
        debugPrint('Warning saving to reseller_orders: $dbErr');
      }

      // 2. Send instant order notification to Telegram admin
      await TelegramOrderService.instance.sendOrderNotification(
        orderId: orderId,
        productName: widget.product['name']?.toString() ?? 'ZEV Store Product',
        priceUsd: _sellingPrice,
        localPriceFormatted: localPriceStr,
        paymentMethod: _selectedPaymentMethod == 'HesabPay'
            ? 'HesabPay'
            : 'Atoma Pay',
        senderPhone: _contactController.text.trim(),
        transactionReference: _txRefController.text.trim(),
        buyerName: _nameController.text.trim(),
        buyerEmail: user?.email ?? _contactController.text.trim(),
        note: _noteController.text.trim(),
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSuccessDialog(orderId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSuccessDialog(String orderId) {
    final palette = AppThemeService.instance.current;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.cardBorder),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 54),
            ),
            const SizedBox(height: 18),
            Text(
              _t('success_title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _t('success_msg'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                '${_t('order_id_label')} $orderId',
                style: TextStyle(
                  color: palette.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(ctx); // Dialog
                  Navigator.pop(context); // Checkout screen
                },
                child: Text(
                  _t('close'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(_t('copied')),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, activeLocale, _) {
        final palette = AppThemeService.instance.current;
        final isDark = palette.isDark;
        final isRtl = LanguageService.isRtl(activeLocale.languageCode);

        final localPriceFormatted =
            CurrencyService.instance.format(_sellingPrice, _selectedCurrency);

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            isRtl ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_rounded,
            color: palette.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _t('checkout_title'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: palette.textPrimary,
          ),
        ),
      ),
      body: ResponsiveLayout.feedConstraint(
        maxWidth: 680,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Full Product Specifications Card
              _buildProductDetailsCard(palette, localPriceFormatted, isRtl, isDark),

              const SizedBox(height: 22),

              // 2. Payment Method Selector (2 Official Buttons: HesabPay & Atoma Pay)
              Text(
                _t('choose_payment'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  // Button 1: HesabPay
                  Expanded(
                    child: _buildPaymentMethodButton(
                      id: 'HesabPay',
                      title: 'HesabPay',
                      subTitle: 'HesabPay',
                      brandColor: const Color(0xFF00A389),
                      icon: Icons.account_balance_wallet_rounded,
                      palette: palette,
                      isSelected: _selectedPaymentMethod == 'HesabPay',
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Button 2: Atoma Pay
                  Expanded(
                    child: _buildPaymentMethodButton(
                      id: 'AtomaPay',
                      title: 'Atoma Pay',
                      subTitle: 'Atoma Pay',
                      brandColor: const Color(0xFF1D4ED8),
                      icon: Icons.payments_rounded,
                      palette: palette,
                      isSelected: _selectedPaymentMethod == 'AtomaPay',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 3. Payment Instruction & Authentic QR Code Card
              _buildPaymentDetailsCard(palette, localPriceFormatted, isRtl, isDark),

              const SizedBox(height: 24),

              // 4. Buyer Info & Transaction Form
              Text(
                _t('buyer_info'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Full name
              TextFormField(
                controller: _nameController,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  labelText: _t('full_name'),
                  prefixIcon: Icon(Icons.person_outline, color: palette.primary),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? _t('name_req') : null,
              ),
              const SizedBox(height: 14),

              // Contact
              TextFormField(
                controller: _contactController,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  labelText: _t('contact'),
                  prefixIcon: Icon(Icons.phone_outlined, color: palette.primary),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? _t('contact_req') : null,
              ),
              const SizedBox(height: 14),

              // Transaction Ref ID
              TextFormField(
                controller: _txRefController,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  labelText: _t('tx_id'),
                  prefixIcon:
                      Icon(Icons.confirmation_number_outlined, color: palette.primary),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? _t('tx_req') : null,
              ),
              const SizedBox(height: 14),

              // Note
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  labelText: _t('notes'),
                  prefixIcon: Icon(Icons.note_alt_outlined, color: palette.primary),
                ),
              ),

              const SizedBox(height: 28),

              // Complete Order Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 6,
                    shadowColor: palette.primary.withValues(alpha: 0.4),
                  ),
                  onPressed: _isSubmitting ? null : _submitOrder,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${_t('complete_order')} ($localPriceFormatted)',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
      },
    );
  }

  // 1. Full Product Specifications Card
  Widget _buildProductDetailsCard(
    LuxuryPalette palette,
    String localPriceFormatted,
    bool isRtl,
    bool isDark,
  ) {
    final name = widget.product['name']?.toString() ?? 'Product';
    final desc = widget.product['description']?.toString() ?? '';
    final cat = widget.product['category']?.toString() ?? 'Verified Item';
    final inStock = widget.product['in_stock'] == true;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Category Pill & In Stock
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: inStock
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3.5,
                      backgroundColor: inStock ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      inStock ? _t('in_stock') : _t('out_of_stock'),
                      style: TextStyle(
                        color: inStock ? Colors.green : Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Title
          Text(
            name,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),

          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              desc,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: palette.cardBorder, height: 1),
          const SizedBox(height: 14),

          // Dual Price Display with Currency Switcher
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('price_title'),
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '\$${_sellingPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'USD',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '≈ $localPriceFormatted',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: palette.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // Currency Switcher Button
              InkWell(
                onTap: _showCurrencyPickerSheet,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedCurrency,
                        style: TextStyle(
                          color: palette.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.swap_horiz_rounded,
                          color: palette.primary, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 2. Payment Method Selector Button (HesabPay / Atoma Pay)
  Widget _buildPaymentMethodButton({
    required String id,
    required String title,
    required String subTitle,
    required Color brandColor,
    required IconData icon,
    required LuxuryPalette palette,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        setState(() => _selectedPaymentMethod = id);
        HapticFeedback.selectionClick();
      },
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? brandColor.withValues(alpha: 0.12)
              : palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? brandColor : palette.cardBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: brandColor.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: brandColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: brandColor, size: 20)
                else
                  Icon(Icons.radio_button_off_rounded,
                      color: palette.textSecondary.withValues(alpha: 0.4),
                      size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subTitle,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 3. Payment Instruction & Authentic QR Code Card
  Widget _buildPaymentDetailsCard(
    LuxuryPalette palette,
    String localPriceFormatted,
    bool isRtl,
    bool isDark,
  ) {
    final isHesab = _selectedPaymentMethod == 'HesabPay';
    final currentPhone = isHesab ? hesabPayPhone : atomaPayPhone;
    final brandColor =
        isHesab ? const Color(0xFF00A389) : const Color(0xFF1D4ED8);
    final qrAssetPath =
        isHesab ? 'assets/hesabpay.jpg' : 'assets/atomapay.jpg';

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: brandColor.withValues(alpha: 0.4), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: brandColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Payment Brand Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: brandColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isHesab ? 'HesabPay' : 'Atoma Pay',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isHesab ? _t('hesabpay_desc') : _t('atomapay_desc'),
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Authentic QR Code Display
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      qrAssetPath,
                      width: 170,
                      height: 170,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, stack) {
                        return Container(
                          width: 170,
                          height: 170,
                          color: const Color(0xFFF1F5F9),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code_2_rounded,
                                  size: 60, color: brandColor),
                              const SizedBox(height: 6),
                              Text(
                                currentPhone,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: brandColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _t('scan_qr'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Merchant Phone Number with 1-Tap Copy
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: brandColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.phone_iphone_rounded, color: brandColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('account_number'),
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        currentPhone,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: brandColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _copyToClipboard(currentPhone),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: brandColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: brandColor.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            _t('copy_number'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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

          const SizedBox(height: 16),
          Divider(color: palette.cardBorder, height: 1),
          const SizedBox(height: 14),

          // Step-by-Step Professional Instructions
          Text(
            _t('step1'),
            style: TextStyle(
              fontSize: 12,
              color: palette.textPrimary,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t('step2'),
            style: TextStyle(
              fontSize: 12,
              color: palette.textPrimary,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t('step3'),
            style: TextStyle(
              fontSize: 12,
              color: palette.textPrimary,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t('step4'),
            style: TextStyle(
              fontSize: 12,
              color: palette.textPrimary,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showCurrencyPickerSheet() {
    final palette = AppThemeService.instance.current;
    const currencies = CurrencyService.supportedCurrencies;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: palette.cardBorder),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.textSecondary.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select Display Currency',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: currencies.length,
                        separatorBuilder: (context, index) =>
                            Divider(color: palette.cardBorder, height: 1),
                        itemBuilder: (c, idx) {
                          final curInfo = currencies[idx];
                          final cur = curInfo.code;
                          final isSelected = cur == _selectedCurrency;
                          final curName = curInfo.nameEn;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              '$cur - $curName (${curInfo.symbol})',
                              style: TextStyle(
                                color: isSelected
                                    ? palette.primary
                                    : palette.textPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: palette.primary)
                                : null,
                            onTap: () {
                              setState(() => _selectedCurrency = cur);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
