import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ZevCountry {
  final String name;
  final String code;
  final String dial;

  const ZevCountry({
    required this.name,
    required this.code,
    required this.dial,
  });

  String get flagUrl => 'https://flagcdn.com/w80/${code.toLowerCase()}.png';

  static Widget buildCircularFlag(String countryCode, {double size = 28}) {
    final cleanCode = countryCode.trim().toLowerCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF1F5F9),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: 'https://flagcdn.com/w80/$cleanCode.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: const Color(0xFFE2E8F0)),
          errorWidget: (context, url, error) => const Icon(
            Icons.public_rounded,
            size: 16,
            color: Color(0xFF0284C7),
          ),
        ),
      ),
    );
  }

  static ZevCountry findByNameOrCode(String query, {ZevCountry? fallback}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return fallback ?? allCountries.first;
    for (final c in allCountries) {
      if (c.name.toLowerCase() == q || c.code.toLowerCase() == q) {
        return c;
      }
    }
    for (final c in allCountries) {
      if (c.name.toLowerCase().contains(q)) {
        return c;
      }
    }
    return fallback ?? allCountries.first;
  }

  static Future<ZevCountry?> show(
    BuildContext context, {
    ZevCountry? selected,
  }) async {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<ZevCountry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ZevCountryPickerSheet(selected: selected),
    );
  }

  static final List<ZevCountry> allCountries = const [
    ZevCountry(name: 'Afghanistan', code: 'AF', dial: '+93'),
    ZevCountry(name: 'Albania', code: 'AL', dial: '+355'),
    ZevCountry(name: 'Algeria', code: 'DZ', dial: '+213'),
    ZevCountry(name: 'American Samoa', code: 'AS', dial: '+1684'),
    ZevCountry(name: 'Andorra', code: 'AD', dial: '+376'),
    ZevCountry(name: 'Angola', code: 'AO', dial: '+244'),
    ZevCountry(name: 'Anguilla', code: 'AI', dial: '+1264'),
    ZevCountry(name: 'Antarctica', code: 'AQ', dial: ''),
    ZevCountry(name: 'Antigua and Barbuda', code: 'AG', dial: '+1268'),
    ZevCountry(name: 'Argentina', code: 'AR', dial: '+54'),
    ZevCountry(name: 'Armenia', code: 'AM', dial: '+374'),
    ZevCountry(name: 'Aruba', code: 'AW', dial: '+297'),
    ZevCountry(name: 'Australia', code: 'AU', dial: '+61'),
    ZevCountry(name: 'Austria', code: 'AT', dial: '+43'),
    ZevCountry(name: 'Azerbaijan', code: 'AZ', dial: '+994'),
    ZevCountry(name: 'Bahamas', code: 'BS', dial: '+1242'),
    ZevCountry(name: 'Bahrain', code: 'BH', dial: '+973'),
    ZevCountry(name: 'Bangladesh', code: 'BD', dial: '+880'),
    ZevCountry(name: 'Barbados', code: 'BB', dial: '+1246'),
    ZevCountry(name: 'Belarus', code: 'BY', dial: '+375'),
    ZevCountry(name: 'Belgium', code: 'BE', dial: '+32'),
    ZevCountry(name: 'Belize', code: 'BZ', dial: '+501'),
    ZevCountry(name: 'Benin', code: 'BJ', dial: '+229'),
    ZevCountry(name: 'Bermuda', code: 'BM', dial: '+1441'),
    ZevCountry(name: 'Bhutan', code: 'BT', dial: '+975'),
    ZevCountry(name: 'Bolivia', code: 'BO', dial: '+591'),
    ZevCountry(name: 'Bosnia and Herzegovina', code: 'BA', dial: '+387'),
    ZevCountry(name: 'Botswana', code: 'BW', dial: '+267'),
    ZevCountry(name: 'Bouvet Island', code: 'BV', dial: '+47'),
    ZevCountry(name: 'Brazil', code: 'BR', dial: '+55'),
    ZevCountry(name: 'British Indian Ocean Territory', code: 'IO', dial: '+246'),
    ZevCountry(name: 'British Virgin Islands', code: 'VG', dial: '+1284'),
    ZevCountry(name: 'Brunei', code: 'BN', dial: '+673'),
    ZevCountry(name: 'Bulgaria', code: 'BG', dial: '+359'),
    ZevCountry(name: 'Burkina Faso', code: 'BF', dial: '+226'),
    ZevCountry(name: 'Burundi', code: 'BI', dial: '+257'),
    ZevCountry(name: 'Cambodia', code: 'KH', dial: '+855'),
    ZevCountry(name: 'Cameroon', code: 'CM', dial: '+237'),
    ZevCountry(name: 'Canada', code: 'CA', dial: '+1'),
    ZevCountry(name: 'Cape Verde', code: 'CV', dial: '+238'),
    ZevCountry(name: 'Caribbean Netherlands', code: 'BQ', dial: '+599'),
    ZevCountry(name: 'Cayman Islands', code: 'KY', dial: '+1345'),
    ZevCountry(name: 'Central African Republic', code: 'CF', dial: '+236'),
    ZevCountry(name: 'Chad', code: 'TD', dial: '+235'),
    ZevCountry(name: 'Chile', code: 'CL', dial: '+56'),
    ZevCountry(name: 'China', code: 'CN', dial: '+86'),
    ZevCountry(name: 'Christmas Island', code: 'CX', dial: '+61'),
    ZevCountry(name: 'Cocos (Keeling) Islands', code: 'CC', dial: '+61'),
    ZevCountry(name: 'Colombia', code: 'CO', dial: '+57'),
    ZevCountry(name: 'Comoros', code: 'KM', dial: '+269'),
    ZevCountry(name: 'Congo', code: 'CG', dial: '+242'),
    ZevCountry(name: 'Cook Islands', code: 'CK', dial: '+682'),
    ZevCountry(name: 'Costa Rica', code: 'CR', dial: '+506'),
    ZevCountry(name: 'Croatia', code: 'HR', dial: '+385'),
    ZevCountry(name: 'Cuba', code: 'CU', dial: '+53'),
    ZevCountry(name: 'Curaçao', code: 'CW', dial: '+599'),
    ZevCountry(name: 'Cyprus', code: 'CY', dial: '+357'),
    ZevCountry(name: 'Czechia', code: 'CZ', dial: '+420'),
    ZevCountry(name: 'DR Congo', code: 'CD', dial: '+243'),
    ZevCountry(name: 'Denmark', code: 'DK', dial: '+45'),
    ZevCountry(name: 'Djibouti', code: 'DJ', dial: '+253'),
    ZevCountry(name: 'Dominica', code: 'DM', dial: '+1767'),
    ZevCountry(name: 'Dominican Republic', code: 'DO', dial: '+1'),
    ZevCountry(name: 'Ecuador', code: 'EC', dial: '+593'),
    ZevCountry(name: 'Egypt', code: 'EG', dial: '+20'),
    ZevCountry(name: 'El Salvador', code: 'SV', dial: '+503'),
    ZevCountry(name: 'Equatorial Guinea', code: 'GQ', dial: '+240'),
    ZevCountry(name: 'Eritrea', code: 'ER', dial: '+291'),
    ZevCountry(name: 'Estonia', code: 'EE', dial: '+372'),
    ZevCountry(name: 'Eswatini', code: 'SZ', dial: '+268'),
    ZevCountry(name: 'Ethiopia', code: 'ET', dial: '+251'),
    ZevCountry(name: 'Falkland Islands', code: 'FK', dial: '+500'),
    ZevCountry(name: 'Faroe Islands', code: 'FO', dial: '+298'),
    ZevCountry(name: 'Fiji', code: 'FJ', dial: '+679'),
    ZevCountry(name: 'Finland', code: 'FI', dial: '+358'),
    ZevCountry(name: 'France', code: 'FR', dial: '+33'),
    ZevCountry(name: 'French Guiana', code: 'GF', dial: '+594'),
    ZevCountry(name: 'French Polynesia', code: 'PF', dial: '+689'),
    ZevCountry(name: 'French Southern and Antarctic Lands', code: 'TF', dial: '+262'),
    ZevCountry(name: 'Gabon', code: 'GA', dial: '+241'),
    ZevCountry(name: 'Gambia', code: 'GM', dial: '+220'),
    ZevCountry(name: 'Georgia', code: 'GE', dial: '+995'),
    ZevCountry(name: 'Germany', code: 'DE', dial: '+49'),
    ZevCountry(name: 'Ghana', code: 'GH', dial: '+233'),
    ZevCountry(name: 'Gibraltar', code: 'GI', dial: '+350'),
    ZevCountry(name: 'Greece', code: 'GR', dial: '+30'),
    ZevCountry(name: 'Greenland', code: 'GL', dial: '+299'),
    ZevCountry(name: 'Grenada', code: 'GD', dial: '+1473'),
    ZevCountry(name: 'Guadeloupe', code: 'GP', dial: '+590'),
    ZevCountry(name: 'Guam', code: 'GU', dial: '+1671'),
    ZevCountry(name: 'Guatemala', code: 'GT', dial: '+502'),
    ZevCountry(name: 'Guernsey', code: 'GG', dial: '+44'),
    ZevCountry(name: 'Guinea', code: 'GN', dial: '+224'),
    ZevCountry(name: 'Guinea-Bissau', code: 'GW', dial: '+245'),
    ZevCountry(name: 'Guyana', code: 'GY', dial: '+592'),
    ZevCountry(name: 'Haiti', code: 'HT', dial: '+509'),
    ZevCountry(name: 'Heard Island and McDonald Islands', code: 'HM', dial: ''),
    ZevCountry(name: 'Honduras', code: 'HN', dial: '+504'),
    ZevCountry(name: 'Hong Kong', code: 'HK', dial: '+852'),
    ZevCountry(name: 'Hungary', code: 'HU', dial: '+36'),
    ZevCountry(name: 'Iceland', code: 'IS', dial: '+354'),
    ZevCountry(name: 'India', code: 'IN', dial: '+91'),
    ZevCountry(name: 'Indonesia', code: 'ID', dial: '+62'),
    ZevCountry(name: 'Iran', code: 'IR', dial: '+98'),
    ZevCountry(name: 'Iraq', code: 'IQ', dial: '+964'),
    ZevCountry(name: 'Ireland', code: 'IE', dial: '+353'),
    ZevCountry(name: 'Isle of Man', code: 'IM', dial: '+44'),
    ZevCountry(name: 'Israel', code: 'IL', dial: '+972'),
    ZevCountry(name: 'Italy', code: 'IT', dial: '+39'),
    ZevCountry(name: 'Ivory Coast', code: 'CI', dial: '+225'),
    ZevCountry(name: 'Jamaica', code: 'JM', dial: '+1876'),
    ZevCountry(name: 'Japan', code: 'JP', dial: '+81'),
    ZevCountry(name: 'Jersey', code: 'JE', dial: '+44'),
    ZevCountry(name: 'Jordan', code: 'JO', dial: '+962'),
    ZevCountry(name: 'Kazakhstan', code: 'KZ', dial: '+7'),
    ZevCountry(name: 'Kenya', code: 'KE', dial: '+254'),
    ZevCountry(name: 'Kiribati', code: 'KI', dial: '+686'),
    ZevCountry(name: 'Kosovo', code: 'XK', dial: '+383'),
    ZevCountry(name: 'Kuwait', code: 'KW', dial: '+965'),
    ZevCountry(name: 'Kyrgyzstan', code: 'KG', dial: '+996'),
    ZevCountry(name: 'Laos', code: 'LA', dial: '+856'),
    ZevCountry(name: 'Latvia', code: 'LV', dial: '+371'),
    ZevCountry(name: 'Lebanon', code: 'LB', dial: '+961'),
    ZevCountry(name: 'Lesotho', code: 'LS', dial: '+266'),
    ZevCountry(name: 'Liberia', code: 'LR', dial: '+231'),
    ZevCountry(name: 'Libya', code: 'LY', dial: '+218'),
    ZevCountry(name: 'Liechtenstein', code: 'LI', dial: '+423'),
    ZevCountry(name: 'Lithuania', code: 'LT', dial: '+370'),
    ZevCountry(name: 'Luxembourg', code: 'LU', dial: '+352'),
    ZevCountry(name: 'Macau', code: 'MO', dial: '+853'),
    ZevCountry(name: 'Madagascar', code: 'MG', dial: '+261'),
    ZevCountry(name: 'Malawi', code: 'MW', dial: '+265'),
    ZevCountry(name: 'Malaysia', code: 'MY', dial: '+60'),
    ZevCountry(name: 'Maldives', code: 'MV', dial: '+960'),
    ZevCountry(name: 'Mali', code: 'ML', dial: '+223'),
    ZevCountry(name: 'Malta', code: 'MT', dial: '+356'),
    ZevCountry(name: 'Marshall Islands', code: 'MH', dial: '+692'),
    ZevCountry(name: 'Martinique', code: 'MQ', dial: '+596'),
    ZevCountry(name: 'Mauritania', code: 'MR', dial: '+222'),
    ZevCountry(name: 'Mauritius', code: 'MU', dial: '+230'),
    ZevCountry(name: 'Mayotte', code: 'YT', dial: '+262'),
    ZevCountry(name: 'Mexico', code: 'MX', dial: '+52'),
    ZevCountry(name: 'Micronesia', code: 'FM', dial: '+691'),
    ZevCountry(name: 'Moldova', code: 'MD', dial: '+373'),
    ZevCountry(name: 'Monaco', code: 'MC', dial: '+377'),
    ZevCountry(name: 'Mongolia', code: 'MN', dial: '+976'),
    ZevCountry(name: 'Montenegro', code: 'ME', dial: '+382'),
    ZevCountry(name: 'Montserrat', code: 'MS', dial: '+1664'),
    ZevCountry(name: 'Morocco', code: 'MA', dial: '+212'),
    ZevCountry(name: 'Mozambique', code: 'MZ', dial: '+258'),
    ZevCountry(name: 'Myanmar', code: 'MM', dial: '+95'),
    ZevCountry(name: 'Namibia', code: 'NA', dial: '+264'),
    ZevCountry(name: 'Nauru', code: 'NR', dial: '+674'),
    ZevCountry(name: 'Nepal', code: 'NP', dial: '+977'),
    ZevCountry(name: 'Netherlands', code: 'NL', dial: '+31'),
    ZevCountry(name: 'New Caledonia', code: 'NC', dial: '+687'),
    ZevCountry(name: 'New Zealand', code: 'NZ', dial: '+64'),
    ZevCountry(name: 'Nicaragua', code: 'NI', dial: '+505'),
    ZevCountry(name: 'Niger', code: 'NE', dial: '+227'),
    ZevCountry(name: 'Nigeria', code: 'NG', dial: '+234'),
    ZevCountry(name: 'Niue', code: 'NU', dial: '+683'),
    ZevCountry(name: 'Norfolk Island', code: 'NF', dial: '+672'),
    ZevCountry(name: 'North Korea', code: 'KP', dial: '+850'),
    ZevCountry(name: 'North Macedonia', code: 'MK', dial: '+389'),
    ZevCountry(name: 'Northern Mariana Islands', code: 'MP', dial: '+1670'),
    ZevCountry(name: 'Norway', code: 'NO', dial: '+47'),
    ZevCountry(name: 'Oman', code: 'OM', dial: '+968'),
    ZevCountry(name: 'Pakistan', code: 'PK', dial: '+92'),
    ZevCountry(name: 'Palau', code: 'PW', dial: '+680'),
    ZevCountry(name: 'Palestine', code: 'PS', dial: '+970'),
    ZevCountry(name: 'Panama', code: 'PA', dial: '+507'),
    ZevCountry(name: 'Papua New Guinea', code: 'PG', dial: '+675'),
    ZevCountry(name: 'Paraguay', code: 'PY', dial: '+595'),
    ZevCountry(name: 'Peru', code: 'PE', dial: '+51'),
    ZevCountry(name: 'Philippines', code: 'PH', dial: '+63'),
    ZevCountry(name: 'Pitcairn Islands', code: 'PN', dial: '+64'),
    ZevCountry(name: 'Poland', code: 'PL', dial: '+48'),
    ZevCountry(name: 'Portugal', code: 'PT', dial: '+351'),
    ZevCountry(name: 'Puerto Rico', code: 'PR', dial: '+1'),
    ZevCountry(name: 'Qatar', code: 'QA', dial: '+974'),
    ZevCountry(name: 'Romania', code: 'RO', dial: '+40'),
    ZevCountry(name: 'Russia', code: 'RU', dial: '+7'),
    ZevCountry(name: 'Rwanda', code: 'RW', dial: '+250'),
    ZevCountry(name: 'Réunion', code: 'RE', dial: '+262'),
    ZevCountry(name: 'Saint Barthélemy', code: 'BL', dial: '+590'),
    ZevCountry(name: 'Saint Helena, Ascension and Tristan da Cunha', code: 'SH', dial: '+2'),
    ZevCountry(name: 'Saint Kitts and Nevis', code: 'KN', dial: '+1869'),
    ZevCountry(name: 'Saint Lucia', code: 'LC', dial: '+1758'),
    ZevCountry(name: 'Saint Martin', code: 'MF', dial: '+590'),
    ZevCountry(name: 'Saint Pierre and Miquelon', code: 'PM', dial: '+508'),
    ZevCountry(name: 'Saint Vincent and the Grenadines', code: 'VC', dial: '+1784'),
    ZevCountry(name: 'Samoa', code: 'WS', dial: '+685'),
    ZevCountry(name: 'San Marino', code: 'SM', dial: '+378'),
    ZevCountry(name: 'Saudi Arabia', code: 'SA', dial: '+966'),
    ZevCountry(name: 'Senegal', code: 'SN', dial: '+221'),
    ZevCountry(name: 'Serbia', code: 'RS', dial: '+381'),
    ZevCountry(name: 'Seychelles', code: 'SC', dial: '+248'),
    ZevCountry(name: 'Sierra Leone', code: 'SL', dial: '+232'),
    ZevCountry(name: 'Singapore', code: 'SG', dial: '+65'),
    ZevCountry(name: 'Sint Maarten', code: 'SX', dial: '+1721'),
    ZevCountry(name: 'Slovakia', code: 'SK', dial: '+421'),
    ZevCountry(name: 'Slovenia', code: 'SI', dial: '+386'),
    ZevCountry(name: 'Solomon Islands', code: 'SB', dial: '+677'),
    ZevCountry(name: 'Somalia', code: 'SO', dial: '+252'),
    ZevCountry(name: 'South Africa', code: 'ZA', dial: '+27'),
    ZevCountry(name: 'South Georgia', code: 'GS', dial: '+500'),
    ZevCountry(name: 'South Korea', code: 'KR', dial: '+82'),
    ZevCountry(name: 'South Sudan', code: 'SS', dial: '+211'),
    ZevCountry(name: 'Spain', code: 'ES', dial: '+34'),
    ZevCountry(name: 'Sri Lanka', code: 'LK', dial: '+94'),
    ZevCountry(name: 'Sudan', code: 'SD', dial: '+249'),
    ZevCountry(name: 'Suriname', code: 'SR', dial: '+597'),
    ZevCountry(name: 'Svalbard and Jan Mayen', code: 'SJ', dial: '+4779'),
    ZevCountry(name: 'Sweden', code: 'SE', dial: '+46'),
    ZevCountry(name: 'Switzerland', code: 'CH', dial: '+41'),
    ZevCountry(name: 'Syria', code: 'SY', dial: '+963'),
    ZevCountry(name: 'São Tomé and Príncipe', code: 'ST', dial: '+239'),
    ZevCountry(name: 'Taiwan', code: 'TW', dial: '+886'),
    ZevCountry(name: 'Tajikistan', code: 'TJ', dial: '+992'),
    ZevCountry(name: 'Tanzania', code: 'TZ', dial: '+255'),
    ZevCountry(name: 'Thailand', code: 'TH', dial: '+66'),
    ZevCountry(name: 'Timor-Leste', code: 'TL', dial: '+670'),
    ZevCountry(name: 'Togo', code: 'TG', dial: '+228'),
    ZevCountry(name: 'Tokelau', code: 'TK', dial: '+690'),
    ZevCountry(name: 'Tonga', code: 'TO', dial: '+676'),
    ZevCountry(name: 'Trinidad and Tobago', code: 'TT', dial: '+1868'),
    ZevCountry(name: 'Tunisia', code: 'TN', dial: '+216'),
    ZevCountry(name: 'Turkmenistan', code: 'TM', dial: '+993'),
    ZevCountry(name: 'Turks and Caicos Islands', code: 'TC', dial: '+1649'),
    ZevCountry(name: 'Tuvalu', code: 'TV', dial: '+688'),
    ZevCountry(name: 'Türkiye', code: 'TR', dial: '+90'),
    ZevCountry(name: 'Uganda', code: 'UG', dial: '+256'),
    ZevCountry(name: 'Ukraine', code: 'UA', dial: '+380'),
    ZevCountry(name: 'United Arab Emirates', code: 'AE', dial: '+971'),
    ZevCountry(name: 'United Kingdom', code: 'GB', dial: '+44'),
    ZevCountry(name: 'United States', code: 'US', dial: '+1'),
    ZevCountry(name: 'United States Minor Outlying Islands', code: 'UM', dial: '+268'),
    ZevCountry(name: 'United States Virgin Islands', code: 'VI', dial: '+1340'),
    ZevCountry(name: 'Uruguay', code: 'UY', dial: '+598'),
    ZevCountry(name: 'Uzbekistan', code: 'UZ', dial: '+998'),
    ZevCountry(name: 'Vanuatu', code: 'VU', dial: '+678'),
    ZevCountry(name: 'Vatican City', code: 'VA', dial: '+3'),
    ZevCountry(name: 'Venezuela', code: 'VE', dial: '+58'),
    ZevCountry(name: 'Vietnam', code: 'VN', dial: '+84'),
    ZevCountry(name: 'Wallis and Futuna', code: 'WF', dial: '+681'),
    ZevCountry(name: 'Western Sahara', code: 'EH', dial: '+2'),
    ZevCountry(name: 'Yemen', code: 'YE', dial: '+967'),
    ZevCountry(name: 'Zambia', code: 'ZM', dial: '+260'),
    ZevCountry(name: 'Zimbabwe', code: 'ZW', dial: '+263'),
    ZevCountry(name: 'Åland Islands', code: 'AX', dial: '+35818'),
];
}

