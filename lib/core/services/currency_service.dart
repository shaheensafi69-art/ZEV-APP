import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CurrencyInfo {
  final String code;
  final String nameEn;
  final String symbol;
  final String flag;

  const CurrencyInfo({
    required this.code,
    required this.nameEn,
    required this.symbol,
    required this.flag,
  });
}

class CurrencyService {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  // Currencies tailored to the 19 supported languages
  static const List<CurrencyInfo> supportedCurrencies = [
    CurrencyInfo(code: 'USD', nameEn: 'US Dollar', symbol: '\$', flag: 'US'),
    CurrencyInfo(code: 'AFN', nameEn: 'Afghan Afghani', symbol: 'AFN', flag: 'AF'),
    CurrencyInfo(code: 'EUR', nameEn: 'Euro', symbol: '€', flag: 'EU'),
    CurrencyInfo(code: 'TRY', nameEn: 'Turkish Lira', symbol: '₺', flag: 'TR'),
    CurrencyInfo(code: 'PKR', nameEn: 'Pakistani Rupee', symbol: 'Rs', flag: 'PK'),
    CurrencyInfo(code: 'SAR', nameEn: 'Saudi Riyal', symbol: 'SAR', flag: 'SA'),
    CurrencyInfo(code: 'AED', nameEn: 'UAE Dirham', symbol: 'AED', flag: 'AE'),
    CurrencyInfo(code: 'IRR', nameEn: 'Iranian Toman', symbol: 'Toman', flag: 'IR'),
    CurrencyInfo(code: 'CNY', nameEn: 'Chinese Yuan', symbol: '¥', flag: 'CN'),
    CurrencyInfo(code: 'INR', nameEn: 'Indian Rupee', symbol: '₹', flag: 'IN'),
    CurrencyInfo(code: 'RUB', nameEn: 'Russian Ruble', symbol: '₽', flag: 'RU'),
    CurrencyInfo(code: 'GBP', nameEn: 'British Pound', symbol: '£', flag: 'GB'),
    CurrencyInfo(code: 'JPY', nameEn: 'Japanese Yen', symbol: '¥', flag: 'JP'),
    CurrencyInfo(code: 'KRW', nameEn: 'South Korean Won', symbol: '₩', flag: 'KR'),
    CurrencyInfo(code: 'UZS', nameEn: 'Uzbekistani Som', symbol: 'so\'m', flag: 'UZ'),
    CurrencyInfo(code: 'IDR', nameEn: 'Indonesian Rupiah', symbol: 'Rp', flag: 'ID'),
    CurrencyInfo(code: 'BRL', nameEn: 'Brazilian Real', symbol: 'R\$', flag: 'BR'),
  ];

  // Reliable baseline rates against 1 USD (used as offline fallback)
  final Map<String, double> _rates = {
    'USD': 1.0,
    'AFN': 68.5,
    'EUR': 0.92,
    'TRY': 36.2,
    'PKR': 278.5,
    'SAR': 3.75,
    'AED': 3.67,
    'IRR': 65000.0, // Toman approx
    'CNY': 7.25,
    'INR': 86.8,
    'RUB': 98.4,
    'GBP': 0.79,
    'JPY': 152.0,
    'KRW': 1420.0,
    'UZS': 12900.0,
    'IDR': 16100.0,
    'BRL': 5.75,
  };

  bool _isFetching = false;
  DateTime? _lastFetchedAt;

  Future<void> fetchLiveRates() async {
    if (_isFetching) return;
    if (_lastFetchedAt != null && DateTime.now().difference(_lastFetchedAt!).inMinutes < 30) {
      return;
    }

    _isFetching = true;
    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['result'] == 'success' && data['rates'] != null) {
          final Map<String, dynamic> apiRates = data['rates'];
          apiRates.forEach((k, v) {
            if (v is num) {
              _rates[k] = v.toDouble();
            }
          });
          // Special fallback for AFN if not in general list
          if (apiRates.containsKey('AFN') && apiRates['AFN'] is num) {
            _rates['AFN'] = (apiRates['AFN'] as num).toDouble();
          }
          _lastFetchedAt = DateTime.now();
          debugPrint('[CurrencyService] Live rates updated successfully!');
        }
      }
    } catch (e) {
      debugPrint('[CurrencyService] Using fallback exchange rates: $e');
    } finally {
      _isFetching = false;
    }
  }

  /// Get currency code associated with the current language code
  String getCurrencyForLanguage(String languageCode) {
    switch (languageCode) {
      case 'fa':
      case 'ps':
        return 'AFN';
      case 'ar':
        return 'SAR';
      case 'tr':
        return 'TRY';
      case 'ur':
        return 'PKR';
      case 'de':
      case 'fr':
      case 'it':
      case 'nl':
      case 'es':
        return 'EUR';
      case 'ru':
        return 'RUB';
      case 'zh':
        return 'CNY';
      case 'hi':
        return 'INR';
      case 'ja':
        return 'JPY';
      case 'ko':
        return 'KRW';
      case 'uz':
        return 'UZS';
      case 'id':
        return 'IDR';
      case 'pt':
        return 'BRL';
      case 'en':
      default:
        return 'USD';
    }
  }

  /// Convert USD amount to target currency
  double convertFromUsd(double usdAmount, String targetCurrency) {
    final rate = _rates[targetCurrency] ?? 1.0;
    return usdAmount * rate;
  }

  /// Format price with proper symbol and formatting
  String format(double usdAmount, String targetCurrency) {
    final converted = convertFromUsd(usdAmount, targetCurrency);
    final currency = supportedCurrencies.firstWhere(
      (c) => c.code == targetCurrency,
      orElse: () => const CurrencyInfo(
        code: 'USD',
        nameEn: 'US Dollar',
        symbol: '\$',
        flag: 'US',
      ),
    );

    if (targetCurrency == 'USD' || targetCurrency == 'EUR' || targetCurrency == 'GBP') {
      return '${currency.symbol}${converted.toStringAsFixed(2)}';
    } else if (targetCurrency == 'IRR' || targetCurrency == 'UZS' || targetCurrency == 'IDR') {
      return '${converted.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} ${currency.symbol}';
    } else {
      return '${converted.toStringAsFixed(1)} ${currency.symbol}';
    }
  }

  CurrencyInfo? getInfo(String code) {
    try {
      return supportedCurrencies.firstWhere((c) => c.code == code);
    } catch (_) {
      return null;
    }
  }
}
