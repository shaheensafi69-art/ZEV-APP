import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_skeleton.dart';

/// Light Clearmorphic Close Friends manager bottom sheet backed by
/// `get_close_friends_profiles(p_query)` and `toggle_close_friend(p_friend_id)`.
class CloseFriendsSheet extends StatefulWidget {
  const CloseFriendsSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CloseFriendsSheet(),
    );
  }

  @override
  State<CloseFriendsSheet> createState() => _CloseFriendsSheetState();
}

class _CloseFriendsSheetState extends State<CloseFriendsSheet> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  Timer? _debounce;
  List<Map<String, dynamic>> _profiles = [];
  final Set<String> _togglingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles([String query = '']) async {
    try {
      final raw = await _supabase.rpc(
        'get_close_friends_profiles',
        params: {'p_query': query.trim()},
      );
      final list = (raw is List)
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _profiles = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Close friends fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      _loadProfiles(val);
    });
  }

  Future<void> _toggleFriend(int index) async {
    final p = _profiles[index];
    final id = p['id']?.toString() ?? '';
    if (id.isEmpty || _togglingIds.contains(id)) return;

    HapticFeedback.selectionClick();
    final prev = p['is_close_friend'] == true;
    setState(() {
      _togglingIds.add(id);
      _profiles[index] = {...p, 'is_close_friend': !prev};
    });

    try {
      final res = await _supabase.rpc(
        'toggle_close_friend',
        params: {'p_friend_id': id},
      );
      final next = res is Map ? res['is_close_friend'] == true : !prev;
      if (mounted) {
        setState(() {
          _togglingIds.remove(id);
          final curIdx = _profiles.indexWhere((e) => e['id']?.toString() == id);
          if (curIdx != -1) {
            _profiles[curIdx] = {..._profiles[curIdx], 'is_close_friend': next};
          }
        });
      }
    } catch (e) {
      debugPrint('Toggle close friend error: $e');
      if (mounted) {
        setState(() {
          _togglingIds.remove(id);
          final curIdx = _profiles.indexWhere((e) => e['id']?.toString() == id);
          if (curIdx != -1) {
            _profiles[curIdx] = {..._profiles[curIdx], 'is_close_friend': prev};
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final closeCount = _profiles
        .where((p) => p['is_close_friend'] == true)
        .length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: ZevColors.softSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ZevColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ZevColors.successGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: ZevColors.successGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Close Friends',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                        Text(
                          '$closeCount selected • People won\'t be notified when you edit',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: ZevColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: ZevColors.secondaryBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search box
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: ZevColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ZevColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: ZevColors.textMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ZevColors.deepNavy,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search friends to add...',
                          hintStyle: TextStyle(
                            fontSize: 13.5,
                            color: ZevColors.textMuted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: ZevColors.textMuted,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadProfiles('');
                        },
                      ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: _isLoading
                  ? ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: 6,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, _) => const ZevSkeleton(
                        width: double.infinity,
                        height: 62,
                      ),
                    )
                  : _profiles.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No matching profiles found. Search by username or follow more friends.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: ZevColors.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _profiles.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final p = _profiles[index];
                            final id = p['id']?.toString() ?? '';
                            final username = (p['username'] ?? 'user').toString();
                            final full =
                                '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                                    .trim();
                            final avatar = (p['avatar_url'] ?? '').toString();
                            final isVerified = p['is_verified'] == true;
                            final isClose = p['is_close_friend'] == true;
                            final isBusy = _togglingIds.contains(id);

                            return InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _toggleFriend(index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: ZevColors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isClose
                                        ? ZevColors.successGreen.withValues(
                                            alpha: 0.45,
                                          )
                                        : ZevColors.border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    avatar.isNotEmpty
                                        ? ZevCachedImage.avatar(
                                            imageUrl: avatar,
                                            size: 42,
                                          )
                                        : Container(
                                            width: 42,
                                            height: 42,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: ZevColors.softSurface,
                                            ),
                                            child: const Icon(
                                              Icons.person_rounded,
                                              color: ZevColors.textMuted,
                                              size: 22,
                                            ),
                                          ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  '@$username',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                    color: ZevColors.deepNavy,
                                                  ),
                                                ),
                                              ),
                                              if (isVerified) ...[
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.verified_rounded,
                                                  size: 14,
                                                  color: ZevColors.primaryBlue,
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (full.isNotEmpty)
                                            Text(
                                              full,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: ZevColors.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isClose
                                            ? ZevColors.successGreen
                                            : ZevColors.softSurface,
                                        border: Border.all(
                                          color: isClose
                                              ? ZevColors.successGreen
                                              : ZevColors.border,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: isBusy
                                          ? const Padding(
                                              padding: EdgeInsets.all(6),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: ZevColors.primaryBlue,
                                              ),
                                            )
                                          : Icon(
                                              isClose
                                                  ? Icons.check_rounded
                                                  : Icons.add_rounded,
                                              size: 16,
                                              color: isClose
                                                  ? Colors.white
                                                  : ZevColors.textMuted,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
