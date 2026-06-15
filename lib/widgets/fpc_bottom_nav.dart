import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/theme.dart';

enum FpcNavTab { home, farmerScan, receiver, grading }

class FpcBottomNavBar extends StatelessWidget {
  final FpcNavTab current;

  const FpcBottomNavBar({super.key, required this.current});

  static const Map<String, String> gradingArgs = {
    'mode': 'fpc',
    'farmerId': 'FPC-WALK-IN',
    'farmerName': 'Walk-in customer',
    'fpcCustomerId': 'FPC-WALK-IN',
    'fpcCustomerName': 'Walk-in customer',
    'farmId': 'FPC-COUNTER',
    'farmName': 'FPC Procurement Lot',
    'crop': 'Finger Millet',
    'variety': 'Local',
    'village': 'FPC collection center',
    'product': 'Grain lot',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFDDE8D4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 72,
              child: Row(
                children: [
                  _NavItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Home',
                    selected: current == FpcNavTab.home,
                    onTap: () => _go(FpcNavTab.home),
                  ),
                  _NavItem(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Farmers',
                    selected: current == FpcNavTab.farmerScan,
                    onTap: () => _go(FpcNavTab.farmerScan),
                  ),
                  _NavItem(
                    icon: Icons.assignment_turned_in_outlined,
                    label: 'Receiver',
                    selected: current == FpcNavTab.receiver,
                    onTap: () => _go(FpcNavTab.receiver),
                  ),
                  _NavItem(
                    icon: Icons.grain_rounded,
                    label: 'Grading',
                    selected: current == FpcNavTab.grading,
                    onTap: () => _go(FpcNavTab.grading),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _go(FpcNavTab tab) {
    if (tab == current) return;
    switch (tab) {
      case FpcNavTab.home:
        Get.offNamed('/fpo');
        return;
      case FpcNavTab.farmerScan:
        Get.offNamed('/fpo/scan-farmer');
        return;
      case FpcNavTab.receiver:
        Get.offNamed('/fpo/receiver');
        return;
      case FpcNavTab.grading:
        Get.offNamed('/fpo/grain-grading', arguments: gradingArgs);
        return;
    }
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? AppTheme.greenPale : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                height: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 23,
                      color: selected ? AppTheme.greenDark : AppTheme.textMuted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppTheme.greenDark : AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
