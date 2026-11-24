import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../profile/screens/zev_coins_screen.dart';

class PostTipSheet extends StatefulWidget {
  final String authorId;
  final String authorUsername;
  final String authorFullName;
  final String? authorAvatar;
  final String? postId;
  final String? reelId;

  const PostTipSheet({
    super.key,
    required this.authorId,
    required this.authorUsername,
    required this.authorFullName,
    this.authorAvatar,
    this.postId,
    this.reelId,
  });

  static Future<bool?> open(
    BuildContext context, {
    required String authorId,
    required String authorUsername,
    required String authorFullName,
    String? authorAvatar,
    String? postId,
    String? reelId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PostTipSheet(
        authorId: authorId,
        authorUsername: authorUsername,
        authorFullName: authorFullName,
        authorAvatar: authorAvatar,
        postId: postId,
        reelId: reelId,
      ),
    );
  }

  @override
  State<PostTipSheet> createState() => _PostTipSheetState();
}

class _PostTipSheetState extends State<PostTipSheet>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  int _selectedAmount = 20;
  final TextEditingController _customCtrl = TextEditingController();
  bool _isCustom = false;
  bool _isSubmitting = false;
  int _myBalance = 0;
  bool _isLoadingBalance = true;

  late final AnimationController _animCtrl;

  final List<int> _presetAmounts = [5, 20, 50, 100, 250, 500];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadBalance();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final res = await _supabase
          .from('profiles')
          .select('coins_balance')
          .eq('id', uid)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _myBalance = (res['coins_balance'] as num?)?.toInt() ?? 0;
          _isLoadingBalance = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingBalance = false);
    }
  }

  int get _tipAmount {
    if (_isCustom) {
      final parsed = int.tryParse(_customCtrl.text.trim()) ?? 0;
      return parsed > 0 ? parsed : 0;
    }
    return _selectedAmount;
  }

  Future<void> _submitTip() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    if (myId == widget.authorId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You cannot send a tip to your own content.")),
      );
      return;
    }

    final coins = _tipAmount;
    if (coins <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid coin amount.")),
      );
      return;
    }

    if (_myBalance < coins) {
      HapticFeedback.vibrate();
      final goRecharge = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text("Insufficient Coins", style: TextStyle(fontWeight: FontWeight.w900)),
          content: Text(
            "You have $_myBalance Coins. You need $coins Coins to send this tip. Would you like to recharge now?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Recharge Coins"),
            ),
          ],
        ),
      );

      if (goRecharge == true && mounted) {
        ZevCoinsScreen.open(context);
      }
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.heavyImpact();

    try {
      // 40% of sent coins goes to recipient as cashable balance (per platform rule)
      final creatorEarned = (coins * 0.40).round();
      final netEarned = creatorEarned > 0 ? creatorEarned : 1;

      // 1. Deduct from sender
      final newSenderBalance = _myBalance - coins;
      await _supabase.from('profiles').update({
        'coins_balance': newSenderBalance,
      }).eq('id', myId);

      // 2. Credit to recipient (40%)
      try {
        final creatorProf = await _supabase
            .from('profiles')
            .select('coins_balance')
            .eq('id', widget.authorId)
            .single();
        final currentCreatorBalance = (creatorProf['coins_balance'] as num?)?.toInt() ?? 0;
        await _supabase.from('profiles').update({
          'coins_balance': currentCreatorBalance + netEarned,
        }).eq('id', widget.authorId);
      } catch (_) {}

      // 3. Record tip in transactions log
      try {
        await _supabase.from('coin_transactions').insert({
          'sender_id': myId,
          'recipient_id': widget.authorId,
          'coins': coins,
          'creator_received': netEarned,
          'transaction_type': widget.reelId != null ? 'reel_tip' : 'post_tip',
          'post_id': widget.postId,
          'reel_id': widget.reelId,
          'status': 'completed',
        });
      } catch (_) {}

      // 4. Send notification to creator
      try {
        await _supabase.from('notifications').insert({
          'user_id': widget.authorId,
          'actor_id': myId,
          'type': 'tip',
          'content': 'sent you a tip of $coins Coins! (+$netEarned added to your balance)',
          'entity_id': widget.reelId ?? widget.postId,
        });
      } catch (_) {}

      if (mounted) {
        _animCtrl.forward();
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0F172A),
              content: Row(
                children: [
                  const Icon(Icons.stars_rounded, color: Color(0xFFEAB308)),
                  const SizedBox(width: 8),
                  Text("Tipped $coins Coins to @${widget.authorUsername}!"),
                ],
              ),
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tip failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        14,
        22,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, -6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF0284C7),
                backgroundImage: widget.authorAvatar != null
                    ? CachedNetworkImageProvider(widget.authorAvatar!)
                    : null,
                child: widget.authorAvatar == null
                    ? Text(
                        widget.authorUsername.isNotEmpty
                            ? widget.authorUsername[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Tip @${widget.authorUsername}",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Support great creators directly with ZEV Coins",
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              // Coins balance pill
              GestureDetector(
                onTap: () => ZevCoinsScreen.open(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monetization_on_rounded, color: Color(0xFFEAB308), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _isLoadingBalance ? "..." : "$_myBalance",
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.add_circle, color: Color(0xFF0284C7), size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // Amount Grid Chips
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._presetAmounts.map((amt) {
                final isSelected = !_isCustom && _selectedAmount == amt;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars_rounded, color: Color(0xFFEAB308), size: 15),
                      const SizedBox(width: 5),
                      Text("$amt Coins"),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF0284C7),
                  backgroundColor: const Color(0xFFF8FAFC),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                    width: 1.5,
                  ),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isCustom = false;
                      _selectedAmount = amt;
                    });
                  },
                );
              }),
              ChoiceChip(
                label: const Text("Custom"),
                selected: _isCustom,
                selectedColor: const Color(0xFF0284C7),
                backgroundColor: const Color(0xFFF8FAFC),
                labelStyle: TextStyle(
                  color: _isCustom ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: BorderSide(
                  color: _isCustom ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                  width: 1.5,
                ),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _isCustom = true);
                },
              ),
            ],
          ),

          if (_isCustom) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _customCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A)),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.stars_rounded, color: Color(0xFFEAB308)),
                hintText: "Enter coin amount (e.g. 300)",
                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],

          const SizedBox(height: 14),

          // Platform split info note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Creator receives 40% in withdrawable balance: +${(_tipAmount * 0.40).round()} Coins.",
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Submit Tip Button
          ElevatedButton(
            onPressed: (_isSubmitting || _tipAmount <= 0) ? null : _submitTip,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "Send Tip ($_tipAmount Coins)",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
