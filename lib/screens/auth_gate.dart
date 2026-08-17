import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/tenant_service.dart';
import '../theme/app_theme.dart';
import 'business_setup_screen.dart';
import 'get_started_screen.dart';
import 'home_screen.dart';
import 'pending_approval_screen.dart';

/// Root screen. Streams both auth state and tenant status, so the UI swaps
/// automatically between Login, business setup, a pending-approval wait, or
/// Home as either changes — no manual navigation needed anywhere in the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        return snapshot.hasData ? const _TenantGate() : const GetStartedScreen();
      },
    );
  }
}

class _TenantGate extends StatelessWidget {
  const _TenantGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: TenantService().watchUserProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        final data = snapshot.data?.data();
        final tenantId = data?['tenantId'] as String?;
        if (tenantId != null) return const HomeScreen();

        final pendingTenantId = data?['pendingTenantId'] as String?;
        if (pendingTenantId != null) {
          return _ApprovalWatcher(tenantId: pendingTenantId);
        }

        return const BusinessSetupScreen();
      },
    );
  }
}

/// Watches the requester's own membership doc under [tenantId]. The moment
/// it appears (an admin approved), records the approval on their profile
/// and lets _TenantGate's stream pick up the new tenantId on next rebuild.
class _ApprovalWatcher extends StatefulWidget {
  final String tenantId;
  const _ApprovalWatcher({required this.tenantId});

  @override
  State<_ApprovalWatcher> createState() => _ApprovalWatcherState();
}

class _ApprovalWatcherState extends State<_ApprovalWatcher> {
  final _tenantService = TenantService();
  bool _marking = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _tenantService.watchMembership(widget.tenantId),
      builder: (context, memberSnapshot) {
        final isApproved = memberSnapshot.data?.exists == true;

        if (isApproved && !_marking) {
          _marking = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tenantService.markApproved(widget.tenantId);
          });
        }

        if (isApproved) return const HomeScreen();
        if (memberSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }

        // Not a member yet — check whether the request is still pending or
        // was declined, so the wait screen can say which.
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _tenantService.watchOwnPendingRequest(widget.tenantId),
          builder: (context, requestSnapshot) {
            final isRejected = requestSnapshot.data?.data()?['status'] == 'rejected';
            return PendingApprovalScreen(isRejected: isRejected);
          },
        );
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}
