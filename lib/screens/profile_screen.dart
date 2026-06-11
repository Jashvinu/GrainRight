import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import '../config/brand_assets.dart';
import '../config/theme.dart';
import '../controllers/main_auth_controller.dart';

class FarmerProfileScreen extends StatelessWidget {
  final dynamic profile; // Using dynamic for now to match the local _FarmerProfile
  final dynamic farm;
  final String avatarAsset;

  const FarmerProfileScreen({
    super.key,
    required this.profile,
    required this.farm,
    this.avatarAsset = BrandAssets.farmerAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    final farmerQrData = jsonEncode({
      'type': 'farmer_profile',
      'allowedRole': 'fpo_fpc',
      'brand': 'Kalsubai Farms',
      'farmerId': profile.farmerId,
      'product': farm.product,
      'farmerName': profile.name,
      'phone': profile.phone,
      'village': '${profile.location ?? profile.village}',
      'location': '${profile.location ?? profile.village}',
      'primaryFarm': farm.name,
      'crop': farm.crop,
      'area': farm.area,
      'variety': farm.variety,
      'source': 'remote_supabase',
      'verified': true,
    });

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Detailed Profile'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          _RevealSection(
            delayMs: 0,
            child: _ProfileHeader(
              profileName: profile.name,
              avatarAsset: avatarAsset,
            ),
          ),
          const SizedBox(height: 20),
          _RevealSection(
            delayMs: 60,
            child: _SectionHeader(title: 'Farmer Identity QR'),
          ),
          _RevealSection(
            delayMs: 90,
            child: _QRSection(farmerQrData: farmerQrData, profile: profile),
          ),
          const SizedBox(height: 24),
          _RevealSection(
            delayMs: 120,
            child: _SectionHeader(title: 'Personal Information'),
          ),
          const SizedBox(height: 8),
          _RevealSection(
            delayMs: 140,
            child: _InfoCard(items: [
              _InfoItem(label: 'Farmer ID', value: profile.farmerId),
              _InfoItem(label: 'Phone Number', value: profile.phone),
              _InfoItem(label: 'Location', value: '${profile.location ?? profile.village}'),
              const _InfoItem(label: 'Gender', value: 'Male'),
              const _InfoItem(label: 'Age', value: '42 years'),
            ]),
          ),
          const SizedBox(height: 24),
          _RevealSection(
            delayMs: 180,
            child: _SectionHeader(title: 'Farm Statistics'),
          ),
          const SizedBox(height: 8),
          _RevealSection(
            delayMs: 210,
            child: _InfoCard(
              items: [
                _InfoItem(label: 'Primary Farm', value: farm.name),
                const _InfoItem(label: 'Total Area', value: '4.0 acres'),
              _InfoItem(label: 'Current Crop', value: farm.crop),
              const _InfoItem(label: 'Soil Health', value: 'Excellent'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _RevealSection(
            delayMs: 240,
            child: _SectionHeader(title: 'Rewards & Achievements'),
          ),
          const SizedBox(height: 10),
          const _RevealSection(
            delayMs: 270,
            child: _RewardsSection(),
          ),
          const SizedBox(height: 24),
          _RevealSection(
            delayMs: 300,
            child: _SectionHeader(title: 'Settings & Support'),
          ),
          const SizedBox(height: 10),
          _RevealSection(
            delayMs: 330,
            child: _ProfileHeaderBlock(profile: profile),
          ),
          const SizedBox(height: 10),
          _RevealSection(
            delayMs: 360,
            child: _MenuCard(
              children: [
                _MenuRow(
                  icon: Icons.settings_outlined,
                  title: 'Account Settings',
                  onTap: () => Get.snackbar(
                    'Account Settings',
                    'Available in next update.',
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.support_agent_rounded,
                  title: 'Help & Support',
                  onTap: () => Get.snackbar(
                    'Help & Support',
                    'Contact your local coordinator for help.',
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.logout_rounded,
                  title: 'Logout',
                  color: Colors.redAccent,
                  onTap: auth.logout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _ProfileFooter(profile: profile),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String profileName;
  final String avatarAsset;

  const _ProfileHeader({required this.profileName, required this.avatarAsset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppTheme.greenPale,
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: AssetImage(avatarAsset),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profileName,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Detailed Farmer Profile',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(Icons.verified_rounded, color: AppTheme.green, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Verified Farmer',
                      style: TextStyle(
                        color: AppTheme.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderBlock extends StatelessWidget {
  final dynamic profile;

  const _ProfileHeaderBlock({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Farmer ID: ${profile.farmerId}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.verified_user_outlined, color: AppTheme.green),
          const SizedBox(width: 6),
          const Text('Trusted Profile', style: TextStyle(color: AppTheme.green)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: AppTheme.greenDark,
        ),
      ),
    );
  }
}

class _QRSection extends StatelessWidget {
  final String farmerQrData;
  final dynamic profile;

  const _QRSection({required this.farmerQrData, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: QrImageView(
                data: farmerQrData,
                version: QrVersions.auto,
                size: 160,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            profile.farmerId,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.greenDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<_InfoItem> items;

  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    items[i].label,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    items[i].value,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            if (i < items.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});
}

class _RewardsSection extends StatelessWidget {
  const _RewardsSection();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: const [
          _RewardBadge(
            icon: Icons.emoji_events_rounded,
            label: 'Top Harvester',
            color: Color(0xFFF59E0B),
          ),
          _RewardBadge(
            icon: Icons.eco_rounded,
            label: 'Organic Pro',
            color: Color(0xFF16A34A),
          ),
          _RewardBadge(
            icon: Icons.star_rounded,
            label: 'Early Adopter',
            color: Color(0xFF2563EB),
          ),
          SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _RewardBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RewardBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;

  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  const _MenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color ?? AppTheme.green),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    );
  }
}

class _ProfileFooter extends StatelessWidget {
  final dynamic profile;

  const _ProfileFooter({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Verified for farm access: ${profile.farmerId}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
      ),
    );
  }
}

class _RevealSection extends StatelessWidget {
  final Widget child;
  final int delayMs;

  const _RevealSection({required this.child, required this.delayMs});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('$delayMs'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 430 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
