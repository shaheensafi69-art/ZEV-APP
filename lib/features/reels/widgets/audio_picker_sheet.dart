import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/zev_theme.dart';

/// Data model for selectable audio tracks in Reels & Posts.
class AudioTrackItem {
  final String id;
  final String title;
  final String artist;
  final String duration;
  final String coverUrl;
  final String audioUrl;
  final String category;
  final bool isTrending;

  const AudioTrackItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.coverUrl,
    required this.audioUrl,
    required this.category,
    this.isTrending = false,
  });
}

/// Clearmorphic Bottom Sheet for picking Trending Sounds & Music for Reels & Posts.
class AudioPickerSheet extends StatefulWidget {
  final String? initialSelectedId;

  const AudioPickerSheet({super.key, this.initialSelectedId});

  static Future<AudioTrackItem?> show(
    BuildContext context, {
    String? initialSelectedId,
  }) {
    return showModalBottomSheet<AudioTrackItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioPickerSheet(initialSelectedId: initialSelectedId),
    );
  }

  @override
  State<AudioPickerSheet> createState() => _AudioPickerSheetState();
}

class _AudioPickerSheetState extends State<AudioPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  final AudioPlayer _player = AudioPlayer();

  String? _playingTrackId;
  PlayerState _playerState = PlayerState.stopped;
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Trending',
    'Lo-Fi Beats',
    'Electronic',
    'Chill',
    'Cinematic',
  ];

  final List<AudioTrackItem> _tracks = const [
    AudioTrackItem(
      id: 'sound_1',
      title: 'Midnight City Lights',
      artist: 'ZEV Originals • Lo-Fi',
      duration: '2:45',
      coverUrl:
          'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=200',
      audioUrl:
          'https://cdn.freesound.org/previews/612/612610_5674468-lq.mp3',
      category: 'Lo-Fi Beats',
      isTrending: true,
    ),
    AudioTrackItem(
      id: 'sound_2',
      title: 'Sunset Tropical Waves',
      artist: 'Aero Soundlab',
      duration: '3:10',
      coverUrl:
          'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=200',
      audioUrl:
          'https://cdn.freesound.org/previews/612/612611_5674468-lq.mp3',
      category: 'Electronic',
      isTrending: true,
    ),
    AudioTrackItem(
      id: 'sound_3',
      title: 'Deep Focus Pulse',
      artist: 'Neural Beats',
      duration: '2:15',
      coverUrl:
          'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200',
      audioUrl:
          'https://cdn.freesound.org/previews/612/612612_5674468-lq.mp3',
      category: 'Chill',
      isTrending: false,
    ),
    AudioTrackItem(
      id: 'sound_4',
      title: 'Epic Cinematic Horizon',
      artist: 'Symphony Collective',
      duration: '3:40',
      coverUrl:
          'https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=200',
      audioUrl:
          'https://cdn.freesound.org/previews/612/612613_5674468-lq.mp3',
      category: 'Cinematic',
      isTrending: true,
    ),
    AudioTrackItem(
      id: 'sound_5',
      title: 'Cyberpunk Neon Drift',
      artist: 'Tokyo Synth Syndicate',
      duration: '2:50',
      coverUrl:
          'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=200',
      audioUrl:
          'https://cdn.freesound.org/previews/612/612614_5674468-lq.mp3',
      category: 'Electronic',
      isTrending: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPreview(AudioTrackItem track) async {
    HapticFeedback.selectionClick();
    if (_playingTrackId == track.id && _playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      _playingTrackId = track.id;
      try {
        await _player.play(UrlSource(track.audioUrl));
      } catch (e) {
        debugPrint('[AudioPickerSheet] preview notice: $e');
      }
    }
  }

  void _selectTrack(AudioTrackItem track) {
    HapticFeedback.mediumImpact();
    _player.stop();
    Navigator.of(context).pop(track);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _tracks.where((t) {
      final matchesCat = _selectedCategory == 'All' ||
          (_selectedCategory == 'Trending' && t.isTrending) ||
          t.category == _selectedCategory;
      final matchesQuery = query.isEmpty ||
          t.title.toLowerCase().contains(query) ||
          t.artist.toLowerCase().contains(query);
      return matchesCat && matchesQuery;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
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

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.music_note_rounded,
                  color: ZevColors.primaryBlue,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Add Music & Sounds',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  onPressed: () {
                    _player.stop();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                  hintText: 'Search songs, artists, or audio vibes...',
                  hintStyle: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13.5,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),

          // Category Chips
          SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (ctx, i) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                final isSel = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = cat);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isSel
                          ? const Color(0xFF0284C7)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel
                            ? const Color(0xFF0284C7)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: isSel ? Colors.white : const Color(0xFF475569),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 16, color: Color(0xFFF1F5F9)),

          // Track List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: filtered.length,
              separatorBuilder: (ctx, i) =>
                  const Divider(height: 12, color: Color(0xFFF1F5F9)),
              itemBuilder: (ctx, idx) {
                final track = filtered[idx];
                final isPlaying = _playingTrackId == track.id &&
                    _playerState == PlayerState.playing;

                return Row(
                  children: [
                    // Cover Thumbnail with Play/Pause
                    GestureDetector(
                      onTap: () => _togglePlayPreview(track),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CachedNetworkImage(
                              imageUrl: track.coverUrl,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                            Container(
                              width: 52,
                              height: 52,
                              color: Colors.black.withValues(alpha: 0.35),
                              child: Icon(
                                isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_filled_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (track.isTrending) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAB308)
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Trending',
                                    style: TextStyle(
                                      color: Color(0xFFCA8A04),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${track.artist} • ${track.duration}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Use Button
                    GestureDetector(
                      onTap: () => _selectTrack(track),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0284C7), Color(0xFF06B6D4)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0284C7)
                                  .withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Use Sound',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
