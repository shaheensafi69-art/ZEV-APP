import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/zev_theme.dart';

/// Type of interactive Story Sticker.
enum StoryStickerType { poll, question, link }

/// Data representation of an interactive story sticker.
class StoryStickerData {
  final String id;
  final StoryStickerType type;
  final String title;
  final String optionA;
  final String optionB;
  final int votesA;
  final int votesB;
  final String linkUrl;
  final String linkTitle;

  const StoryStickerData({
    required this.id,
    required this.type,
    this.title = '',
    this.optionA = 'Yes',
    this.optionB = 'No',
    this.votesA = 0,
    this.votesB = 0,
    this.linkUrl = '',
    this.linkTitle = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'option_a': optionA,
        'option_b': optionB,
        'votes_a': votesA,
        'votes_b': votesB,
        'link_url': linkUrl,
        'link_title': linkTitle,
      };

  factory StoryStickerData.fromJson(Map<String, dynamic> json) {
    StoryStickerType t = StoryStickerType.poll;
    if (json['type'] == 'question') t = StoryStickerType.question;
    if (json['type'] == 'link') t = StoryStickerType.link;

    return StoryStickerData(
      id: json['id']?.toString() ?? '',
      type: t,
      title: json['title']?.toString() ?? '',
      optionA: json['option_a']?.toString() ?? 'Yes',
      optionB: json['option_b']?.toString() ?? 'No',
      votesA: (json['votes_a'] as num?)?.toInt() ?? 0,
      votesB: (json['votes_b'] as num?)?.toInt() ?? 0,
      linkUrl: json['link_url']?.toString() ?? '',
      linkTitle: json['link_title']?.toString() ?? '',
    );
  }
}

/// Modal Sheet to pick and configure an interactive sticker in Story Studio.
class StoryStickersSheet extends StatefulWidget {
  const StoryStickersSheet({super.key});

  static Future<StoryStickerData?> show(BuildContext context) {
    return showModalBottomSheet<StoryStickerData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const StoryStickersSheet(),
    );
  }

  @override
  State<StoryStickersSheet> createState() => _StoryStickersSheetState();
}

class _StoryStickersSheetState extends State<StoryStickersSheet> {
  StoryStickerType _selectedType = StoryStickerType.poll;

  final TextEditingController _titleCtrl = TextEditingController(text: "Do you like this?");
  final TextEditingController _optACtrl = TextEditingController(text: "Yes 🔥");
  final TextEditingController _optBCtrl = TextEditingController(text: "No 🤔");

  final TextEditingController _questionCtrl = TextEditingController(text: "Ask me a question...");
  final TextEditingController _linkUrlCtrl = TextEditingController(text: "https://");
  final TextEditingController _linkTitleCtrl = TextEditingController(text: "Visit Link ↗");

  @override
  void dispose() {
    _titleCtrl.dispose();
    _optACtrl.dispose();
    _optBCtrl.dispose();
    _questionCtrl.dispose();
    _linkUrlCtrl.dispose();
    _linkTitleCtrl.dispose();
    super.dispose();
  }