class _ZevCountryPickerSheet extends StatefulWidget {
  final ZevCountry? selected;

  const _ZevCountryPickerSheet({this.selected});

  @override
  State<_ZevCountryPickerSheet> createState() => _ZevCountryPickerSheetState();
}

class _ZevCountryPickerSheetState extends State<_ZevCountryPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<ZevCountry> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = ZevCountry.allCountries;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = ZevCountry.allCountries;
      } else {
        _filtered = ZevCountry.allCountries.where((c) {
          return c.name.toLowerCase().contains(q) ||
              c.code.toLowerCase().contains(q) ||
              c.dial.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Country',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Search country or dial code...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Country list
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No matching countries found',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filtered.length,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemBuilder: (ctx, idx) {
                      final c = _filtered[idx];
                      final isSel = widget.selected?.code == c.code;

                      return InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context, c);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          color: isSel ? const Color(0xFF00D4FF).withValues(alpha: 0.08) : Colors.transparent,
                          child: Row(
                            children: [
                              ZevCountry.buildCircularFlag(c.code, size: 30),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: isSel ? FontWeight.w900 : FontWeight.w700,
                                    color: isSel ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (c.dial.isNotEmpty) ...[
                                Text(
                                  c.dial,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              if (isSel)
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF00D4FF), size: 20)
                              else
                                const SizedBox(width: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
