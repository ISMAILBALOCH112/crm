import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
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

  static const _tabs = [
    ChatTab(),
    OrdersTab(),
    BotTab(),
    SettingsTab(),
  ];

  static const _navItems = [
    NavItemData(icon: Icons.chat_bubble_rounded, label: 'Chat'),
    NavItemData(icon: Icons.shopping_bag_rounded, label: 'Orders'),
    NavItemData(icon: Icons.auto_awesome_rounded, label: 'Bot'),
    NavItemData(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    setState(() => _currentIndex = index);
    // Jump instantly rather than animating: sliding through every tab in
    // between (e.g. Settings -> Bot -> Orders -> Chat) briefly renders all
    // of them, which reads as a glitch. Swiping by hand still animates
    // smoothly since PageView drives that itself.
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goToTab(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            children: _tabs,
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          currentIndex: _currentIndex,
          onTap: _goToTab,
          items: _navItems,
        ),
      ),
    );
  }
}
