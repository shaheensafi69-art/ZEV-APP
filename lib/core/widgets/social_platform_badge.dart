import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/zev_theme.dart';

/// Recognized global social media & content platforms.
enum SocialPlatformType {
  instagram,
  tiktok,
  youtube,
  x,
  facebook,
  linkedin,
  telegram,
  whatsapp,
  github,
  discord,
  spotify,
  threads,
  snapchat,
  twitch,
  reddit,
  pinterest,
  medium,
  substack,
  behance,
  dribbble,
  patreon,
  appleMusic,
  soundcloud,
  kick,
  website,
}

/// Metadata model for a recognized platform.
class SocialPlatformInfo {
  final SocialPlatformType type;
  final String displayName;
  final Color brandColor;
  final Gradient? brandGradient;
  final String? domain;
  final String? urlPrefix;

  const SocialPlatformInfo({
    required this.type,
    required this.displayName,
    required this.brandColor,
    this.brandGradient,
    this.domain,
    this.urlPrefix,
  });
}

/// Engine to intelligently detect platforms from arbitrary URLs and titles.
class SocialPlatformDetector {
  static const List<SocialPlatformInfo> presets = [
    SocialPlatformInfo(
      type: SocialPlatformType.instagram,
      displayName: 'Instagram',
      brandColor: Color(0xFFE1306C),
      brandGradient: LinearGradient(
        colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCB045)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      domain: 'instagram.com',
      urlPrefix: 'https://instagram.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.tiktok,
      displayName: 'TikTok',
      brandColor: Color(0xFF000000),
      domain: 'tiktok.com',
      urlPrefix: 'https://tiktok.com/@',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.youtube,
      displayName: 'YouTube',
      brandColor: Color(0xFFFF0000),
      domain: 'youtube.com',
      urlPrefix: 'https://youtube.com/@',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.x,
      displayName: 'X',
      brandColor: Color(0xFF0F1419),
      domain: 'x.com',
      urlPrefix: 'https://x.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.linkedin,
      displayName: 'LinkedIn',
      brandColor: Color(0xFF0A66C2),
      domain: 'linkedin.com',
      urlPrefix: 'https://linkedin.com/in/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.facebook,
      displayName: 'Facebook',
      brandColor: Color(0xFF1877F2),
      domain: 'facebook.com',
      urlPrefix: 'https://facebook.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.telegram,
      displayName: 'Telegram',
      brandColor: Color(0xFF24A1DE),
      domain: 't.me',
      urlPrefix: 'https://t.me/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.whatsapp,
      displayName: 'WhatsApp',
      brandColor: Color(0xFF25D366),
      domain: 'wa.me',
      urlPrefix: 'https://wa.me/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.github,
      displayName: 'GitHub',
      brandColor: Color(0xFF24292F),
      domain: 'github.com',
      urlPrefix: 'https://github.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.discord,
      displayName: 'Discord',
      brandColor: Color(0xFF5865F2),
      domain: 'discord.gg',
      urlPrefix: 'https://discord.gg/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.spotify,
      displayName: 'Spotify',
      brandColor: Color(0xFF1DB954),
      domain: 'spotify.com',
      urlPrefix: 'https://open.spotify.com/user/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.threads,
      displayName: 'Threads',
      brandColor: Color(0xFF101010),
      domain: 'threads.net',
      urlPrefix: 'https://threads.net/@',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.snapchat,
      displayName: 'Snapchat',
      brandColor: Color(0xFFFFFC00),
      domain: 'snapchat.com',
      urlPrefix: 'https://snapchat.com/add/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.twitch,
      displayName: 'Twitch',
      brandColor: Color(0xFF9146FF),
      domain: 'twitch.tv',
      urlPrefix: 'https://twitch.tv/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.reddit,
      displayName: 'Reddit',
      brandColor: Color(0xFFFF4500),
      domain: 'reddit.com',
      urlPrefix: 'https://reddit.com/user/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.pinterest,
      displayName: 'Pinterest',
      brandColor: Color(0xFFE60023),
      domain: 'pinterest.com',
      urlPrefix: 'https://pinterest.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.medium,
      displayName: 'Medium',
      brandColor: Color(0xFF121212),
      domain: 'medium.com',
      urlPrefix: 'https://medium.com/@',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.substack,
      displayName: 'Substack',
      brandColor: Color(0xFFFF6719),
      domain: 'substack.com',
      urlPrefix: 'https://substack.com/@',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.behance,
      displayName: 'Behance',
      brandColor: Color(0xFF1769FF),
      domain: 'behance.net',
      urlPrefix: 'https://behance.net/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.dribbble,
      displayName: 'Dribbble',
      brandColor: Color(0xFFEA4C89),
      domain: 'dribbble.com',
      urlPrefix: 'https://dribbble.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.patreon,
      displayName: 'Patreon',
      brandColor: Color(0xFFFF424D),
      domain: 'patreon.com',
      urlPrefix: 'https://patreon.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.appleMusic,
      displayName: 'Apple Music',
      brandColor: Color(0xFFFA243C),
      domain: 'apple.com',
      urlPrefix: 'https://music.apple.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.soundcloud,
      displayName: 'SoundCloud',
      brandColor: Color(0xFFFF5500),
      domain: 'soundcloud.com',
      urlPrefix: 'https://soundcloud.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.kick,
      displayName: 'Kick',
      brandColor: Color(0xFF53FC18),
      domain: 'kick.com',
      urlPrefix: 'https://kick.com/',
    ),
    SocialPlatformInfo(
      type: SocialPlatformType.website,
      displayName: 'Website',
      brandColor: ZevColors.secondaryBlue,
      domain: '',
      urlPrefix: 'https://',
    ),
  ];

