import 'package:flutter/material.dart';

import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';

enum FarmerBottomNavItem { home, farm, aiChat, marketplace, inventory }

class FarmerFloatingBottomNav extends StatelessWidget {
  final FarmerBottomNavItem selectedItem;
  final ValueChanged<FarmerBottomNavItem> onSelected;

  const FarmerFloatingBottomNav({
    super.key,
    required this.selectedItem,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFDDE9D5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.greenDark.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: _FarmerNavButton(
                  item: FarmerBottomNavItem.home,
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  label: UiStrings.t('nav_home'),
                  selectedItem: selectedItem,
                  onSelected: onSelected,
                ),
              ),
              Expanded(
                child: _FarmerNavButton(
                  item: FarmerBottomNavItem.farm,
                  icon: Icons.agriculture_outlined,
                  selectedIcon: Icons.agriculture_rounded,
                  label: UiStrings.t('nav_farm'),
                  selectedItem: selectedItem,
                  onSelected: onSelected,
                ),
              ),
              Expanded(
                child: _FarmerNavButton(
                  item: FarmerBottomNavItem.aiChat,
                  icon: Icons.auto_awesome_outlined,
                  selectedIcon: Icons.auto_awesome_rounded,
                  label: UiStrings.t('ai_chat'),
                  selectedItem: selectedItem,
                  onSelected: onSelected,
                ),
              ),
              Expanded(
                child: _FarmerNavButton(
                  item: FarmerBottomNavItem.marketplace,
                  icon: Icons.storefront_outlined,
                  selectedIcon: Icons.storefront_rounded,
                  label: UiStrings.t('nav_apmc_short'),
                  selectedItem: selectedItem,
                  onSelected: onSelected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FarmerNavButton extends StatelessWidget {
  final FarmerBottomNavItem item;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final FarmerBottomNavItem selectedItem;
  final ValueChanged<FarmerBottomNavItem> onSelected;

  const _FarmerNavButton({
    required this.item,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selectedItem,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedItem == item;
    final color = selected ? Colors.white : AppTheme.textMuted;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onSelected(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? AppTheme.greenDark : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 160),
                scale: selected ? 1.08 : 1,
                curve: Curves.easeOutCubic,
                child: Icon(
                  selected ? selectedIcon : icon,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