  void _done() {
    HapticFeedback.mediumImpact();
    final id = 'stk_${DateTime.now().microsecondsSinceEpoch}';

    StoryStickerData data;
    switch (_selectedType) {
      case StoryStickerType.poll:
        data = StoryStickerData(
          id: id,
          type: StoryStickerType.poll,
          title: _titleCtrl.text.trim().isEmpty ? "Poll" : _titleCtrl.text.trim(),
          optionA: _optACtrl.text.trim().isEmpty ? "Yes" : _optACtrl.text.trim(),
          optionB: _optBCtrl.text.trim().isEmpty ? "No" : _optBCtrl.text.trim(),
        );
        break;
      case StoryStickerType.question:
        data = StoryStickerData(
          id: id,
          type: StoryStickerType.question,
          title: _questionCtrl.text.trim().isEmpty ? "Ask me anything..." : _questionCtrl.text.trim(),
        );
        break;
      case StoryStickerType.link:
        data = StoryStickerData(
          id: id,
          type: StoryStickerType.link,
          linkUrl: _linkUrlCtrl.text.trim(),
          linkTitle: _linkTitleCtrl.text.trim().isEmpty ? "Visit Link ↗" : _linkTitleCtrl.text.trim(),
        );
        break;
    }

    Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.sticky_note_2_rounded, color: ZevColors.primaryBlue),
                const SizedBox(width: 8),
                const Text(
                  'Story Stickers',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _done,
                  child: const Text(
                    'Add Sticker',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0284C7),
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sticker Types Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                _buildTypeTab('📊 Poll', StoryStickerType.poll),
                const SizedBox(width: 8),
                _buildTypeTab('💬 Question', StoryStickerType.question),
                const SizedBox(width: 8),
                _buildTypeTab('🔗 Link', StoryStickerType.link),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Editor for selected type
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildTypeEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeTab(String label, StoryStickerType type) {
    final isSel = _selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedType = type);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSel ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSel ? Colors.white : const Color(0xFF334155),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeEditor() {
    switch (_selectedType) {
      case StoryStickerType.poll:
        return Column(
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: "Question / Poll Title",
                hintText: "Ask something...",
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _optACtrl,
                    decoration: InputDecoration(
                      labelText: "Option 1",
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _optBCtrl,
                    decoration: InputDecoration(
                      labelText: "Option 2",
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case StoryStickerType.question:
        return TextField(
          controller: _questionCtrl,
          decoration: InputDecoration(
            labelText: "Question Box Prompt",
            hintText: "Ask me a question...",
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      case StoryStickerType.link:
        return Column(
          children: [
            TextField(
              controller: _linkUrlCtrl,
              decoration: InputDecoration(
                labelText: "URL (https://...)",
                hintText: "https://yourwebsite.com",
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _linkTitleCtrl,
              decoration: InputDecoration(
                labelText: "Sticker Button Text",
                hintText: "e.g. Visit Store ↗",
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        );
    }
  }
}

/// Interactive Story Sticker Renderer (Displays inside Story Viewer & Creator).
class InteractiveStorySticker extends StatefulWidget {
  final StoryStickerData sticker;
  final bool isInteractive;

  const InteractiveStorySticker({
    super.key,
    required this.sticker,
    this.isInteractive = true,
  });

  @override
  State<InteractiveStorySticker> createState() => _InteractiveStoryStickerState();
}

class _InteractiveStoryStickerState extends State<InteractiveStorySticker> {
  int? _votedOption;
  late int _countA;
  late int _countB;

  @override
  void initState() {
    super.initState();
    _countA = widget.sticker.votesA;
    _countB = widget.sticker.votesB;
  }

  void _vote(int option) {
    if (!widget.isInteractive || _votedOption != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _votedOption = option;
      if (option == 1) _countA++;
      if (option == 2) _countB++;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.sticker.type) {
      case StoryStickerType.poll:
        final total = _countA + _countB;
        final pctA = total > 0 ? ((_countA / total) * 100).round() : 50;
        final pctB = total > 0 ? 100 - pctA : 50;

        return Container(
          width: 250,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.sticker.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildPollOption(
                      label: widget.sticker.optionA,
                      percent: pctA,
                      isVoted: _votedOption == 1,
                      onTap: () => _vote(1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPollOption(
                      label: widget.sticker.optionB,
                      percent: pctB,
                      isVoted: _votedOption == 2,
                      onTap: () => _vote(2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case StoryStickerType.question:
        return Container(
          width: 250,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.sticker.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Type something...',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
              ),
            ],
          ),
        );

      case StoryStickerType.link:
        return GestureDetector(
          onTap: () async {
            if (!widget.isInteractive) return;
            final url = Uri.tryParse(widget.sticker.linkUrl);
            if (url != null) {
              HapticFeedback.lightImpact();
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.link_rounded,
                  color: Color(0xFF0284C7),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.sticker.linkTitle.isNotEmpty
                      ? widget.sticker.linkTitle
                      : 'Visit Link ↗',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildPollOption({
    required String label,
    required int percent,
    required bool isVoted,
    required VoidCallback onTap,
  }) {
    final showPct = _votedOption != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isVoted ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
            width: isVoted ? 1.8 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showPct)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percent / 100,
                  child: Container(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  if (showPct) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