  /// Detect platform from URL, with fallback checking of Title.
  static SocialPlatformInfo detect({String? url, String? title}) {
    final cleanUrl = (url ?? '').trim().toLowerCase();
    final cleanTitle = (title ?? '').trim().toLowerCase();

    // 1. Check URL Domain Patterns
    if (cleanUrl.isNotEmpty) {
      if (cleanUrl.contains('instagram.com') || cleanUrl.contains('instagr.am')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.instagram);
      }
      if (cleanUrl.contains('tiktok.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.tiktok);
      }
      if (cleanUrl.contains('youtube.com') || cleanUrl.contains('youtu.be')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.youtube);
      }
      if (cleanUrl.contains('x.com') ||
          cleanUrl.contains('twitter.com') ||
          cleanUrl.contains('t.co')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.x);
      }
      if (cleanUrl.contains('facebook.com') ||
          cleanUrl.contains('fb.com') ||
          cleanUrl.contains('fb.watch') ||
          cleanUrl.contains('fb.me')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.facebook);
      }
      if (cleanUrl.contains('linkedin.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.linkedin);
      }
      if (cleanUrl.contains('t.me') ||
          cleanUrl.contains('telegram.me') ||
          cleanUrl.contains('telegram.org')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.telegram);
      }
      if (cleanUrl.contains('wa.me') || cleanUrl.contains('whatsapp.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.whatsapp);
      }
      if (cleanUrl.contains('github.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.github);
      }
      if (cleanUrl.contains('discord.gg') || cleanUrl.contains('discord.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.discord);
      }
      if (cleanUrl.contains('spotify.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.spotify);
      }
      if (cleanUrl.contains('threads.net')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.threads);
      }
      if (cleanUrl.contains('snapchat.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.snapchat);
      }
      if (cleanUrl.contains('twitch.tv')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.twitch);
      }
      if (cleanUrl.contains('reddit.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.reddit);
      }
      if (cleanUrl.contains('pinterest.com') || cleanUrl.contains('pin.it')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.pinterest);
      }
      if (cleanUrl.contains('medium.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.medium);
      }
      if (cleanUrl.contains('substack.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.substack);
      }
      if (cleanUrl.contains('behance.net')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.behance);
      }
      if (cleanUrl.contains('dribbble.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.dribbble);
      }
      if (cleanUrl.contains('patreon.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.patreon);
      }
      if (cleanUrl.contains('music.apple.com') ||
          cleanUrl.contains('podcasts.apple.com') ||
          cleanUrl.contains('apple.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.appleMusic);
      }
      if (cleanUrl.contains('soundcloud.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.soundcloud);
      }
      if (cleanUrl.contains('kick.com')) {
        return presets.firstWhere((p) => p.type == SocialPlatformType.kick);
      }
    }

    // 2. Check Title Matches (e.g. if user wrote "Instagram" or "YouTube")
    if (cleanTitle.isNotEmpty) {
      if (cleanTitle == 'instagram' || cleanTitle == 'insta' || cleanTitle == 'ig') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.instagram);
      }
      if (cleanTitle == 'tiktok' || cleanTitle == 'tik tok') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.tiktok);
      }
      if (cleanTitle == 'youtube' || cleanTitle == 'yt') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.youtube);
      }
      if (cleanTitle == 'x' || cleanTitle == 'twitter') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.x);
      }
      if (cleanTitle == 'facebook' || cleanTitle == 'fb') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.facebook);
      }
      if (cleanTitle == 'linkedin') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.linkedin);
      }
      if (cleanTitle == 'telegram' || cleanTitle == 'tg') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.telegram);
      }
      if (cleanTitle == 'whatsapp' || cleanTitle == 'wa') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.whatsapp);
      }
      if (cleanTitle == 'github') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.github);
      }
      if (cleanTitle == 'discord') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.discord);
      }
      if (cleanTitle == 'spotify') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.spotify);
      }
      if (cleanTitle == 'threads') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.threads);
      }
      if (cleanTitle == 'snapchat' || cleanTitle == 'snap') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.snapchat);
      }
      if (cleanTitle == 'twitch') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.twitch);
      }
      if (cleanTitle == 'reddit') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.reddit);
      }
      if (cleanTitle == 'pinterest') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.pinterest);
      }
      if (cleanTitle == 'medium') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.medium);
      }
      if (cleanTitle == 'substack') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.substack);
      }
      if (cleanTitle == 'behance') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.behance);
      }
      if (cleanTitle == 'dribbble') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.dribbble);
      }
      if (cleanTitle == 'patreon') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.patreon);
      }
      if (cleanTitle.contains('apple music') || cleanTitle == 'apple') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.appleMusic);
      }
      if (cleanTitle == 'soundcloud') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.soundcloud);
      }
      if (cleanTitle == 'kick') {
        return presets.firstWhere((p) => p.type == SocialPlatformType.kick);
      }
    }

    // 3. Fallback: Website / Personal Blog
    return presets.last; // website
  }

  /// Extracts host domain (e.g. "shaheensafi.blog" from "https://www.shaheensafi.blog/posts")
  static String extractCleanDomain(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return '';
    var url = rawUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    try {
      final uri = Uri.parse(url);
      var host = uri.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      return host;
    } catch (_) {
      return '';
    }
  }

  /// Returns Google Favicon service URL for a custom domain
  static String? getFaviconUrl(String? rawUrl) {
    final domain = extractCleanDomain(rawUrl);
    if (domain.isEmpty || !domain.contains('.')) return null;
    return 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
  }
}

