import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/cloudflare_storage_service.dart';

class SavedMessagesScreen extends StatefulWidget {
  const SavedMessagesScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedMessagesScreen()),
    );
  }

  @override
  State<SavedMessagesScreen> createState() => _SavedMessagesScreenState();
}

class _SavedMessagesScreenState extends State<SavedMessagesScreen> {
  final _client = Supabase.instance.client;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  String _selectedCategory = 'all'; // 'all', 'notes', 'media', 'documents', 'links'
  String? _selectedFolderId;
  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _storageStats;
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadCloudData();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCloudData() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      setState(() => _isLoading = true);

      // 1. Fetch user folders
      final foldersRes = await _client
          .from('user_cloud_folders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      _folders = List<Map<String, dynamic>>.from(foldersRes);

      // 2. Fetch storage statistics
      try {
        final statsRes = await _client.rpc('get_user_cloud_stats');
        if (statsRes is Map) {
          _storageStats = Map<String, dynamic>.from(statsRes);
        }
      } catch (_) {}

      // 3. Fetch items based on category and folder
      var query = _client
          .from('user_cloud_items')
          .select()
          .eq('user_id', userId);

      if (_selectedCategory != 'all') {
        query = query.eq('category', _selectedCategory);
      }
      if (_selectedFolderId != null) {
        query = query.eq('folder_id', _selectedFolderId!);
      }

      final itemsRes = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      setState(() {
        _items = List<Map<String, dynamic>>.from(itemsRes);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[SavedMessagesScreen] load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendTextNote() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _textController.clear();

    // Auto-detect links
    final isLink = text.startsWith('http://') || text.startsWith('https://');
    final category = isLink ? 'links' : 'notes';

    try {
      final insertRes = await _client.from('user_cloud_items').insert({
        'user_id': userId,
        'category': category,
        'folder_id': _selectedFolderId,
        'title': isLink ? text : (text.length > 40 ? '${text.substring(0, 40)}...' : text),
        'content': text,
        'file_url': isLink ? text : null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).select().single();

      setState(() {
        _items.insert(0, Map<String, dynamic>.from(insertRes));
      });

      _loadCloudData();
    } catch (e) {
      debugPrint('[SavedMessagesScreen] insert note error: $e');
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      setState(() => _isUploading = true);

      final ext = file.extension?.toLowerCase() ?? '';
      final isImage = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext);
      final isVideo = ['mp4', 'mov', 'avi', 'mkv'].contains(ext);
      final isAudio = ['mp3', 'm4a', 'wav', 'aac'].contains(ext);

      String category = 'documents';
      if (isImage || isVideo) category = 'media';
      if (isAudio) category = 'audio';

      final userId = _client.auth.currentUser!.id;
      final path = 'cloud/$userId/${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      final publicUrl = await CloudflareStorageService.instance.upload(
        bucket: 'media',
        path: path,
        bytes: bytes,
        contentType: isImage ? 'image/$ext' : 'application/octet-stream',
      );

      if (publicUrl.isNotEmpty) {
        final insertRes = await _client.from('user_cloud_items').insert({
          'user_id': userId,
          'category': category,
          'folder_id': _selectedFolderId,
          'title': file.name,
          'file_name': file.name,
          'file_url': publicUrl,
          'file_size': file.size,
          'file_mime_type': ext,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }).select().single();

        setState(() {
          _items.insert(0, Map<String, dynamic>.from(insertRes));
        });
        _loadCloudData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showCreateFolderDialog() {
    final folderController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "New Cloud Folder",
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: folderController,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: "Folder Name (e.g. Work, Media, Documents)",
            hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = folderController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              final userId = _client.auth.currentUser?.id;
              if (userId == null) return;

              try {
                await _client.from('user_cloud_folders').insert({
                  'user_id': userId,
                  'name': name,
                });
                _loadCloudData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error creating folder: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text("Create", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePin(Map<String, dynamic> item) async {
    final id = item['id'];
    final isPinned = !(item['is_pinned'] == true);

    await _client.from('user_cloud_items').update({'is_pinned': isPinned}).eq('id', id);
    _loadCloudData();
  }

  Future<void> _deleteItem(String id) async {
    await _client.from('user_cloud_items').delete().eq('id', id);
    setState(() {
      _items.removeWhere((it) => it['id'] == id);
    });
    _loadCloudData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          children: [
            Text(
              "Saved Messages",
              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 17),
            ),
            Text(
              "Personal Cloud Storage",
              style: TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: Color(0xFF0284C7)),
            tooltip: "Create Folder",
            onPressed: _showCreateFolderDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Storage Stats Banner
          _buildStorageBanner(),

          // Categories & Folders Horizontal Bar
          _buildFilterBar(),

          // Main Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
                : _items.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _items.length,
                        itemBuilder: (ctx, idx) => _buildItemCard(_items[idx]),
                      ),
          ),

          if (_isUploading)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: const Color(0xFFE0F2FE),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0284C7))),
                  SizedBox(width: 10),
                  Text("Uploading to ZEV Cloud...", style: TextStyle(color: Color(0xFF0284C7), fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),

          // Bottom Input Bar
          _buildBottomInputBar(),
        ],
      ),
    );
  }

