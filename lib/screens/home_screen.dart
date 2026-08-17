import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/push_service.dart';
import '../services/subscription_service.dart';
import '../services/tenant_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/plan_payment_warning.dart';
import 'plan_billing_screen.dart';
import 'tabs/bot_tab.dart';
import 'tabs/chat_tab.dart';
import 'tabs/orders_tab.dart';
import 'tabs/settings_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _pageController = PageController();
  String? _warnedSignature;

  List<NavItemData> _navItems(int unreadChats) => [
        NavItemData(icon: Icons.chat_bubble_rounded, label: 'Chat', badgeCount: unreadChats),
        const NavItemData(icon: Icons.shopping_bag_rounded, label: 'Orders'),
        const NavItemData(icon: Icons.auto_awesome_rounded, label: 'Bot'),
        const NavItemData(icon: Icons.settings_rounded, label: 'Settings'),
      ];

  int _unreadChatCount(QuerySnapshot<Map<String, dynamic>>? snap) {
    if (snap == null) return 0;
    var n = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['isArchived'] == true) continue;
      final unread = (data['unreadCount'] as num?)?.toInt() ?? 0;
      if (unread > 0) n++;
    }
    return n;
  }

  @override
  void initState() {
    super.initState();
    PushService.instance.init();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    setState(() => _currentIndex = index);
    _pageController.jumpToPage(index);
  }

  String _signature(TenantBilling b) {
    return '${b.writeAllowed}|${b.planLockReason}|${b.planExpiresAt?.millisecondsSinceEpoch}|${b.isExpiringSoon}';
  }

  Future<void> _maybeShowWarning(String tenantId, TenantBilling billing) async {
    if (billing.writeAllowed && !billing.isExpiringSoon) return;
    final sig = _signature(billing);
    if (_warnedSignature == sig) return;
    _warnedSignature = sig;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await showPlanPaymentWarningDialog(
      context,
      billing: billing,
      onRenew: () => openPlanBillingScreen(context, tenantId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goToTab(0);
      },
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: TenantService().watchUserProfile(),
        builder: (context, userSnap) {
          final tenantId = userSnap.data?.data()?['tenantId'] as String?;
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  if (tenantId != null)
                    StreamBuilder<TenantBilling>(
                      stream: SubscriptionService().watchBilling(tenantId),
                      builder: (context, billSnap) {
                        final billing = billSnap.data;
                        if (billing != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _maybeShowWarning(tenantId, billing);
                          });
                        }
                        if (billing == null || (billing.writeAllowed && !billing.isExpiringSoon)) {
                          return const SizedBox.shrink();
                        }
                        final expired = !billing.writeAllowed;
                        final color = expired ? AppColors.error : AppColors.accentWarm;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => showPlanPaymentWarningDialog(
                              context,
                              billing: billing,
                              onRenew: () => openPlanBillingScreen(context, tenantId),
                            ),
                            child: Ink(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: expired
                                      ? [const Color(0xFFFFE4E6), const Color(0xFFFFF1F2)]
                                      : [const Color(0xFFFFE8D0), const Color(0xFFFFF6EB)],
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    billing.wasKeyLocked
                                        ? Icons.gpp_bad_rounded
                                        : (expired ? Icons.warning_amber_rounded : Icons.timelapse_rounded),
                                    color: color,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      billing.bannerText,
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => openPlanBillingScreen(context, tenantId),
                                    child: Text('Renew', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  Expanded(
                      child: PageView(
                      controller: _pageController,
                      onPageChanged: (index) => setState(() => _currentIndex = index),
                      children: const [
                        ChatTab(),
                        OrdersTab(),
                        BotTab(),
                        SettingsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: tenantId == null
                ? AppBottomNav(
                    currentIndex: _currentIndex,
                    onTap: _goToTab,
                    items: _navItems(0),
                  )
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: ChatService().watchContacts(tenantId),
                    builder: (context, contactSnap) {
                      final unread = _unreadChatCount(contactSnap.data);
                      return AppBottomNav(
                        currentIndex: _currentIndex,
                        onTap: _goToTab,
                        items: _navItems(unread),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
