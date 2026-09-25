import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../auth/screens/welcome_screen.dart';
import 'direct_chat_screen.dart';

class ChatThreadItem {
  final String peerId;
  final String peerName;
  final String peerAvatar;
  final String role;
  final String lastMessage;
  final String time;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final bool isRequest;

  ChatThreadItem({
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
    required this.role,
    required this.lastMessage,
    required this.time,
    this.lastMessageTime,
    required this.unreadCount,
    required this.isOnline,
    this.isRequest = false,
  });
}

class UserNoteItem {
  final String userId;
  final String userName;
  final String userAvatar;
  final String noteText;
  final bool isCurrentUser;

  UserNoteItem({
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.noteText,
    this.isCurrentUser = false,
  });
}

class DirectChatListScreen extends StatefulWidget {
  const DirectChatListScreen({super.key});

  @override
  State<DirectChatListScreen> createState() => _DirectChatListScreenState();
}

class _DirectChatListScreenState extends State<DirectChatListScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool isLoading = true;
  bool isSearchingLive = false;
  List<ChatThreadItem> threads = [];
  List<ChatThreadItem> searchResults = [];

  String _currentUserName = "zev_member";
  String _currentUserAvatar = "";
  String _myNote = "";
  String _selectedFilter = "Primary"; // "Primary", "General", "Requests"
  String _activeSecondaryFilter = "all"; // "all", "unread"

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFFF0F5);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserInfo();
    _fetchExistingChatThreads();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
      if (mounted && !isSearchingLive) {
        _fetchExistingChatThreads(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentUserInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final res = await supabase
          .from("profiles")
          .select("first_name, last_name, avatar_url")
          .eq("id", user.id)
          .maybeSingle();
      if (res != null && mounted) {
        final fName = res['first_name'] ?? '';
        final lName = res['last_name'] ?? '';
        final combined = "$fName $lName".trim();
        setState(() {
          if (combined.isNotEmpty) {
            _currentUserName = combined.toLowerCase().replaceAll(' ', '_');
          }
          _currentUserAvatar = res['avatar_url'] ?? '';
        });
      }
    } catch (_) {}
  }

  /// Fetch conversations that have existing message exchanges from database
  Future<void> _fetchExistingChatThreads({bool showLoading = true}) async {
    if (showLoading) setState(() => isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }
      final currentUserId = user.id;

      Set<String> friendIds = {};
      try {
        final friendsRes = await supabase
            .from("student_friends")
            .select("sender_id, receiver_id")
            .eq("status", "accepted")
            .or("sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId");
        for (var f in (friendsRes as List)) {
          final s = f['sender_id']?.toString() ?? '';
          final r = f['receiver_id']?.toString() ?? '';
          friendIds.add(s == currentUserId ? r : s);
        }
      } catch (_) {}

      final messagesRes = await supabase
          .from("direct_messages")
          .select(
            "id, sender_id, receiver_id, message_text, created_at, is_read",
          )
          .or("sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId")
          .order("created_at", ascending: false);

      Map<String, Map<String, dynamic>> activePeersMap = {};

      for (var m in (messagesRes as List)) {
        final senderId = m['sender_id']?.toString() ?? '';
        final receiverId = m['receiver_id']?.toString() ?? '';
        final peerId = (senderId == currentUserId) ? receiverId : senderId;

        if (peerId.isEmpty || peerId == currentUserId) continue;

        if (!activePeersMap.containsKey(peerId)) {
          activePeersMap[peerId] = {
            'lastMessage': m['message_text'] ?? '',
            'created_at': m['created_at'] ?? '',
            'unreadCount': 0,
            'iSentAny': senderId == currentUserId,
          };
        } else if (senderId == currentUserId) {
          activePeersMap[peerId]!['iSentAny'] = true;
        }

        if (senderId == peerId &&
            receiverId == currentUserId &&
            m['is_read'] == false) {
          activePeersMap[peerId]!['unreadCount'] =
              (activePeersMap[peerId]!['unreadCount'] as int) + 1;
        }
      }

      List<ChatThreadItem> loadedThreads = [];

      for (var entry in activePeersMap.entries) {
        final peerId = entry.key;
        final data = entry.value;

        String fullName = "ZEV User";
        String avatar = "";
        String role = "STUDENT";

        try {
          final profileRes = await supabase
              .from("profiles")
              .select("first_name, last_name, avatar_url, role")
              .eq("id", peerId)
              .maybeSingle();

          if (profileRes != null) {
            final fName = profileRes['first_name'] ?? '';
            final lName = profileRes['last_name'] ?? '';
            fullName = "$fName $lName".trim();
            if (fullName.isEmpty) fullName = "ZEV User";
            avatar = profileRes['avatar_url'] ?? '';
            role = (profileRes['role'] ?? 'STUDENT').toString().toUpperCase();
          }
        } catch (_) {}

        String timeStr = "";
        DateTime? msgDt;
        final dtStr = data['created_at']?.toString() ?? '';
        if (dtStr.isNotEmpty) {
          try {
            msgDt = DateTime.parse(dtStr);
            final now = DateTime.now();
            final diff = now.difference(msgDt);
            if (diff.inMinutes < 60) {
              timeStr = "${diff.inMinutes}m";
            } else if (diff.inHours < 24) {
              timeStr = "${diff.inHours}h";
            } else if (diff.inDays < 7) {
              timeStr = "${diff.inDays}d";
            } else {
              timeStr = "${msgDt.day}/${msgDt.month}";
            }
          } catch (_) {}
        }

        final bool isFriend = friendIds.contains(peerId);
        final bool iSentAny = data['iSentAny'] == true;
        final bool isRequest = !isFriend && !iSentAny;

        loadedThreads.add(
          ChatThreadItem(
            peerId: peerId,
            peerName: fullName,
            peerAvatar: avatar,
            role: role,
            lastMessage: data['lastMessage'],
            time: timeStr,
            lastMessageTime: msgDt,
            unreadCount: data['unreadCount'] as int,
            isOnline: true,
            isRequest: isRequest,
          ),
        );
      }

      loadedThreads.sort((a, b) {
        if (a.lastMessageTime == null) return 1;
        if (b.lastMessageTime == null) return -1;
        return b.lastMessageTime!.compareTo(a.lastMessageTime!);
      });

      if (mounted) {
        setState(() {
          threads = loadedThreads;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching existing chat threads: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _onSearchChanged(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        isSearchingLive = false;
        searchResults = [];
      });
      return;
    }

    setState(() => isSearchingLive = true);

    try {
      final user = supabase.auth.currentUser;
      final currentUserId = user?.id ?? '';

      final res = await supabase
          .from("profiles")
          .select("id, first_name, last_name, avatar_url, role")
          .or("first_name.ilike.%$q%,last_name.ilike.%$q%")
          .limit(20);

      List<ChatThreadItem> found = [];
      for (var p in (res as List)) {
        final pId = p['id'].toString();
        if (pId == currentUserId) continue;

        final fName = p['first_name'] ?? '';
        final lName = p['last_name'] ?? '';
        String fullName = "$fName $lName".trim();
        if (fullName.isEmpty) fullName = "ZEV User";

        found.add(
          ChatThreadItem(
            peerId: pId,
            peerName: fullName,
            peerAvatar: p['avatar_url'] ?? '',
            role: (p['role'] ?? 'STUDENT').toString().toUpperCase(),
            lastMessage: "start_conversation_placeholder",
            time: "",
            unreadCount: 0,
            isOnline: true,
          ),
        );
      }

      if (mounted) {
        setState(() => searchResults = found);
      }
    } catch (e) {
      debugPrint("Error searching users for chat: $e");
    }
  }

  void _showAddNoteDialog() {
    final controller = TextEditingController(text: _myNote);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 24,
            left: 20,
            right: 20,
          ),
          decoration: const BoxDecoration(
            color: surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Share a thought...",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 60,
                autofocus: true,
                style: const TextStyle(fontSize: 15, color: textDark),
                decoration: InputDecoration(
                  hintText: "What's on your mind? (Visible for 24h)",
                  hintStyle: const TextStyle(color: textGrey, fontSize: 13),
                  filled: true,
                  fillColor: cardBorder,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: textGrey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _myNote = controller.text.trim();
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("Share Note"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAccountSwitcherDrawer() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await MultiAccountService.instance.saveCurrentAccount(
      name: _currentUserName,
      avatarUrl: _currentUserAvatar,
    );

    final savedAccounts = await MultiAccountService.instance.getSavedAccounts();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: const BoxDecoration(
            color: surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Switch Accounts",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: textDark,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: textGrey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              for (var acc in savedAccounts) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: lightPinkBg,
                    backgroundImage: acc.avatarUrl.isNotEmpty
                        ? NetworkImage(acc.avatarUrl)
                        : null,
                    child: acc.avatarUrl.isEmpty
                        ? Text(
                            acc.name.isNotEmpty ? acc.name[0] : 'U',
                            style: const TextStyle(
                              color: primaryPink,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  title: Text(
                    acc.name,
                    style: TextStyle(
                      fontWeight: acc.id == user.id
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: textDark,
                    ),
                  ),
                  subtitle: Text(
                    acc.email,
                    style: const TextStyle(fontSize: 12, color: textGrey),
                  ),
                  trailing: acc.id == user.id
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: primaryPink,
                          size: 24,
                        )
                      : TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final switched = await MultiAccountService.instance
                                .switchAccount(acc);
                            if (switched && mounted) {
                              _fetchCurrentUserInfo();
                              _fetchExistingChatThreads();
                            }
                          },
                          child: const Text(
                            "Switch",
                            style: TextStyle(
                              color: primaryPink,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
                const Divider(color: cardBorder, height: 1),
              ],

              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: lightPinkBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: primaryPink.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: primaryPink,
                    size: 24,
                  ),
                ),
                title: const Text(
                  "Add ZEV Account",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: primaryPink,
                  ),
                ),
                subtitle: const Text(
                  "Sign into another account",
                  style: TextStyle(fontSize: 12, color: textGrey),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddAccountDialog();
                },
              ),

              const Divider(color: cardBorder, height: 20),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                ),
                title: const Text(
                  "Log Out of Active Account",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _logoutCurrent();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _logoutCurrent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Log Out?"),
        content: const Text(
          "Are you sure you want to sign out of this account?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("Log Out"),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await supabase.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _showAddAccountDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool isLoggingIn = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: surfaceWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  "Add Existing Account",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Sign in to switch between multiple accounts seamlessly.",
                  style: TextStyle(fontSize: 12, color: textGrey),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 14, color: textDark),
                  decoration: InputDecoration(
                    labelText: "Email address",
                    filled: true,
                    fillColor: cardBorder,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 14, color: textDark),
                  decoration: InputDecoration(
                    labelText: "Password",
                    filled: true,
                    fillColor: cardBorder,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoggingIn
                        ? null
                        : () async {
                            final em = emailCtrl.text.trim();
                            final pw = passCtrl.text.trim();
                            if (em.isEmpty || pw.isEmpty) return;

                            setModalState(() => isLoggingIn = true);
                            try {
                              final authRes = await supabase.auth
                                  .signInWithPassword(email: em, password: pw);
                              final newUser = authRes.user;
                              if (newUser != null) {
                                String newName = em.split('@').first;
                                String newAvatar = '';
                                try {
                                  final pRes = await supabase
                                      .from('profiles')
                                      .select(
                                        'first_name, last_name, avatar_url',
                                      )
                                      .eq('id', newUser.id)
                                      .maybeSingle();
                                  if (pRes != null) {
                                    final fn = pRes['first_name'] ?? '';
                                    final ln = pRes['last_name'] ?? '';
                                    final f = "$fn $ln".trim();
                                    if (f.isNotEmpty) newName = f;
                                    newAvatar = pRes['avatar_url'] ?? '';
                                  }
                                } catch (_) {}

                                await MultiAccountService.instance
                                    .saveCurrentAccount(
                                      name: newName,
                                      avatarUrl: newAvatar,
                                    );

                                if (mounted) {
                                  Navigator.pop(ctx);
                                  _fetchCurrentUserInfo();
                                  _fetchExistingChatThreads();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Switched to $newName!"),
                                      backgroundColor: const Color(0xFF10B981),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              setModalState(() => isLoggingIn = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Login error: $e")),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: isLoggingIn
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Sign In & Add Account",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showNewChatSearchModal() {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> searchList = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: const BoxDecoration(
              color: surfaceWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "New Message ✍️",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textDark,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: textGrey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: cardBorder,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      cursorColor: primaryPink,
                      style: const TextStyle(fontSize: 14, color: textDark),
                      decoration: const InputDecoration(
                        hintText: "Search user by name...",
                        hintStyle: TextStyle(fontSize: 13, color: textGrey),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: textGrey,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (q) async {
                        final trimmed = q.trim();
                        if (trimmed.isEmpty) {
                          setModalState(() {
                            searchList = [];
                            isSearching = false;
                          });
                          return;
                        }
                        setModalState(() => isSearching = true);
                        try {
                          final currentUserId =
                              supabase.auth.currentUser?.id ?? '';
                          final res = await supabase
                              .from('profiles')
                              .select(
                                'id, first_name, last_name, avatar_url, role',
                              )
                              .or(
                                'first_name.ilike.%$trimmed%,last_name.ilike.%$trimmed%',
                              )
                              .neq('id', currentUserId)
                              .limit(20);
                          setModalState(() {
                            searchList = List<Map<String, dynamic>>.from(res);
                            isSearching = false;
                          });
                        } catch (_) {
                          setModalState(() => isSearching = false);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: cardBorder, height: 1),

                Expanded(
                  child: isSearching
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: primaryPink,
                            strokeWidth: 2,
                          ),
                        )
                      : searchList.isEmpty
                      ? Center(
                          child: Text(
                            searchCtrl.text.isEmpty
                                ? "Type a name to find people"
                                : "No users found",
                            style: const TextStyle(
                              color: textGrey,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          itemCount: searchList.length,
                          separatorBuilder: (_, _) =>
                              const Divider(color: cardBorder, height: 1),
                          itemBuilder: (context, index) {
                            final p = searchList[index];
                            final fn = p['first_name'] ?? '';
                            final ln = p['last_name'] ?? '';
                            String name = "$fn $ln".trim();
                            if (name.isEmpty) name = "ZEV User";
                            final av = p['avatar_url'] ?? '';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor: lightPinkBg,
                                backgroundImage: av.isNotEmpty
                                    ? NetworkImage(av)
                                    : null,
                                child: av.isEmpty
                                    ? Text(
                                        name[0],
                                        style: const TextStyle(
                                          color: primaryPink,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                p['role']?.toString().toUpperCase() ?? 'MEMBER',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: primaryPink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: primaryPink,
                                size: 20,
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DirectChatScreen(
                                      peerId: p['id'].toString(),
                                      peerName: name,
                                      peerAvatar: av,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          color: surfaceWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Filter Conversations",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textDark,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.mark_chat_unread_outlined,
                color: primaryPink,
              ),
              title: const Text(
                "Unread Messages Only",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: _activeSecondaryFilter == "unread"
                  ? const Icon(Icons.check_rounded, color: primaryPink)
                  : null,
              onTap: () {
                setState(
                  () => _activeSecondaryFilter =
                      _activeSecondaryFilter == "unread" ? "all" : "unread",
                );
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.all_inbox_rounded, color: textDark),
              title: const Text(
                "Show All",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: _activeSecondaryFilter == "all"
                  ? const Icon(Icons.check_rounded, color: primaryPink)
                  : null,
              onTap: () {
                setState(() => _activeSecondaryFilter = "all");
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptRequest(ChatThreadItem item) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase.from('student_friends').upsert({
        'sender_id': item.peerId,
        'receiver_id': user.id,
        'status': 'accepted',
        'created_at': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Chat request accepted from ${item.peerName}"),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      _fetchExistingChatThreads();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _declineRequest(ChatThreadItem item) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase
          .from('direct_messages')
          .delete()
          .eq('sender_id', item.peerId)
          .eq('receiver_id', user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Request declined from ${item.peerName}")),
      );
      _fetchExistingChatThreads();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    List<ChatThreadItem> baseList = _searchController.text.trim().isNotEmpty
        ? searchResults
        : threads;

    List<ChatThreadItem> displayList;
    if (_searchController.text.trim().isNotEmpty) {
      displayList = baseList;
    } else if (_selectedFilter == "Requests") {
      displayList = baseList.where((t) => t.isRequest).toList();
    } else if (_selectedFilter == "General") {
      displayList = baseList
          .where((t) => !t.isRequest && t.unreadCount == 0)
          .toList();
    } else {
      // Primary
      displayList = baseList.where((t) => !t.isRequest).toList();
    }

    if (_activeSecondaryFilter == "unread") {
      displayList = displayList.where((t) => t.unreadCount > 0).toList();
    }

    return Scaffold(
      backgroundColor: surfaceWhite,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _showAccountSwitcherDrawer,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _currentUserName,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: textDark,
                size: 20,
              ),
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: primaryPink,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.edit_note_rounded,
              color: textDark,
              size: 26,
            ),
            onPressed: _showNewChatSearchModal,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ResponsiveLayout.feedConstraint(
        maxWidth: 640,
        child: Column(
          children: [
            // Search Bar (Instagram style rounded capsule)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: cardBorder,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  cursorColor: primaryPink,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textDark,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: "${context.l10n.search}...",
                    hintStyle: const TextStyle(color: textGrey, fontSize: 13),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: textGrey,
                      size: 20,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: textGrey,
                              size: 16,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged("");
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),

            // Instagram Notes Tray (Screenshot 4)
            if (!isSearchingLive) _buildNotesTray(),

            // Filter Pills Row (Screenshot 4)
            if (!isSearchingLive) _buildFilterPills(),

            // Chat Conversations List
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: primaryPink,
                        strokeWidth: 2.5,
                      ),
                    )
                  : displayList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: const BoxDecoration(
                              color: lightPinkBg,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: primaryPink,
                              size: 44,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _searchController.text.trim().isNotEmpty
                                ? "${context.l10n.search}: '${_searchController.text}'"
                                : context.l10n.noConversationsYet,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.l10n.startLiveChatHint,
                            style: const TextStyle(
                              color: textGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: primaryPink,
                      onRefresh: _fetchExistingChatThreads,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        itemCount: displayList.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: cardBorder, height: 14),
                        itemBuilder: (context, index) {
                          final item = displayList[index];
                          return _buildThreadItem(item);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Horizontal Instagram Notes Tray (matching Screenshot 4)
  Widget _buildNotesTray() {
    return Container(
      height: 124,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Current User's Note
          GestureDetector(
            onTap: _showAddNoteDialog,
            child: SizedBox(
              width: 86,
              child: Column(
                children: [
                  // Thought bubble (Fixed height for uniform avatar alignment)
                  Container(
                    height: 38,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _myNote.isNotEmpty ? lightPinkBg : cardBorder,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _myNote.isNotEmpty
                            ? primaryPink
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _myNote.isNotEmpty
                          ? _myNote
                          : "Start your\nfirst note...",
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _myNote.isNotEmpty ? primaryPink : textGrey,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: lightPinkBg,
                        backgroundImage: _currentUserAvatar.isNotEmpty
                            ? NetworkImage(_currentUserAvatar)
                            : null,
                        child: _currentUserAvatar.isEmpty
                            ? const Icon(
                                Icons.person,
                                color: primaryPink,
                                size: 24,
                              )
                            : null,
                      ),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: primaryPink,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Your note",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: textGrey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Sample active peer notes from friends list
          for (var t in threads.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: 86,
                child: Column(
                  children: [
                    Container(
                      height: 38,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cardBorder,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        t.lastMessage.isNotEmpty && t.lastMessage.length < 25
                            ? t.lastMessage
                            : "👋 Hello ZEV!",
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: lightPinkBg,
                      backgroundImage: t.peerAvatar.isNotEmpty
                          ? NetworkImage(t.peerAvatar)
                          : null,
                      child: t.peerAvatar.isEmpty
                          ? Text(
                              t.peerName[0],
                              style: const TextStyle(
                                color: primaryPink,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.peerName.split(' ').first,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Filter Pills Row matching Screenshot 4
  Widget _buildFilterPills() {
    final filters = ["Primary", "Requests", "General"];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          // Filter Icon pill
          GestureDetector(
            onTap: _showFiltersBottomSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _activeSecondaryFilter != 'all'
                    ? primaryPink.withOpacity(0.12)
                    : cardBorder,
                borderRadius: BorderRadius.circular(16),
                border: _activeSecondaryFilter != 'all'
                    ? Border.all(color: primaryPink)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 14,
                    color: _activeSecondaryFilter != 'all'
                        ? primaryPink
                        : textDark,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _activeSecondaryFilter == 'unread' ? "Unread" : "Filters",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _activeSecondaryFilter != 'all'
                          ? primaryPink
                          : textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Category pills
          for (var f in filters)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _selectedFilter = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _selectedFilter == f ? primaryPink : cardBorder,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _selectedFilter == f ? Colors.white : textDark,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThreadItem(ChatThreadItem item) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DirectChatScreen(
              peerId: item.peerId,
              peerName: item.peerName,
              peerAvatar: item.peerAvatar,
            ),
          ),
        );
        _fetchExistingChatThreads();
      },
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: lightPinkBg,
            backgroundImage: item.peerAvatar.isNotEmpty
                ? NetworkImage(item.peerAvatar)
                : null,
            child: item.peerAvatar.isEmpty
                ? Text(
                    item.peerName.isNotEmpty ? item.peerName[0] : 'U',
                    style: const TextStyle(
                      color: primaryPink,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
          if (item.isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        item.peerName,
        style: const TextStyle(
          color: textDark,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              (item.lastMessage == 'start_conversation_placeholder' ||
                      item.lastMessage == 'Start a conversation 💬')
                  ? context.l10n.startConversation
                  : item.lastMessage,
              style: TextStyle(
                color: item.unreadCount > 0 ? textDark : textGrey,
                fontSize: 13,
                fontWeight: item.unreadCount > 0
                    ? FontWeight.w700
                    : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.time.isNotEmpty) ...[
            const Text(" · ", style: TextStyle(color: textGrey, fontSize: 13)),
            Text(
              item.time,
              style: const TextStyle(color: textGrey, fontSize: 12),
            ),
          ],
        ],
      ),
      trailing: item.isRequest
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () => _acceptRequest(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Accept",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: () => _declineRequest(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textGrey,
                    side: const BorderSide(color: cardBorder),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Decline",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: primaryPink,
                      shape: BoxShape.circle,
                    ),
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.camera_alt_outlined,
                    color: textGrey,
                    size: 22,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DirectChatScreen(
                          peerId: item.peerId,
                          peerName: item.peerName,
                          peerAvatar: item.peerAvatar,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
