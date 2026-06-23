import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../config/ui_strings.dart';

enum FarmerBottomNavItem { home, farm, aiChat, apmc, harvest }

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
      height: 86,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 68,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: const Color(0xFFDDE9D5)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.greenDark.withValues(alpha: 0.16),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
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
                  const SizedBox(width: 78),
                  Expanded(
                    child: _FarmerNavButton(
                      item: FarmerBottomNavItem.apmc,
                      icon: Icons.storefront_outlined,
                      selectedIcon: Icons.storefront_rounded,
                      label: UiStrings.t('nav_apmc_short'),
                      selectedItem: selectedItem,
                      onSelected: onSelected,
                    ),
                  ),
                  Expanded(
                    child: _FarmerNavButton(
                      item: FarmerBottomNavItem.harvest,
                      icon: Icons.inventory_2_outlined,
                      selectedIcon: Icons.inventory_2_rounded,
                      label: UiStrings.t('nav_harvest'),
                      selectedItem: selectedItem,
                      onSelected: onSelected,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: _FarmerAiNavButton(
              selected: selectedItem == FarmerBottomNavItem.aiChat,
              onTap: () => onSelected(FarmerBottomNavItem.aiChat),
            ),
          ),
        ],
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
    final color = selected ? AppTheme.greenDark : AppTheme.textMuted;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onSelected(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.greenPale.withValues(alpha: 0.78)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
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

class _FarmerAiNavButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _FarmerAiNavButton({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ringColor = selected ? AppTheme.gold : Colors.white;
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      scale: selected ? 1.05 : 1,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        elevation: selected ? 12 : 8,
        shadowColor: AppTheme.greenDark.withValues(alpha: 0.26),
        child: Ink(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.greenDark, AppTheme.green],
            ),
            border: Border.all(color: ringColor, width: selected ? 3 : 4),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Semantics(
              label: UiStrings.t('ai_chat'),
              button: true,
              child: Center(
                child: AnimatedRotation(
                  duration: const Duration(milliseconds: 220),
                  turns: selected ? 0.06 : 0,
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