  Widget _buildStorageBanner() {
    final totalItems = _storageStats?['total_items'] ?? _items.length;
    final totalBytes = _storageStats?['total_bytes'] ?? 0;
    final mb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_done_rounded, color: Color(0xFF0284C7), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Unlimited ZEV Cloud Drive",
                  style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 13),
                ),
                Text(
                  "$totalItems saved items • $mb MB synced across devices",
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final categories = [
      {'id': 'all', 'label': 'All', 'icon': Icons.apps_rounded},
      {'id': 'notes', 'label': 'Notes', 'icon': Icons.notes_rounded},
      {'id': 'media', 'label': 'Media', 'icon': Icons.photo_library_rounded},
      {'id': 'documents', 'label': 'Files', 'icon': Icons.insert_drive_file_rounded},
      {'id': 'links', 'label': 'Links', 'icon': Icons.link_rounded},
    ];

    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...categories.map((cat) {
            final isSelected = _selectedCategory == cat['id'] && _selectedFolderId == null;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat['icon'] as IconData, size: 14, color: isSelected ? Colors.white : const Color(0xFF64748B)),
                    const SizedBox(width: 5),
                    Text(cat['label'] as String),
                  ],
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF0284C7),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0)),
                onSelected: (_) {
                  setState(() {
                    _selectedCategory = cat['id'] as String;
                    _selectedFolderId = null;
                  });
                  _loadCloudData();
                },
              ),
            );
          }),
          // Folder Chips
          ..._folders.map((folder) {
            final isSelected = _selectedFolderId == folder['id'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_rounded, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 5),
                    Text(folder['name'] ?? ''),
                  ],
                ),
                selected: isSelected,
                selectedColor: const Color(0xFFF59E0B),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
                onSelected: (_) {
                  setState(() {
                    _selectedFolderId = isSelected ? null : folder['id'];
                  });
                  _loadCloudData();
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final isPinned = item['is_pinned'] == true;
    final cat = item['category'] ?? 'notes';
    final content = item['content'] ?? '';
    final fileUrl = item['file_url'];
    final fileName = item['file_name'];
    final title = item['title'];
    final createdStr = item['created_at'] != null ? DateTime.parse(item['created_at']).toLocal().toString().substring(0, 16) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPinned ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
          width: isPinned ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (Category + Pin + Menu)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
            child: Row(
              children: [
                if (isPinned) ...[
                  const Icon(Icons.push_pin_rounded, color: Color(0xFF0284C7), size: 14),
                  const SizedBox(width: 4),
                  const Text("PINNED", style: TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.w900)),
                  const Spacer(),
                ] else
                  const Spacer(),
                Text(createdStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B), size: 18),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (val) {
                    if (val == 'pin') _togglePin(item);
                    if (val == 'delete') _deleteItem(item['id']);
                    if (val == 'copy') {
                      Clipboard.setData(ClipboardData(text: content.isNotEmpty ? content : (fileUrl ?? '')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Copied to clipboard")),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Row(
                        children: [
                          Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, size: 16, color: const Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Text(isPinned ? "Unpin" : "Pin to top", style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: const [
                          Icon(Icons.copy_rounded, size: 16, color: Color(0xFF64748B)),
                          SizedBox(width: 8),
                          Text("Copy", style: TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: const [
                          Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                          SizedBox(width: 8),
                          Text("Delete", style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Body Content
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: SelectableText(
                content,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, height: 1.4, fontWeight: FontWeight.w500),
              ),
            ),

          // File / Media Attachment Preview
          if (fileUrl != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: InkWell(
                onTap: () {
                  final uri = Uri.tryParse(fileUrl);
                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          cat == 'media' ? Icons.image_rounded : Icons.attach_file_rounded,
                          color: const Color(0xFF0284C7),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName ?? title ?? "Download File",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Text("Tap to view or download", style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.download_rounded, color: Color(0xFF0284C7), size: 20),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_queue_rounded, color: Color(0xFF0284C7), size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            "Your Personal Cloud Drive",
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Save notes, documents, voice memos, links and media here. Everything is stored on Cloudflare and accessible across all your devices.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF0284C7)),
              tooltip: "Attach File / Photo",
              onPressed: _pickAndUploadFile,
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Write a note or paste a link...",
                    hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _sendTextNote(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0284C7),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                onPressed: _sendTextNote,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