/// Official pixel-perfect Platform Badge Widget.
/// Renders authentic vector logos for known platforms,
/// and live high-resolution favicons for custom personal websites / blogs.
class SocialPlatformBadge extends StatelessWidget {
  final String? url;
  final String? title;
  final double size;
  final bool showShadow;
  final BorderRadius? borderRadius;

  const SocialPlatformBadge({
    super.key,
    required this.url,
    this.title,
    this.size = 18,
    this.showShadow = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final info = SocialPlatformDetector.detect(url: url, title: title);
    final radius = borderRadius ?? BorderRadius.circular(size * 0.28);

    // If it's a generic website, attempt to load live domain favicon with fallback
    if (info.type == SocialPlatformType.website) {
      final faviconUrl = SocialPlatformDetector.getFaviconUrl(url);
      if (faviconUrl != null) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: Colors.white,
            boxShadow: showShadow
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: faviconUrl,
            fit: BoxFit.contain,
            placeholder: (context, _) => _buildGlobeFallback(size, radius),
            errorWidget: (context, _, error) =>
                _buildGlobeFallback(size, radius),
          ),
        );
      }
      return _buildGlobeFallback(size, radius);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: info.brandGradient == null ? info.brandColor : null,
        gradient: info.brandGradient,
        borderRadius: radius,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: (info.brandGradient != null
                          ? const Color(0xFFE1306C)
                          : info.brandColor)
                      .withValues(alpha: 0.28),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ]
            : null,
      ),
      child: Center(
        child: _buildPlatformGlyph(info.type, size),
      ),
    );
  }

  Widget _buildGlobeFallback(double size, BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0284C7),
        borderRadius: radius,
      ),
      child: Center(
        child: Icon(
          Icons.language_rounded,
          size: size * 0.62,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPlatformGlyph(SocialPlatformType type, double size) {
    final iconSize = size * 0.60;

    switch (type) {
      case SocialPlatformType.instagram:
        return CustomPaint(
          size: Size(size * 0.58, size * 0.58),
          painter: _InstagramGlyphPainter(),
        );

      case SocialPlatformType.tiktok:
        return CustomPaint(
          size: Size(size * 0.56, size * 0.56),
          painter: _TikTokGlyphPainter(),
        );

      case SocialPlatformType.youtube:
        return CustomPaint(
          size: Size(size * 0.56, size * 0.40),
          painter: _PlayTrianglePainter(),
        );

      case SocialPlatformType.x:
        return Text(
          '𝕏',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.62,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            height: 1.0,
          ),
        );

      case SocialPlatformType.linkedin:
        return Text(
          'in',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.55,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            height: 1.0,
          ),
        );

      case SocialPlatformType.facebook:
        return Text(
          'f',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.68,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            height: 1.0,
          ),
        );

      case SocialPlatformType.telegram:
        return Icon(
          Icons.send_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.whatsapp:
        return Icon(
          Icons.call_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.github:
        return Icon(
          Icons.code_rounded,
          size: iconSize * 0.98,
          color: Colors.white,
        );

      case SocialPlatformType.discord:
        return Icon(
          Icons.sports_esports_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.spotify:
        return Icon(
          Icons.graphic_eq_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.threads:
        return Text(
          '@',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.62,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            height: 1.0,
          ),
        );

      case SocialPlatformType.snapchat:
        return Icon(
          Icons.chat_bubble_rounded,
          size: iconSize * 0.92,
          color: Colors.black,
        );

      case SocialPlatformType.twitch:
        return Icon(
          Icons.videogame_asset_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.reddit:
        return Icon(
          Icons.face_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.pinterest:
        return Text(
          'P',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.65,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            fontStyle: FontStyle.italic,
            height: 1.0,
          ),
        );

      case SocialPlatformType.medium:
        return Text(
          'M',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.58,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            height: 1.0,
          ),
        );

      case SocialPlatformType.substack:
        return Icon(
          Icons.bookmark_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.behance:
        return Text(
          'Bē',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.50,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            height: 1.0,
          ),
        );

      case SocialPlatformType.dribbble:
        return Icon(
          Icons.sports_basketball_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.patreon:
        return Text(
          'P',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.62,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            height: 1.0,
          ),
        );

      case SocialPlatformType.appleMusic:
        return Icon(
          Icons.music_note_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.soundcloud:
        return Icon(
          Icons.cloud_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );

      case SocialPlatformType.kick:
        return Text(
          'K',
          style: TextStyle(
            color: Colors.black,
            fontSize: size * 0.62,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            height: 1.0,
          ),
        );

      case SocialPlatformType.website:
        return Icon(
          Icons.language_rounded,
          size: iconSize * 0.95,
          color: Colors.white,
        );
    }
  }
}

/// Custom vector painter for the iconic Instagram camera glyph.
class _InstagramGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12;

    // Outer rounded rect
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.width * 0.28),
    );
    canvas.drawRRect(rrect, paint);

    // Inner circle
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.width * 0.22,
      paint,
    );

    // Dot at top right
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.76, size.height * 0.24),
      size.width * 0.065,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom vector painter for the TikTok musical note glyph with cyan/magenta accents.
