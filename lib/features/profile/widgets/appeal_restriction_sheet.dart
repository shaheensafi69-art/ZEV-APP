import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';

/// Light Clearmorphic Account Standing & Restriction Appeal Modal Sheet.
/// Lets users inspect active restrictions/suspensions, review past appeals,
/// attach up to 3 evidence screenshots, and submit an appeal via `submit_restriction_appeal`.
class AppealRestrictionSheet extends StatefulWidget {
  final String? initialReason;

  const AppealRestrictionSheet({
    super.key,
    this.initialReason,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialReason,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppealRestrictionSheet(initialReason: initialReason),
    );
  }

  @override
  State<AppealRestrictionSheet> createState() => _AppealRestrictionSheetState();
}

class _AppealRestrictionSheetState extends State<AppealRestrictionSheet> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  final _reasonCtrl = TextEditingController();
  final _explanationCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMsg;
  Map<String, dynamic> _profileStanding = {};
  List<Map<String, dynamic>> _restrictions = [];
  List<Map<String, dynamic>> _appeals = [];
  String? _selectedRestrictionId;
  final List<File> _evidenceFiles = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialReason != null && widget.initialReason!.trim().isNotEmpty) {
      _reasonCtrl.text = widget.initialReason!.trim();
    }
    _loadData();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _explanationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Please sign in to view or submit an appeal.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('profiles')
            .select(
              'is_banned, banned_until, ban_reason, is_restricted, restricted_until, restriction_reason, warning_count',
            )
            .eq('id', uid)
            .maybeSingle(),
        _supabase
            .from('user_restrictions')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false),
        _supabase
            .from('appeals')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false),
      ]);

      final prof = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : <String, dynamic>{};
      final restr = (results[1] is List)
          ? (results[1] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final appeals = (results[2] is List)
          ? (results[2] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      String? defaultRestrId = _selectedRestrictionId;
      if (defaultRestrId == null) {
        final active = restr.where((r) => r['status'] == 'active').toList();
        if (active.isNotEmpty) {
          defaultRestrId = active.first['id']?.toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _profileStanding = prof;
        _restrictions = restr;
        _appeals = appeals;
        _selectedRestrictionId = defaultRestrId;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load appeals sheet error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMsg = 'Could not load standing details: $e';
      });
    }
  }

  Future<void> _pickEvidence() async {
    final remaining = 3 - _evidenceFiles.length;
    if (remaining <= 0) {
      _showToast('Maximum 3 screenshots allowed per appeal.', isError: true);
      return;
    }

    try {
      if (remaining == 1) {
        final picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        if (picked != null && mounted) {
          setState(() => _evidenceFiles.add(File(picked.path)));
        }
      } else {
        final picked = await _picker.pickMultiImage(
          imageQuality: 85,
          limit: remaining,
        );
        if (picked.isNotEmpty && mounted) {
          setState(() {
            for (final x in picked) {
              if (_evidenceFiles.length < 3) {
                _evidenceFiles.add(File(x.path));
              }
            }
          });
        }
      }
    } catch (e) {
      _showToast('Could not pick screenshot: $e', isError: true);
    }
  }

  bool _hasOpenAppealForSelection() {
    return _appeals.any((a) {
      final st = (a['status'] ?? '').toString();
      if (st != 'pending' && st != 'under_review') return false;
      final rid = a['restriction_id']?.toString();
      return _selectedRestrictionId == null
          ? (rid == null || rid.isEmpty)
          : rid == _selectedRestrictionId;
    });
  }

  Future<void> _submitAppeal() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    final reason = _reasonCtrl.text.trim();
    final explanation = _explanationCtrl.text.trim();

    if (reason.length < 3 || reason.length > 200) {
      _showToast('Reason must be between 3 and 200 characters.', isError: true);
      return;
    }
    if (explanation.length < 10 || explanation.length > 4000) {
      _showToast(
        'Please write at least 10 characters explaining your appeal.',
        isError: true,
      );
      return;
    }
    if (_hasOpenAppealForSelection()) {
      _showToast(
        'You already have an open appeal under review for this notice.',
        isError: true,
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);

    final uploadedUrls = <String>[];
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < _evidenceFiles.length; i++) {
        final file = _evidenceFiles[i];
        final ext = file.path.contains('.')
            ? file.path.split('.').last.toLowerCase()
            : 'jpg';
        final url = await CloudflareStorageService.instance.upload(
          bucket: 'temp',
          path: 'appeal_${uid}_${ts}_$i.$ext',
          file: file,
        );
        uploadedUrls.add(url);
      }

      await _supabase.rpc(
        'submit_restriction_appeal',
        params: {
          'p_reason': reason,
          'p_explanation': explanation,
          'p_restriction_id': _selectedRestrictionId,
          'p_evidence_urls': uploadedUrls,
        },
      );

      if (!mounted) return;
      _reasonCtrl.clear();
      _explanationCtrl.clear();
      setState(() {
        _evidenceFiles.clear();
        _isSubmitting = false;
      });
      _showToast('Appeal submitted! Our moderation team will review it soon.');
      await _loadData();
    } catch (e) {
      if (uploadedUrls.isNotEmpty) {
        CloudflareStorageService.instance.deleteUrls(uploadedUrls);
      }
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showToast(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: isError ? ZevColors.errorRed : ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasOpenForSelection = _hasOpenAppealForSelection();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottomInset),
      decoration: BoxDecoration(
        color: ZevColors.softSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.14),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: ZevColors.brandGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.gavel_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Standing & Appeals',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      Text(
                        'Review notices and submit an appeal to ZEV Moderation',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ZevColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: ZevColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: CircularProgressIndicator(color: ZevColors.primaryBlue),
                ),
              )
            else if (_errorMsg != null)
              _buildCard(
                child: Column(
                  children: [
                    Text(
                      _errorMsg!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ZevColors.errorRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStandingSummary(),
                      const SizedBox(height: 14),
                      if (_appeals.isNotEmpty) ...[
                        _buildSectionLabel('YOUR APPEAL HISTORY'),
                        ..._appeals.map(_buildAppealHistoryCard),
                        const SizedBox(height: 14),
                      ],
                      _buildSectionLabel('SUBMIT NEW APPEAL'),
                      _buildCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_restrictions.isNotEmpty) ...[
                              const Text(
                                'Notice to Appeal',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildRestrictionChip(
                                    id: null,
                                    label: 'General Account Standing',
                                  ),
                                  ..._restrictions.map((r) {
                                    final rid = r['id']?.toString();
                                    final type =
                                        (r['type'] ?? 'Notice').toString();
                                    final reason =
                                        (r['reason'] ?? '').toString();
                                    final label = reason.isNotEmpty
                                        ? '$type: $reason'
                                        : type;
                                    return _buildRestrictionChip(
                                      id: rid,
                                      label: label,
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (hasOpenForSelection)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFFDE68A),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.hourglass_top_rounded,
                                      size: 18,
                                      color: Color(0xFFB45309),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'An appeal for this notice is already pending or under review.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF92400E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              TextField(
                                controller: _reasonCtrl,
                                maxLength: 200,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: ZevColors.deepNavy,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Appeal Reason',
                                  hintText:
                                      'e.g. Account action made in error',
                                  filled: true,
                                  fillColor: ZevColors.softSurface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: ZevColors.border,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: ZevColors.border,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _explanationCtrl,
                                maxLines: 4,
                                maxLength: 4000,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: ZevColors.deepNavy,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Detailed Explanation',
                                  hintText:
                                      'Explain clearly why this warning, restriction, or suspension should be lifted...',
                                  filled: true,
                                  fillColor: ZevColors.softSurface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: ZevColors.border,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: ZevColors.border,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Screenshots (optional, up to 3)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: ZevColors.textSecondary,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _evidenceFiles.length >= 3 ||
                                            _isSubmitting
                                        ? null
                                        : _pickEvidence,
                                    icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Attach'),
                                  ),
                                ],
                              ),
                              if (_evidenceFiles.isNotEmpty) ...[
                                SizedBox(
                                  height: 76,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _evidenceFiles.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (_, idx) => Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.file(
                                            _evidenceFiles[idx],
                                            width: 76,
                                            height: 76,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 3,
                                          right: 3,
                                          child: GestureDetector(
                                            onTap: _isSubmitting
                                                ? null
                                                : () => setState(
                                                      () => _evidenceFiles
                                                          .removeAt(idx),
                                                    ),
                                            child: Container(
                                              padding: const EdgeInsets.all(3),
                                              decoration: const BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                color: Colors.white,
                                                size: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed:
                                      _isSubmitting ? null : _submitAppeal,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ZevColors.secondaryBlue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Submit Appeal',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandingSummary() {
    final isBanned = _profileStanding['is_banned'] == true;
    final isRestricted = _profileStanding['is_restricted'] == true;
    final banReason = (_profileStanding['ban_reason'] ?? '').toString().trim();
    final restrReason =
        (_profileStanding['restriction_reason'] ?? '').toString().trim();
    final warningCount = (_profileStanding['warning_count'] as num?)?.toInt() ?? 0;

    final Color badgeColor = isBanned
        ? ZevColors.errorRed
        : (isRestricted ? const Color(0xFFD97706) : ZevColors.successGreen);
    final String statusLabel = isBanned
        ? 'Account Suspended'
        : (isRestricted ? 'Account Restricted' : 'Good Standing');

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: badgeColor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$warningCount warning${warningCount == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.textMuted,
                ),
              ),
            ],
          ),
          if (banReason.isNotEmpty || restrReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              banReason.isNotEmpty ? banReason : restrReason,
              style: const TextStyle(
                fontSize: 12.5,
                color: ZevColors.deepNavy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRestrictionChip({required String? id, required String label}) {
    final selected = _selectedRestrictionId == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedRestrictionId = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? ZevColors.secondaryBlue : ZevColors.softSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? ZevColors.secondaryBlue : ZevColors.border,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : ZevColors.deepNavy,
          ),
        ),
      ),
    );
  }

  Widget _buildAppealHistoryCard(Map<String, dynamic> a) {
    final status = (a['status'] ?? 'pending').toString();
    final reason = (a['reason'] ?? '').toString();
    final explanation = (a['explanation'] ?? '').toString();
    final adminResp = (a['admin_response'] ?? '').toString().trim();
    final createdAt = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final evidence = (a['evidence_urls'] is List)
        ? (a['evidence_urls'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    Color statusColor;
    switch (status) {
      case 'approved':
        statusColor = ZevColors.successGreen;
        break;
      case 'rejected':
        statusColor = ZevColors.errorRed;
        break;
      case 'under_review':
        statusColor = ZevColors.secondaryBlue;
        break;
      default:
        statusColor = const Color(0xFFD97706);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    TimeAgo.format(createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: ZevColors.textMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              explanation,
              style: const TextStyle(
                fontSize: 12,
                color: ZevColors.textSecondary,
                height: 1.35,
              ),
            ),
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: evidence.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, idx) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: ZevCachedImage.grid(imageUrl: evidence[idx]),
                    ),
                  ),
                ),
              ),
            ],
            if (adminResp.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ZevColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Moderation Response',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.secondaryBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      adminResp,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
