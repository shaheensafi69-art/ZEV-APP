import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/theme/app_theme_service.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../widgets/shop_ad_banner.dart';
import 'product_checkout_screen.dart';

class ShopScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ShopScreen({super.key, this.onBack});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _products = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';
  late String _activeCurrency;

  @override
  void initState() {
    super.initState();
    final langCode = LanguageService.instance.currentLanguage.code;
    _activeCurrency = CurrencyService.instance.getCurrencyForLanguage(langCode);
    CurrencyService.instance.fetchLiveRates().then((_) {
      if (mounted) setState(() {});
    });
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);
    try {
      final res = await supabase
          .from('reseller_products')
          .select('*')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> loaded = List<Map<String, dynamic>>.from(res);
      if (loaded.isEmpty) {
        loaded = _getDemoProducts();
      }
      if (mounted) {
        setState(() {
          _products = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reseller_products: $e');
      if (mounted) {
        setState(() {
          _products = _getDemoProducts();
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getDemoProducts() {
    return [
      {
        'id': 'demo-prod-1',
        'name': 'Algorithmic Smart Trading Bot VIP Pro',
        'category': 'Trading Bots',
        'description':
            'Official AI trading algorithm with automatic risk management, 78%+ win-rate, compatible with MetaTrader 4/5 and TradingView.',
        'selling_price': 149.0,
        'cost_price': 100.0,
        'in_stock': true,
        'currency': 'USD',
      },
      {
        'id': 'demo-prod-2',
        'name': 'Golden Signals & Technical Analysis (6-Month)',
        'category': 'Signals',
        'description':
            'Exclusive access to VIP signals for Gold, Forex, and Crypto with precision entry/exit targets and direct mentor consultations.',
        'selling_price': 89.0,
        'cost_price': 60.0,
        'in_stock': true,
        'currency': 'USD',
      },
      {
        'id': 'demo-prod-3',
        'name': 'Ultra Low-Latency Dedicated Forex VPS',
        'category': 'VPS & Servers',
        'description':
            'Dedicated German & UK servers with sub-1ms ping to major brokers, 16GB RAM, 100% uptime guarantee for Expert Advisors.',
        'selling_price': 35.0,
        'cost_price': 25.0,
        'in_stock': true,
        'currency': 'USD',
      },
      {
        'id': 'demo-prod-4',
        'name': 'TradingView Premium Annual License Key',
        'category': 'Accounts',
        'description':
            'Verified annual activation for TradingView Premium with unlimited indicators, 8-chart layouts, and second-based intervals.',
        'selling_price': 199.0,
        'cost_price': 140.0,
        'in_stock': true,
        'currency': 'USD',
      },
      {
        'id': 'demo-prod-5',
        'name': 'Master Trader Financial Hardware Key',
        'category': 'Educational Gear',
        'description':
            'Certified hardware security token with biometric protection for crypto assets, cold-storage backup, and official manufacturer warranty.',
        'selling_price': 129.0,
        'cost_price': 90.0,
        'in_stock': false,
        'currency': 'USD',
      },
    ];
  }

  List<String> get _categories {
    final Set<String> cats = {'All'};
    for (final p in _products) {
      final cat = p['category']?.toString();
      if (cat != null && cat.isNotEmpty) {
        cats.add(cat);
      }
    }
    return cats.toList();
  }

  List<Map<String, dynamic>> get _filteredProducts {
    return _products.where((p) {
      final matchesCat =
          _selectedCategory == 'All' || p['category'] == _selectedCategory;
      final q = _searchQuery.toLowerCase().trim();
      final name = (p['name'] ?? '').toString().toLowerCase();
      final desc = (p['description'] ?? '').toString().toLowerCase();
      final matchesQuery = q.isEmpty || name.contains(q) || desc.contains(q);
      return matchesCat && matchesQuery;
    }).toList();
  }

  // Multilingual labels for Shop delegating to central 19-language ZevStrings
  String _t(String key) {
    return context.zevTr(key);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, activeLocale, _) {
        final palette = AppThemeService.instance.current;
        final isDark = palette.isDark;
        final textPrimary = palette.textPrimary;
        final textSecondary = palette.textSecondary;
        final isRtl = LanguageService.isRtl(activeLocale.languageCode);

        final Widget mainContent = RefreshIndicator(
              color: palette.primary,
              onRefresh: _fetchProducts,
              child: ResponsiveLayout.pageConstraint(
                maxWidth: 1200,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    // Search Bar & Subtitle
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: isRtl
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('subtitle'),
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Search box
                            Container(
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: palette.cardBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.2 : 0.04,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: TextField(
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: _t('search_hint'),
                                  hintStyle: TextStyle(
                                    color: textSecondary.withValues(alpha: 0.7),
                                    fontSize: 13,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: palette.primary,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Categories List
                            SizedBox(
                              height: 38,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: _categories.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (ctx, i) {
                                  final cat = _categories[i];
                                  final isSelected = cat == _selectedCategory;
                                  final label = cat == 'All' ? _t('all') : cat;

                                  return InkWell(
                                    onTap: () =>
                                        setState(() => _selectedCategory = cat),
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? palette.primary
                                            : palette.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected
                                              ? palette.primary
                                              : palette.cardBorder,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : textSecondary,
                                            fontSize: 12.5,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Google AdMob Shop Banner
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ShopAdBanner(),
                      ),
                    ),

                    // Products Grid / List
                    if (_isLoading)
                      SliverToBoxAdapter(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 80),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: palette.primary,
                            ),
                          ),
                        ),
                      )
                    else if (_filteredProducts.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 80),
                          child: Column(
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 60,
                                color: textSecondary.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _t('no_products'),
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (ResponsiveLayout.isPhone(context))
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final product = _filteredProducts[index];
                            return _buildProductCard(product, palette, isRtl);
                          }, childCount: _filteredProducts.length),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    ResponsiveLayout.isTablet(context) ? 2 : (MediaQuery.of(context).size.width >= 1200 ? 3 : 2),
                                crossAxisSpacing: 18,
                                mainAxisSpacing: 18,
                                childAspectRatio: 0.69,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final product = _filteredProducts[index];
                            return _buildProductCard(product, palette, isRtl);
                          }, childCount: _filteredProducts.length),
                        ),
                      ),
                  ],
                ),
              ),
            );

        if (MediaQuery.of(context).size.width >= 1050) {
          return Directionality(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              backgroundColor: palette.background,
              appBar: AppBar(
                backgroundColor: palette.surface,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                centerTitle: false,
                leading: (Navigator.of(context).canPop() || widget.onBack != null)
                    ? IconButton(
                        icon: Icon(
                          isRtl
                              ? Icons.arrow_forward_ios_rounded
                              : Icons.arrow_back_ios_rounded,
                          color: textPrimary,
                          size: 20,
                        ),
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else if (widget.onBack != null) {
                            widget.onBack!();
                          }
                        },
                      )
                    : null,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: palette.gradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _t('title'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: InkWell(
                      onTap: _showCurrencyPickerSheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
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
                              _activeCurrency,
                              style: TextStyle(
                                color: palette.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_drop_down,
                              color: palette.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main products area (70%)
                    Expanded(child: mainContent),
                    const SizedBox(width: 22),
                    // Right ads and trust sidebar (30%)
                    SizedBox(
                      width: 320,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: _buildShopSidebar(palette, isDark, isRtl),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              backgroundColor: palette.surface,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              leading: (Navigator.of(context).canPop() || widget.onBack != null)
                  ? IconButton(
                      icon: Icon(
                        isRtl
                            ? Icons.arrow_forward_ios_rounded
                            : Icons.arrow_back_ios_rounded,
                        color: textPrimary,
                        size: 20,
                      ),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else if (widget.onBack != null) {
                          widget.onBack!();
                        }
                      },
                    )
                  : null,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: palette.gradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _t('title'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: InkWell(
                    onTap: _showCurrencyPickerSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
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
                            _activeCurrency,
                            style: TextStyle(
                              color: palette.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down,
                            color: palette.primary,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: mainContent,
          ),
        );
      },
    );
  }

  (List<Color>, IconData) _getCategoryStyle(String category) {
    final c = category.toLowerCase();
    if (c.contains('bot') || c.contains('ai') || c.contains('algo')) {
      return (
        [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
        Icons.smart_toy_rounded,
      );
    } else if (c.contains('signal') || c.contains('forex') || c.contains('gold')) {
      return (
        [const Color(0xFFF59E0B), const Color(0xFFEF4444)],
        Icons.trending_up_rounded,
      );
    } else if (c.contains('vps') || c.contains('server')) {
      return (
        [const Color(0xFF06B6D4), const Color(0xFF3B82F6)],
        Icons.dns_rounded,
      );
    } else if (c.contains('account') || c.contains('key') || c.contains('license')) {
      return (
        [const Color(0xFF10B981), const Color(0xFF059669)],
        Icons.vpn_key_rounded,
      );
    }
    return (
      [const Color(0xFFFC466B), const Color(0xFFFF8E53)],
      Icons.shopping_bag_rounded,
    );
  }

  Widget _buildProductCard(
    Map<String, dynamic> product,
    LuxuryPalette palette,
    bool isRtl,
  ) {
    final name = product['name']?.toString() ?? 'Product';
    final desc = product['description']?.toString() ?? '';
    final cat = product['category']?.toString() ?? 'General';
    final sellingPrice = (product['selling_price'] as num?)?.toDouble() ?? 0.0;
    final inStock = product['in_stock'] == true;
    final isDark = palette.isDark;
    final textPrimary = palette.textPrimary;
    final textSecondary = palette.textSecondary;

    final localPriceFormatted = CurrencyService.instance.format(
      sellingPrice,
      _activeCurrency,
    );

    final (catGradient, catIcon) = _getCategoryStyle(cat);
    final simulatedOriginalPrice = sellingPrice > 0 ? (sellingPrice * 1.35).toStringAsFixed(2) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.09)
              : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openProductCheckout(product),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Vibrant Top Product Banner Header
                Container(
                  height: 72,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: catGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(catIcon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cat.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Text(
                              "⚡ INSTANT DELIVERY",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // In-stock badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: inStock
                              ? Colors.greenAccent.withValues(alpha: 0.25)
                              : Colors.redAccent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: inStock ? Colors.greenAccent : Colors.redAccent,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 3,
                              backgroundColor: inStock ? Colors.greenAccent : Colors.redAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              inStock ? _t('in_stock') : _t('out_of_stock'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Product Name & Badges
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Column(
                    crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Feature Tags Row
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildTagPill("Verified 🛡️", palette.primary, isDark),
                          _buildTagPill("⭐ 4.9 Rated", Colors.amber[700]!, isDark),
                          _buildTagPill("Auto Setup", Colors.blueAccent, isDark),
                        ],
                      ),

                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const Spacer(),

                // 3. Price & Action Button Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.02)
                        : const Color(0xFFF8FAFC),
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '\$${sellingPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'USD',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (simulatedOriginalPrice.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '\$$simulatedOriginalPrice',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10.5,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              '≈ $localPriceFormatted',
                              style: TextStyle(
                                color: palette.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Order Action Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.primary,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: palette.primary.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        ),
                        onPressed: () => _openProductCheckout(product),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                        label: Text(
                          _t('details_order'),
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                      ),
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

  Widget _buildTagPill(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildShopSidebar(LuxuryPalette palette, bool isDark, bool isRtl) {
    return Column(
      children: [
        // 1. Featured Sponsored Deal Banner
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2575FC).withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "⭐ FEATURED DEAL",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 20),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                "ZEV VIP Trading & Bots\nSave up to 40% Today",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Automated high win-rate bots & VIP signals verified by top market mentors.",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2575FC),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    setState(() => _selectedCategory = 'Trading Bots');
                  },
                  child: const Text(
                    "Explore VIP Bots ➔",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 2. Buyer Guarantee & Trust Box
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: palette.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "ZEV Buyer Guarantee",
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildTrustItem(Icons.flash_on_rounded, "Instant Auto-Delivery", "Licenses and logins dispatched instantly", palette),
              const SizedBox(height: 12),
              _buildTrustItem(Icons.security_rounded, "100% Escrow Protection", "Funds held safely until full verification", palette),
              const SizedBox(height: 12),
              _buildTrustItem(Icons.support_agent_rounded, "24/7 Priority Support", "Dedicated dispute & activation team", palette),
              const SizedBox(height: 12),
              _buildTrustItem(Icons.replay_rounded, "Warranty & Replacement", "30-day official replacement coverage", palette),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 3. Merchant / Reseller Partner Program
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                  : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: palette.primary.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storefront_rounded, color: palette.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "Sell On ZEV Shop",
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Are you a software creator or digital provider? List your licenses to 50k+ students.",
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Reseller program application: Contact support@zevapp.com"),
                        backgroundColor: Colors.blueAccent,
                      ),
                    );
                  },
                  child: Text(
                    "Become a Partner",
                    style: TextStyle(
                      color: palette.primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrustItem(IconData icon, String title, String sub, LuxuryPalette palette) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: palette.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: palette.primary, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openProductCheckout(Map<String, dynamic> product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductCheckoutScreen(
          product: product,
          initialCurrency: _activeCurrency,
        ),
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
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
                      _t('currency_title'),
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
                          final isSelected = cur == _activeCurrency;
                          final curName = curInfo.nameEn;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
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
                                ? Icon(
                                    Icons.check_circle,
                                    color: palette.primary,
                                  )
                                : null,
                            onTap: () {
                              setState(() => _activeCurrency = cur);
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
