import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/tenant_service.dart';
import '../../services/tenant_roles.dart';
import '../../theme/app_theme.dart';
import '../abandoned_cart_settings_screen.dart';
import '../broadcast_screen.dart';
import '../business_profile_screen.dart';
import '../inbox_analytics_screen.dart';
import '../invoice_branding_screen.dart';
import '../parcel_payment_settings_screen.dart';
import '../plan_billing_screen.dart';
import '../../services/subscription_service.dart';
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
        if (userSnapshot.connectionState == ConnectionState.waiting && !userSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        final userData = userSnapshot.data?.data();
        final tenantId = userData?['tenantId'] as String? ?? userData?['pendingTenantId'] as String?;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (tenantId != null)
              _TenantSection(
                key: ValueKey(tenantId),
                tenantId: tenantId,
                name: userData?['name'] as String?,
                photoUrl: userData?['photoUrl'] as String?,
              ),
            if (tenantId != null) const SizedBox(height: 20),
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _memberSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tenantSub;

  Map<String, dynamic> _tenantData = const {};
  bool _tenantLoading = true;
  Object? _tenantError;

  String? _memberRole;
  bool _memberLoading = true;

  @override
  void initState() {
    super.initState();
    _memberSub = _tenantService.watchMembership(widget.tenantId).listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _memberRole = snap.data()?['role'] as String?;
          _memberLoading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _memberLoading = false);
      },
    );
    _tenantSub = _tenantService.watchTenant(widget.tenantId).listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _tenantData = snap.data() ?? const {};
          _tenantLoading = false;
          _tenantError = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _tenantLoading = false;
          _tenantError = e;
        });
      },
    );
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    _tenantSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tenantLoading && _tenantData.isEmpty && _tenantError == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final data = _tenantData;
    final isAdmin = TenantRoles.isAdmin(_memberRole);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tenantError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
              ),
              child: const Text(
                'Could not load team settings. Check your connection and try again.',
                style: TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),
          ),
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
          child: _TeamInviteCard(
            tenantId: widget.tenantId,
            businessName: data['businessName'] as String? ?? '',
            inviteLinkToken: data['inviteLinkToken'] as String?,
            inviteLinkExpiresAt: (data['inviteLinkExpiresAt'] as Timestamp?)?.toDate(),
            canManage: isAdmin && !_memberLoading,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _MembersSection(tenantId: widget.tenantId, isAdmin: isAdmin),
        ),
        if (isAdmin) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _PlanLinksCard(tenantId: widget.tenantId),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _FeatureLinksCard(tenantId: widget.tenantId),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: _RolesGuideCard(),
          ),
          _PendingRequestsSection(tenantId: widget.tenantId),
        ] else if (!_memberLoading) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _FeatureLinksCard(tenantId: widget.tenantId, agentView: true),
          ),
        ],
      ],
    );
  }
}

class _TeamInviteCard extends StatefulWidget {
  final String tenantId;
  final String businessName;
  final String? inviteLinkToken;
  final DateTime? inviteLinkExpiresAt;
  final bool canManage;

  const _TeamInviteCard({
    required this.tenantId,
    required this.businessName,
    required this.inviteLinkToken,
    required this.inviteLinkExpiresAt,
    required this.canManage,
  });

  @override
  State<_TeamInviteCard> createState() => _TeamInviteCardState();
}

