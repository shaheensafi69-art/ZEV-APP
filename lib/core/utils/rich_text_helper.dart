import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/discover/screens/hashtag_feed_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../theme/zev_theme.dart';

/// Renders rich social text with clickable @mentions, #hashtags, and https links,
/// properly managing [TapGestureRecognizer] lifecycles.
class ZevRichText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final List<InlineSpan> prefixSpans;
  final TextDirection? textDirection;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final Color mentionColor;
  final Color hashtagColor;
  final Color linkColor;
  final ValueChanged<String>? onHashtagTap;

  const ZevRichText({
    super.key,
    required this.text,
    required this.style,
    this.prefixSpans = const [],
    this.textDirection,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.mentionColor = ZevColors.secondaryBlue,
    this.hashtagColor = ZevColors.secondaryBlue,
    this.linkColor = ZevColors.primaryBlue,
    this.onHashtagTap,
  });

  @override
  State<ZevRichText> createState() => _ZevRichTextState();
}

class _ZevRichTextState extends State<ZevRichText> {
  static final RegExp _tokenRegex = RegExp(
    r'(@[A-Za-z0-9_.]+|#[A-Za-z0-9_\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]+|https?://[^\s<>()]+)',
  );

  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _bodySpans = [];

  @override
  void initState() {
    super.initState();
    _rebuildBodySpans();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ZevRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.mentionColor != widget.mentionColor ||
        oldWidget.hashtagColor != widget.hashtagColor ||
        oldWidget.linkColor != widget.linkColor) {
      _rebuildBodySpans();
    }
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _registerTap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _openMention(String handle) async {
    HapticFeedback.lightImpact();
    final username = handle.startsWith('@') ? handle.substring(1) : handle;
    if (username.isEmpty) return;
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .ilike('username', username)
          .limit(1)
          .maybeSingle();

      final userId = res?['id']?.toString() ?? '';
      if (!mounted) return;
      if (userId.isNotEmpty) {
        await ProfileScreen.open(context, userId: userId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User @$username not found'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  void _openHashtag(String tag) {
    HapticFeedback.lightImpact();
    final clean = tag.startsWith('#') ? tag.substring(1) : tag;
    if (clean.isEmpty) return;
    if (widget.onHashtagTap != null) {
      widget.onHashtagTap!(clean);
      return;
    }
    HashtagFeedScreen.open(context, tag: clean);
  }

  Future<void> _openUrl(String rawUrl) async {
    HapticFeedback.lightImpact();
    final clean = rawUrl.replaceAll(RegExp(r'[.,!?;:]+$'), '');
    final uri = Uri.tryParse(clean);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _rebuildBodySpans() {
    _disposeRecognizers();

    final spans = <InlineSpan>[];
    final source = widget.text;
    int lastEnd = 0;

    for (final match in _tokenRegex.allMatches(source)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: source.substring(lastEnd, match.start)));
      }
      final token = match.group(0) ?? '';
      if (token.startsWith('@') && token.length > 1) {
        spans.add(
          TextSpan(
            text: token,
            style: TextStyle(
              color: widget.mentionColor,
              fontWeight: FontWeight.w700,
            ),
            recognizer: _registerTap(() => _openMention(token)),
          ),
        );
      } else if (token.startsWith('#') && token.length > 1) {
        spans.add(
          TextSpan(
            text: token,
            style: TextStyle(
              color: widget.hashtagColor,
              fontWeight: FontWeight.w700,
            ),
            recognizer: _registerTap(() => _openHashtag(token)),
          ),
        );
      } else if (token.startsWith('http')) {
        final clean = token.replaceAll(RegExp(r'[.,!?;:]+$'), '');
        final trailing = token.substring(clean.length);
        spans.add(
          TextSpan(
            text: clean,
            style: TextStyle(
              color: widget.linkColor,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: widget.linkColor.withValues(alpha: 0.5),
            ),
            recognizer: _registerTap(() => _openUrl(clean)),
          ),
        );
        if (trailing.isNotEmpty) {
          spans.add(TextSpan(text: trailing));
        }
      } else {
        spans.add(TextSpan(text: token));
      }
      lastEnd = match.end;
    }

    if (lastEnd < source.length) {
      spans.add(TextSpan(text: source.substring(lastEnd)));
    }

    _bodySpans = spans;
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [...widget.prefixSpans, ..._bodySpans],
      ),
      textDirection: widget.textDirection,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
