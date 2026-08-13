import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/tenant_service.dart';
import '../../theme/app_theme.dart';
import 'whatsapp_connect_sheet.dart';
import 'whatsapp_verified_sheet.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final tenantService = TenantService();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tenantService.watchUserProfile(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data();
        final tenantId = userData?['tenantId'] as String?;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Keyed by tenantId so this subtree's State (and the streams it
            // opens once in initState) survives unrelated rebuilds of this
            // StreamBuilder instead of re-querying every time.
            if (tenantId != null)
              _TenantSection(
                key: ValueKey(tenantId),
                tenantId: tenantId,
                name: userData?['name'] as String?,
                photoUrl: userData?['photoUrl'] as String?,
              ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceSolid,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                title: const Text('Log Out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                onTap: authService.logout,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileHeader extends StatefulWidget {
  final String tenantId;
  final String? name;
  final String? photoUrl;
  final bool isAdmin;
  final bool whatsappConnected;
  final String? whatsappPhoneDisplay;
  final String? whatsappVerifiedName;
  final String? whatsappQualityRating;
  final String? whatsappCodeVerificationStatus;

  const _ProfileHeader({
    required this.tenantId,
    this.name,
    this.photoUrl,
    required this.isAdmin,
    required this.whatsappConnected,
    this.whatsappPhoneDisplay,
    this.whatsappVerifiedName,
    this.whatsappQualityRating,
    this.whatsappCodeVerificationStatus,
  });

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  bool _isUploading = false;

  Future<void> _changePhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      await ProfileService().uploadProfilePhoto(picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update photo. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = (widget.name?.isNotEmpty == true) ? widget.name![0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _isUploading ? null : _changePhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: widget.photoUrl == null ? AppColors.primaryGradient : null,
                    shape: BoxShape.circle,
                    image: widget.photoUrl != null
                        ? DecorationImage(image: NetworkImage(widget.photoUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _isUploading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : (widget.photoUrl == null
                          ? Text(
                              initial,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22),
                            )
                          : null),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSolid,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name?.isNotEmpty == true ? widget.name! : 'Your Name',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (widget.whatsappConnected)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showWhatsappVerifiedDetails(
                      context,
                      phoneDisplay: widget.whatsappPhoneDisplay,
                      verifiedName: widget.whatsappVerifiedName,
                      qualityRating: widget.whatsappQualityRating,
                      codeVerificationStatus: widget.whatsappCodeVerificationStatus,
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.whatsappPhoneDisplay ?? 'Connected',
                            style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (widget.whatsappCodeVerificationStatus == 'VERIFIED') const VerifiedBadge(),
                      ],
                    ),
                  )
                else if (widget.isAdmin)
                  GestureDetector(
                    onTap: () => showConnectWhatsappSheet(context, widget.tenantId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Connect WhatsApp',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                  )
                else
                  Text(
                    'WhatsApp not connected',
                    style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TenantSection extends StatefulWidget {
  final String tenantId;
  final String? name;
  final String? photoUrl;

  const _TenantSection({super.key, required this.tenantId, this.name, this.photoUrl});

  @override
  State<_TenantSection> createState() => _TenantSectionState();
}

class _TenantSectionState extends State<_TenantSection> {
  final _tenantService = TenantService();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _memberStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _tenantStream;

  @override
  void initState() {
    super.initState();
    _memberStream = _tenantService.watchMembership(widget.tenantId);
    _tenantStream = _tenantService.watchTenant(widget.tenantId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _memberStream,
      builder: (context, memberSnapshot) {
        final isAdmin = memberSnapshot.data?.data()?['role'] == 'admin';

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _tenantStream,
          builder: (context, tenantSnapshot) {
            final data = tenantSnapshot.data?.data();
            if (data == null) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _ProfileHeader(
                    tenantId: widget.tenantId,
                    name: widget.name,
                    photoUrl: widget.photoUrl,
                    isAdmin: isAdmin,
                    whatsappConnected: data['whatsappConnected'] == true,
                    whatsappPhoneDisplay: data['whatsappPhoneDisplay'] as String?,
                    whatsappVerifiedName: data['whatsappVerifiedName'] as String?,
                    whatsappQualityRating: data['whatsappQualityRating'] as String?,
                    whatsappCodeVerificationStatus: data['whatsappCodeVerificationStatus'] as String?,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _BusinessCard(
                    tenantId: widget.tenantId,
                    businessName: data['businessName'] as String? ?? '',
                    inviteCode: data['inviteCode'] as String? ?? '',
                    canRegenerate: isAdmin,
                  ),
                ),
                if (isAdmin) ...[
                  _PendingRequestsSection(tenantId: widget.tenantId),
                  const SizedBox(height: 20),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _BusinessCard extends StatefulWidget {
  final String tenantId;
  final String businessName;
  final String inviteCode;
  final bool canRegenerate;

  const _BusinessCard({
    required this.tenantId,
    required this.businessName,
    required this.inviteCode,
    required this.canRegenerate,
  });

  @override
  State<_BusinessCard> createState() => _BusinessCardState();
}

class _BusinessCardState extends State<_BusinessCard> {
  bool _isRegenerating = false;

  Future<void> _regenerate() async {
    setState(() => _isRegenerating = true);
    try {
      await TenantService().regenerateInviteCode(widget.tenantId, widget.inviteCode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New invite code generated'), duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _isRegenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.businessName,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invite teammates with this code (expires in 48h)',
                  style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 12.5),
                ),
              ),
              if (widget.canRegenerate)
                GestureDetector(
                  onTap: _isRegenerating ? null : _regenerate,
                  child: _isRegenerating
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.inviteCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite code copied'), duration: Duration(seconds: 2)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.inviteCode,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const Icon(Icons.copy_rounded, color: AppColors.primary, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRequestsSection extends StatelessWidget {
  final String tenantId;

  const _PendingRequestsSection({required this.tenantId});

  @override
  Widget build(BuildContext context) {
    final tenantService = TenantService();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: tenantService.watchPendingRequests(tenantId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceSolid,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pending Requests (${docs.length})',
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 12),
              for (final doc in docs) _PendingRequestRow(tenantId: tenantId, uid: doc.id, email: doc.data()['email'] as String? ?? ''),
            ],
          ),
        );
      },
    );
  }
}

class _PendingRequestRow extends StatefulWidget {
  final String tenantId;
  final String uid;
  final String email;

  const _PendingRequestRow({required this.tenantId, required this.uid, required this.email});

  @override
  State<_PendingRequestRow> createState() => _PendingRequestRowState();
}

class _PendingRequestRowState extends State<_PendingRequestRow> {
  bool _isBusy = false;

  Future<void> _respond(bool approve) async {
    setState(() => _isBusy = true);
    final tenantService = TenantService();
    if (approve) {
      await tenantService.approveRequest(widget.tenantId, widget.uid);
    } else {
      await tenantService.rejectRequest(widget.tenantId, widget.uid);
    }
    // No need to reset _isBusy: the stream removes this row once resolved.
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.email,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isBusy)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.error, size: 20),
              onPressed: () => _respond(false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
              onPressed: () => _respond(true),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}