class _TeamInviteCardState extends State<_TeamInviteCard> {
  bool _busy = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _token = widget.inviteLinkToken;
    if (widget.canManage) _ensureLink();
  }

  @override
  void didUpdateWidget(covariant _TeamInviteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.inviteLinkToken != oldWidget.inviteLinkToken) {
      _token = widget.inviteLinkToken;
    }
  }

  Future<void> _ensureLink() async {
    if (!widget.canManage) return;
    setState(() => _busy = true);
    try {
      final t = await TenantService().ensureInviteLink(widget.tenantId);
      if (mounted) setState(() => _token = t);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not prepare invite link')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regenerate() async {
    if (!widget.canManage) return;
    setState(() => _busy = true);
    try {
      final t = await TenantService().regenerateInviteLink(widget.tenantId);
      if (mounted) {
        setState(() => _token = t);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New invite link generated'), duration: Duration(seconds: 2)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not regenerate link')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _link {
    final t = (_token ?? '').trim();
    if (t.isEmpty) return '';
    return TenantService.inviteLinkUrl(t);
  }

  Future<void> _copy() async {
    final link = _link;
    if (link.isEmpty) {
      await _ensureLink();
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _share() async {
    var link = _link;
    if (link.isEmpty) {
      await _ensureLink();
      link = _link;
    }
    if (link.isEmpty) return;
    final name = widget.businessName.trim().isEmpty ? 'our team' : widget.businessName.trim();
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Join $name on WaTech. Open this link, create your account, and you\'re in:\n$link\n\n(App link: ${TenantService.inviteAppLinkUrl((_token ?? '').trim())})',
      ),
    );
  }

  String get _expiryLabel {
    final exp = widget.inviteLinkExpiresAt;
    if (exp == null) return 'Expires in 48 hours';
    final left = exp.difference(DateTime.now());
    if (left.isNegative) return 'Expired — tap refresh for a new link';
    if (left.inHours >= 1) return 'Expires in ${left.inHours}h';
    return 'Expires in ${left.inMinutes.clamp(1, 59)}m';
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;

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
                child: const Icon(Icons.group_add_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Team',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              if (widget.canManage)
                IconButton(
                  onPressed: _busy ? null : _regenerate,
                  tooltip: 'New link',
                  icon: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.canManage
                ? 'Agent invite — https link share karo. $_expiryLabel'
                : 'Only admins can share invite links.',
            style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.95), fontSize: 12.5, height: 1.35),
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Text(
                link.isEmpty ? 'Preparing invite link…' : link,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _copy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy link'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RolesGuideCard extends StatelessWidget {
  const _RolesGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roles',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          SizedBox(height: 8),
          Text(
            'Admin — team, WhatsApp, bot, catalog, order delete, templates\n'
            'Agent — chat, create/edit orders, CN book, payments, view catalog',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MembersSection extends StatelessWidget {
  final String tenantId;
  final bool isAdmin;

  const _MembersSection({required this.tenantId, required this.isAdmin});

  Future<void> _changeRole(BuildContext context, String uid, String title, String nextRole) async {
    final label = nextRole == TenantRoles.admin ? 'admin' : 'agent';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(nextRole == TenantRoles.admin ? 'Make admin?' : 'Make agent?'),
        content: Text('Change $title to $label?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await TenantService().setMemberRole(tenantId: tenantId, memberUid: uid, role: nextRole);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title is now $label')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService().currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: TenantService().watchMembers(tenantId),
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
              const Text(
                'Members',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 12),
              ...docs.map((doc) {
                final data = doc.data();
                final uid = doc.id;
                final role = (data['role'] as String?) ?? 'agent';
                final name = (data['name'] as String?)?.trim();
                final email = (data['email'] as String?)?.trim() ?? '';
                final title = (name != null && name.isNotEmpty)
                    ? name
                    : (email.isNotEmpty ? email : uid);
                final subtitle = email.isNotEmpty && title != email ? email : null;
                final canManageMember = isAdmin && uid != me;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          role.toUpperCase(),
                          style: TextStyle(
                            color: role == 'admin' ? AppColors.primary : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (canManageMember) ...[
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            tooltip: 'Manage',
                            icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
                            onSelected: (value) async {
                              if (value == 'remove') {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Remove member?'),
                                    content: Text('Remove $title from this team?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                try {
                                  await TenantService().removeMember(tenantId, uid);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Member removed')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                                    );
                                  }
                                }
                              } else if (value == 'make_admin') {
                                await _changeRole(context, uid, title, TenantRoles.admin);
                              } else if (value == 'make_agent') {
                                await _changeRole(context, uid, title, TenantRoles.agent);
                              }
                            },
                            itemBuilder: (context) => [
                              if (role != TenantRoles.admin)
                                const PopupMenuItem(value: 'make_admin', child: Text('Make admin')),
                              if (role != TenantRoles.agent)
                                const PopupMenuItem(value: 'make_agent', child: Text('Make agent')),
                              const PopupMenuItem(value: 'remove', child: Text('Remove')),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
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

class _PlanLinksCard extends StatelessWidget {
  final String tenantId;

  const _PlanLinksCard({required this.tenantId});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          StreamBuilder<TenantBilling>(
            stream: SubscriptionService().watchBilling(tenantId),
            builder: (context, snap) {
              final b = snap.data;
              final subtitle = b == null
                  ? 'Trial / license key'
                  : '${b.planLabel} · expires ${b.expiryLabel}${b.writeAllowed ? '' : ' · READ ONLY'}';
              return ListTile(
                leading: const Icon(Icons.workspace_premium_outlined, color: AppColors.primary),
                title: const Text('Plan & billing', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openPlanBillingScreen(context, tenantId),
              );
            },
          ),
          StreamBuilder<bool>(
            stream: SubscriptionService().watchIsPlatformAdmin(),
            builder: (context, snap) {
              if (snap.data != true) return const SizedBox.shrink();
              return Column(
                children: [
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.vpn_key_outlined, color: AppColors.primary),
                    title: const Text('Platform · License keys', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Generate keys for customers'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => openPlatformKeysScreen(context),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureLinksCard extends StatelessWidget {
  final String tenantId;
  final bool agentView;

  const _FeatureLinksCard({required this.tenantId, this.agentView = false});

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          if (!agentView) ...[
            _tile(
              context: context,
              icon: Icons.palette_outlined,
              title: 'Invoice branding',
              subtitle: 'Logo & color on PDFs',
              onTap: () => openInvoiceBrandingScreen(context, tenantId),
            ),
            const Divider(height: 1),
            _tile(
              context: context,
              icon: Icons.campaign_outlined,
              title: 'Broadcast',
              subtitle: 'Send WhatsApp to many contacts',
              onTap: () => openBroadcastScreen(context, tenantId),
            ),
            const Divider(height: 1),
            _tile(
              context: context,
              icon: Icons.account_balance_wallet_outlined,
              title: 'Parcel payment',
              subtitle: 'JazzCash & EasyPaisa numbers for orders',
              onTap: () => openParcelPaymentSettings(context, tenantId),
            ),
            const Divider(height: 1),
            _tile(
              context: context,
              icon: Icons.shopping_cart_outlined,
              title: 'Auto follow-up',
              subtitle: 'No-reply / no-order reminders',
              onTap: () => openAbandonedCartSettings(context, tenantId),
            ),
            const Divider(height: 1),
          ],
          _tile(
            context: context,
            icon: Icons.insights_outlined,
            title: 'Inbox analytics',
            subtitle: 'Unread, muted, oldest waiting',
            onTap: () => openInboxAnalytics(context, tenantId),
          ),
          const Divider(height: 1),
          _tile(
            context: context,
            icon: Icons.storefront_outlined,
            title: 'WhatsApp profile',
            subtitle: 'Verified name, quality, Meta edit link',
            onTap: () => openBusinessProfileScreen(context, tenantId),
          ),
        ],
      ),
    );
  }
}
