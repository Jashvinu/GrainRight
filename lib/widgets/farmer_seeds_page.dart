import 'package:flutter/material.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import 'farmer_crop_program_card.dart';

class FarmerSeedFarmOption {
  final int sourceIndex;
  final String id;
  final String name;
  final String crop;
  final String variety;

  const FarmerSeedFarmOption({
    required this.sourceIndex,
    required this.id,
    required this.name,
    required this.crop,
    required this.variety,
  });
}

class FarmerSeedsPage extends StatelessWidget {
  final List<FarmerSeedFarmOption> farms;
  final int selectedIndex;
  final ValueChanged<int> onFarmSelected;
  final VoidCallback onAddFarm;
  final bool hasOnlySownFarms;

  const FarmerSeedsPage({
    super.key,
    required this.farms,
    required this.selectedIndex,
    required this.onFarmSelected,
    required this.onAddFarm,
    this.hasOnlySownFarms = false,
  });

  @override
  Widget build(BuildContext context) {
    if (farms.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 112),
        children: [
          _SeedsPurposeCard(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Icon(
                    hasOnlySownFarms
                        ? Icons.task_alt_rounded
                        : Icons.add_location_alt_outlined,
                    size: 42,
                    color: AppTheme.green,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasOnlySownFarms
                        ? UiStrings.fromEnglish(
                            'Seed is already sown on every farm. Purchase history and delivery tracking remain available in Inventory.',
                          )
                        : UiStrings.t('farmer_seeds_add_farm_first'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  if (!hasOnlySownFarms)
                    FilledButton.icon(
                      onPressed: onAddFarm,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(UiStrings.t('add_first_farm')),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final selectedOptionIndex = farms.indexWhere(
      (farm) => farm.sourceIndex == selectedIndex,
    );
    final safeIndex = selectedOptionIndex < 0 ? 0 : selectedOptionIndex;
    final farm = farms[safeIndex];
    return ListView(
      key: const PageStorageKey<String>('farmer-seeds-page'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 112),
      children: [
        Text(
          UiStrings.t('farmer_seeds_select_farm'),
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: farms.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final option = farms[index];
              return FarmerSeedFarmCard(
                farm: option,
                selected: index == safeIndex,
                onTap: () => onFarmSelected(option.sourceIndex),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.spa_rounded, color: AppTheme.greenDark, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                UiStrings.t('farmer_seeds_available_programs'),
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FarmerCropProgramCard(
          key: ValueKey('farmer-seed-program-${farm.id}'),
          farmId: farm.id,
          showEmptyState: true,
        ),
        const SizedBox(height: 16),
        _SeedsPurposeCard(),
      ],
    );
  }
}

class FarmerSeedFarmCard extends StatelessWidget {
  final FarmerSeedFarmOption farm;
  final bool selected;
  final VoidCallback onTap;

  const FarmerSeedFarmCard({
    super.key,
    required this.farm,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        elevation: 0,
        color: selected ? AppTheme.greenPale : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected
                ? AppTheme.greenDark
                : AppTheme.green.withValues(alpha: 0.18),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.agriculture_rounded,
                      color: selected ? AppTheme.greenDark : AppTheme.green,
                    ),
                    const Spacer(),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.greenDark,
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  UiStrings.label(farm.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FarmTag(
                      icon: Icons.grass_rounded,
                      label: UiStrings.option(farm.crop),
                    ),
                    if (farm.variety.trim().isNotEmpty)
                      _FarmTag(
                        icon: Icons.eco_outlined,
                        label: UiStrings.option(farm.variety),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeedsPurposeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF174D2B), Color(0xFF2F7D44)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.spa_rounded, color: Colors.white, size: 34),
          const SizedBox(height: 12),
          Text(
            UiStrings.t('farmer_seeds_title'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            UiStrings.t('farmer_seeds_purpose'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PurposeStep(
                icon: Icons.edit_note_rounded,
                label: UiStrings.t('farmer_seeds_step_request'),
              ),
              _PurposeStep(
                icon: Icons.local_shipping_outlined,
                label: UiStrings.t('farmer_seeds_step_track'),
              ),
              _PurposeStep(
                icon: Icons.verified_outlined,
                label: UiStrings.t('farmer_seeds_step_confirm'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PurposeStep extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PurposeStep({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FarmTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17, color: AppTheme.greenDark),
      label: Text(label),
      backgroundColor: AppTheme.greenPale,
      side: BorderSide(color: AppTheme.green.withValues(alpha: 0.18)),
    );
  }
}
