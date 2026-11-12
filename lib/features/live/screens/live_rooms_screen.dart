import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../../profile/screens/profile_screen.dart';
import 'live_room_screen.dart';

/// Interactive ZEV Live Chat & Presence Rooms Lobby (Supabase Realtime).
/// 100% Light Clearmorphic UI with live room discovery, category filtering,
/// Realtime updates on `live_streams`, and host room creation.
class LiveRoomsScreen extends StatefulWidget {
  const LiveRoomsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LiveRoomsScreen()),
    );
  }

  @override
  State<LiveRoomsScreen> createState() => _LiveRoomsScreenState();
}

class _LiveRoomsScreenState extends State<LiveRoomsScreen> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  static const List<String> _categories = [
    'All',
    'General',
    'Q&A',
    'Tech',
    'Music',
    'Community',
  ];

  bool _isLoading = true;
  String? _errorMsg;
  String _selectedCategory = 'All';
  List<Map<String, dynamic>> _rooms = [];
  Map<String, Map<String, dynamic>> _hostProfiles = {};
  RealtimeChannel? _lobbyChannel;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadRooms();
    _subscribeLobby();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    final channel = _lobbyChannel;
    _lobbyChannel = null;
    if (channel != null) {
      unawaited(channel.unsubscribe());
    }
    super.dispose();
  }

  void _subscribeLobby() {
    try {
      _lobbyChannel = _supabase
          .channel('live_rooms_lobby')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'live_streams',
            callback: (_) {
              _debounceTimer?.cancel();
              _debounceTimer = Timer(
                const Duration(milliseconds: 280),
                () => unawaited(_loadRooms(silent: true)),
              );
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[LiveRoomsScreen] subscribeLobby notice: $e');
    }
  }

  Future<void> _loadRooms({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }

    try {
      final safety = await SocialGraphService.instance.fetchSafetyFilters();
      final res = await _supabase
          .from('live_streams')
          .select()
          .eq('status', 'live')
          .order('started_at', ascending: false)
          .limit(50);

      final rawRooms = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((r) {
            final hostId = r['host_id']?.toString() ?? '';
            return hostId.isNotEmpty && !safety.blockedUserIds.contains(hostId);
          })
          .toList();

      final hostIds = rawRooms
          .map((r) => r['host_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final profilesMap = <String, Map<String, dynamic>>{};
      if (hostIds.isNotEmpty) {
        final profRes = await _supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified, is_banned, account_status',
            )
            .inFilter('id', hostIds);

        for (final item in (profRes as List)) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final id = m['id']?.toString() ?? '';
            final isBanned = m['is_banned'] == true;
            final accountStatus = (m['account_status'] ?? 'active').toString();
            if (id.isNotEmpty && !isBanned && accountStatus == 'active') {
              profilesMap[id] = m;
            }
          }
        }
      }

      final visibleRooms = rawRooms
          .where((r) => profilesMap.containsKey(r['host_id']?.toString()))
          .toList();

      if (!mounted) return;
      setState(() {
        _rooms = visibleRooms;
        _hostProfiles = profilesMap;
        _isLoading = false;
        _errorMsg = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMsg = 'Could not load live rooms: $e';
      });
    }
  }

  void _openStartRoomModal() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showToast('Please sign in to start a Live Room.', isError: true);
      return;
    }

    HapticFeedback.lightImpact();
    final titleCtrl = TextEditingController();
    String selectedCategory = 'General';
    File? coverFile;
    bool isStarting = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

          return Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
            decoration: const BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              border: Border.fromBorderSide(
                BorderSide(color: Colors.white, width: 1.5),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: ZevColors.brandGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.podcasts_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Live Chat & Presence Room',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            Text(
                              'Real-time group chat, emoji reactions & live presence',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: ZevColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Room Topic / Title',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ZevColors.border, width: 1.2),
                    ),
                    child: TextField(
                      controller: titleCtrl,
                      maxLength: 120,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.deepNavy,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'What are we talking about right now?',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: ZevColors.textMuted,
                        ),
                        border: InputBorder.none,
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.where((c) => c != 'All').map((cat) {
                      final selected = selectedCategory == cat;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setModalState(() => selectedCategory = cat);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? ZevColors.secondaryBlue
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? ZevColors.secondaryBlue
                                  : ZevColors.border,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color:
                                  selected ? Colors.white : ZevColors.deepNavy,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isStarting
                              ? null
                              : () async {
                                  final picked = await _picker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 85,
                                  );
                                  if (picked != null && ctx.mounted) {
                                    setModalState(
                                      () => coverFile = File(picked.path),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: Text(
                            coverFile == null
                                ? 'Add Optional Cover'
                                : 'Change Cover Photo',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ZevColors.deepNavy,
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: ZevColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      if (coverFile != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: isStarting
                              ? null
                              : () => setModalState(() => coverFile = null),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: ZevColors.errorRed,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (coverFile != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        coverFile!,
                        width: double.infinity,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  if (modalError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      modalError!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.errorRed,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isStarting
                          ? null
                          : () async {
                              final title = titleCtrl.text.trim();
                              if (title.length < 2) {
                                setModalState(() {
                                  modalError =
                                      'Enter a room title (at least 2 characters).';
                                });
                                return;
                              }

                              setModalState(() {
                                isStarting = true;
                                modalError = null;
                              });

                              String? uploadedThumb;
                              try {
                                if (coverFile != null) {
                                  final ts =
                                      DateTime.now().millisecondsSinceEpoch;
                                  final ext = coverFile!.path.contains('.')
                                      ? coverFile!.path
                                          .split('.')
                                          .last
                                          .toLowerCase()
                                      : 'jpg';
                                  uploadedThumb = await CloudflareStorageService
                                      .instance
                                      .upload(
                                    bucket: 'covers',
                                    path: 'live_${user.id}_$ts.$ext',
                                    file: coverFile!,
                                  );
                                }

                                final rawStream = await _supabase.rpc(
                                  'start_live_stream',
                                  params: {
                                    'p_title': title,
                                    'p_category': selectedCategory,
                                    'p_thumbnail_url': uploadedThumb,
                                  },
                                );
                                final streamMap = rawStream is Map
                                    ? Map<String, dynamic>.from(rawStream)
                                    : <String, dynamic>{};

                                Map<String, dynamic> myProf = {};
                                try {
                                  final prof = await _supabase
                                      .from('profiles')
                                      .select(
                                        'id, username, first_name, last_name, avatar_url, is_verified',
                                      )
                                      .eq('id', user.id)
                                      .maybeSingle();
                                  if (prof != null) {
                                    myProf = Map<String, dynamic>.from(prof);
                                  }
                                } catch (_) {}

                                if (ctx.mounted) Navigator.pop(ctx);
                                if (!mounted) return;
                                await LiveRoomScreen.open(
                                  context,
                                  stream: streamMap,
                                  hostProfile: myProf,
                                  isHost: true,
                                );
                                await _loadRooms(silent: true);
                              } catch (e) {
                                if (uploadedThumb != null) {
                                  unawaited(
                                    CloudflareStorageService.instance
                                        .deleteByUrl(uploadedThumb),
                                  );
                                }
                                if (ctx.mounted) {
                                  setModalState(() {
                                    isStarting = false;
                                    modalError = e
                                        .toString()
                                        .replaceFirst('Exception: ', '');
                                  });
                                }
                              }
                            },
                      icon: isStarting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.sensors_rounded),
                      label: Text(
                        isStarting ? 'Starting Live Room...' : 'Go Live Now',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZevColors.secondaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: isError ? ZevColors.errorRed : ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _supabase.auth.currentUser?.id;
    final filteredRooms = _selectedCategory == 'All'
        ? _rooms
        : _rooms
            .where(
              (r) =>
                  (r['category'] ?? 'General').toString().toLowerCase() ==
                  _selectedCategory.toLowerCase(),
            )
            .toList();

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ZEV Live Rooms',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _openStartRoomModal,
              icon: const Icon(Icons.sensors_rounded, size: 17),
              label: const Text(
                'Start Room',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
              style: TextButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: ZevColors.primaryBlue,
        onRefresh: () => _loadRooms(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            // Explicit Interactive Realtime Capability Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.deepNavy.withValues(alpha: 0.045),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.forum_rounded,
                      color: ZevColors.secondaryBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Interactive ZEV Live Chat & Presence Rooms',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Powered by Supabase Realtime for live community chat, floating reactions, and real-time participant lists.',
                          style: TextStyle(
                            fontSize: 12,
                            color: ZevColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Category Filter Pills
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final cat = _categories[idx];
                  final selected = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedCategory = cat);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? ZevColors.deepNavy : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? ZevColors.deepNavy
                              : ZevColors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : ZevColors.deepNavy,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading) ...[
              const ZevFeedCardSkeleton(),
              const SizedBox(height: 10),
              const ZevFeedCardSkeleton(),
            ] else if (_errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ZevColors.border),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: ZevColors.errorRed,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMsg!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => _loadRooms(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ] else if (filteredRooms.isEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 34,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: ZevColors.border),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ZevColors.primaryBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.podcasts_rounded,
                        color: ZevColors.secondaryBlue,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _selectedCategory == 'All'
                          ? 'No Active Live Rooms Right Now'
                          : 'No $_selectedCategory Live Rooms',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Start an interactive real-time discussion room and invite your followers to join.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: ZevColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _openStartRoomModal,
                      icon: const Icon(Icons.sensors_rounded),
                      label: const Text('Start a Live Room'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              for (final room in filteredRooms) ...[
                _buildRoomCard(room, me: me),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room, {String? me}) {
    final hostId = room['host_id']?.toString() ?? '';
    final host = _hostProfiles[hostId] ?? const <String, dynamic>{};
    final uname = (host['username'] ?? 'host').toString();
    final full = '${host['first_name'] ?? ''} ${host['last_name'] ?? ''}'.trim();
    final avatar = (host['avatar_url'] ?? '').toString();
    final verified = host['is_verified'] == true;

    final title = (room['title'] ?? 'Live Room').toString();
    final category = (room['category'] ?? 'General').toString();
    final thumbnail = (room['thumbnail_url'] ?? '').toString();
    final viewers = (room['viewer_count'] as num?)?.toInt() ?? 0;
    final startedAt = room['started_at']?.toString();
    final isHost = me != null && me == hostId;

    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        await LiveRoomScreen.open(
          context,
          stream: room,
          hostProfile: host,
          isHost: isHost,
        );
        await _loadRooms(silent: true);
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: ZevColors.deepNavy.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 138,
                  child: ZevCachedImage(imageUrl: thumbnail, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                GestureDetector(
                  onTap: () => ProfileScreen.open(context, userId: hostId),
                  child: ZevCachedImage.avatar(imageUrl: avatar, size: 42),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              full.isNotEmpty ? full : '@$uname',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: ZevColors.primaryBlue,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '@$uname • $category • ${TimeAgo.fromIsoString(startedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: ZevColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: ZevColors.errorRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: ZevColors.errorRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'LIVE • $viewers',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.errorRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  isHost ? 'Re-enter your live room' : 'Join live chat',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: ZevColors.secondaryBlue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
