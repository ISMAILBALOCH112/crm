import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NavItemData {
  final IconData icon;
  final String label;
  final int badgeCount;

  const NavItemData({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// Bottom navigation where the active tab's icon sits inside a small
/// gradient badge, and inactive tabs stay as plain outlined icons.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavItemData> items;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            return _NavItem(
              item: items[index],
              isActive: index == currentIndex,
              onTap: () => onTap(index),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavItemData item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({required this.item, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: isActive ? AppColors.primaryGradient : null,
                    color: isActive ? null : Colors.transparent,
                    shape: BoxShape.circle,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : [],
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      item.icon,
                      key: ValueKey(isActive),
                      color: isActive ? Colors.white : AppColors.textSecondary,
                      size: isActive ? 22 : 24,
                    ),
                  ),
                ),
                if (item.badgeCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.surfaceSolid, width: 1.5),
                      ),
                      child: Text(
                        item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