class _TikTokGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    final w = size.width;
    final h = size.height;

    // Stem
    path.moveTo(w * 0.52, h * 0.05);
    path.lineTo(w * 0.68, h * 0.05);
    path.cubicTo(w * 0.70, h * 0.24, w * 0.86, h * 0.38, w * 0.98, h * 0.40);
    path.lineTo(w * 0.98, h * 0.56);
    path.cubicTo(w * 0.82, h * 0.55, w * 0.68, h * 0.45, w * 0.68, h * 0.45);
    path.lineTo(w * 0.68, h * 0.72);
    // Note circle bottom
    path.cubicTo(w * 0.68, h * 0.88, w * 0.52, h * 0.98, w * 0.36, h * 0.98);
    path.cubicTo(w * 0.20, h * 0.98, w * 0.06, h * 0.85, w * 0.06, h * 0.69);
    path.cubicTo(w * 0.06, h * 0.53, w * 0.20, h * 0.40, w * 0.36, h * 0.40);
    path.cubicTo(w * 0.42, h * 0.40, w * 0.48, h * 0.42, w * 0.52, h * 0.45);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom vector painter for the YouTube play triangle.
class _PlayTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.12)
      ..lineTo(size.width * 0.80, size.height * 0.50)
      ..lineTo(size.width * 0.28, size.height * 0.88)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
