import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/widgets/app_logout_flow.dart';
import '../controllers/main_auth_controller.dart';
import '../services/fpc_preferences_service.dart';
import '../widgets/fpc_bottom_nav.dart';
import '../models/fpc_account_identity.dart';

class FpcProfileScreen extends StatelessWidget {
  const FpcProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final account = _FpcAccountSnapshot.current();
    return FpcWorkspaceScaffold(
      current: FpcNavTab.profile,
      title: UiStrings.t('fpc_profile'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
        children: [
          _FpcHeroPanel(
            icon: Icons.badge_outlined,
            title: account.organizationLabel,
            subtitle:
                'FPC account used for farmer verification and procurement',
            trailing: account.roleLabel,
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: 'Account details',
            children: [
              _InfoRow(
                icon: Icons.person_outline_rounded,
                label: 'Contact person',
                value: account.displayName,
              ),
              _InfoRow(
                icon: Icons.business_outlined,
                label: 'FPC / FPO name',
                value: account.organization,
              ),
              _InfoRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: account.email,
              ),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Mobile number',
                value: account.phone,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoSection(
            title: 'Access and sync',
            children: [
              _InfoRow(
                icon: Icons.verified_user_outlined,
                label: 'Server role',
                value: account.roleLabel,
              ),
              _InfoRow(
                icon: Icons.fingerprint_rounded,
                label: 'User ID',
                value: account.userId,
              ),
              const _InfoRow(
                icon: Icons.cloud_done_outlined,
                label: 'Profile sync',
                value: 'Auth metadata and FPC profile table',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _QuickActionGrid(
            actions: [
              _QuickAction(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Verify farmer',
                route: '/fpo/scan-farmer',
              ),
              _QuickAction(
                icon: Icons.assignment_turned_in_outlined,
                title: 'Receive lot',
                route: '/fpo/receiver',
              ),
              _QuickAction(
                icon: Icons.storefront_rounded,
                title: 'Marketplace',
                route: '/fpo/marketplace',
              ),
              _QuickAction(
                icon: Icons.fact_check_outlined,
                title: 'Review queue',
                route: '/fpo/grading-review',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FpcSettingsScreen extends StatefulWidget {
  const FpcSettingsScreen({super.key});

  @override
  State<FpcSettingsScreen> createState() => _FpcSettingsScreenState();
}

class _FpcSettingsScreenState extends State<FpcSettingsScreen> {
  FpcPreferences _preferences = const FpcPreferences();
  bool _loadingPreferences = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await FpcPreferences.load();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _loadingPreferences = false;
    });
  }

  Future<void> _savePreferences(FpcPreferences preferences) async {
    setState(() => _preferences = preferences);
    await preferences.save();
  }

  @override
  Widget build(BuildContext context) {
    final account = _FpcAccountSnapshot.current();
    return FpcWorkspaceScaffold(
      current: FpcNavTab.settings,
      title: UiStrings.t('fpc_settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
        children: [
          _FpcHeroPanel(
            icon: Icons.settings_rounded,
            title: 'Workspace settings',
            subtitle: account.organizationLabel,
            trailing: 'Active',
          ),
          const SizedBox(height: 16),
          _SettingsPanel(
            title: 'Operations',
            children: [
              if (_loadingPreferences) const LinearProgressIndicator(),
              SwitchListTile(
                value: _preferences.autoRefreshLedgers,
                onChanged: _loadingPreferences
                    ? null
                    : (value) => _savePreferences(
                        _preferences.copyWith(autoRefreshLedgers: value),
                      ),
                secondary: const Icon(Icons.sync_rounded),
                title: Text(UiStrings.t('auto_refresh_fpc_ledgers')),
                subtitle: Text(
                  UiStrings.t('auto_refresh_fpc_ledgers_desc'),
                ),
              ),
              SwitchListTile(
                value: _preferences.reviewQueueAlerts,
                onChanged: _loadingPreferences
                    ? null
                    : (value) => _savePreferences(
                        _preferences.copyWith(reviewQueueAlerts: value),
                      ),
                secondary: const Icon(Icons.fact_check_outlined),
                title: Text(UiStrings.t('review_queue_alerts')),
                subtitle: Text(
                  UiStrings.t('review_queue_alerts_desc'),
                ),
              ),
              SwitchListTile(
                value: _preferences.marketplaceInterestAlerts,
                onChanged: _loadingPreferences
                    ? null
                    : (value) => _savePreferences(
                        _preferences.copyWith(marketplaceInterestAlerts: value),
                      ),
                secondary: const Icon(Icons.storefront_rounded),
                title: Text(UiStrings.t('marketplace_interest_alerts')),
                subtitle: Text(
                  UiStrings.t('marketplace_interest_alerts_desc'),
                ),
              ),
              SwitchListTile(
                value: _preferences.scannerSoundFeedback,
                onChanged: _loadingPreferences
                    ? null
                    : (value) => _savePreferences(
                        _preferences.copyWith(scannerSoundFeedback: value),
                      ),
                secondary: const Icon(Icons.volume_up_outlined),
                title: Text(UiStrings.t('scanner_sound_feedback')),
                subtitle: Text(
                  UiStrings.t('scanner_sound_feedback_desc'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsPanel(
            title: 'Account',
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(UiStrings.t('open_fpc_profile')),
                subtitle: Text(account.email),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Get.offNamed('/fpo/profile'),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: Text(UiStrings.t('sign_out')),
                subtitle: Text(UiStrings.t('return_to_role_selection')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => AppLogoutFlow.run(
                  context,
                  onLogout: Get.find<MainAuthController>().logout,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FpcActivityScreen extends StatelessWidget {
  const FpcActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.activity,
      title: UiStrings.t('fpc_activity'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
        children: const [
          _FpcHeroPanel(
            icon: Icons.timeline_rounded,
            title: 'FPC operations',
            subtitle:
                'Daily work checklist for farmer service, grading and buying',
            trailing: 'Today',
          ),
          SizedBox(height: 16),
          _WorkflowPanel(
            title: 'Farmer service flow',
            steps: [
              'Scan verified farmer profile QR.',
              'Check farmer and farm details before procurement.',
              'Grade the grain lot or send it to review.',
              'Receive approved harvest QR into the FPC ledger.',
            ],
          ),
          SizedBox(height: 14),
          _WorkflowPanel(
            title: 'Marketplace flow',
            steps: [
              'Open buyer listings from the marketplace tab.',
              'Review crop, quantity, grade and village details.',
              'Mark buyer interest for lots the FPC wants to follow up.',
              'Use receiver after the final harvest QR is available.',
            ],
          ),
          SizedBox(height: 14),
          _WorkflowPanel(
            title: 'Review queue flow',
            steps: [
              'Open grading review for pending analysis jobs.',
              'Approve good lots, reject failed lots or request recapture.',
              'Keep notes clear so farmers know the next action.',
            ],
          ),
        ],
      ),
    );
  }
}

class FpcHelpScreen extends StatelessWidget {
  const FpcHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.support,
      title: UiStrings.t('fpc_help'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
        children: const [
          _FpcHeroPanel(
            icon: Icons.support_agent_rounded,
            title: 'FPC support',
            subtitle:
                'Operational help for profile QR, harvest QR and ledger sync',
            trailing: 'SOP',
          ),
          SizedBox(height: 16),
          _WorkflowPanel(
            title: 'If farmer QR does not scan',
            steps: [
              'Ask the farmer to open the verified profile QR from their app.',
              'Do not scan harvest QR in the farmer verification page.',
              'If the QR is old or incomplete, ask the farmer to regenerate it.',
            ],
          ),
          SizedBox(height: 14),
          _WorkflowPanel(
            title: 'If harvest receiving fails',
            steps: [
              'Use the Receiver tab, not the Farmer Verification tab.',
              'Scan only the final approved harvest trace QR.',
              'Check internet connection before saving the received lot.',
            ],
          ),
          SizedBox(height: 14),
          _WorkflowPanel(
            title: 'If FPC login fails',
            steps: [
              'Confirm the email was created from FPC signup.',
              'Confirm the account has FPC server role access.',
              'Ask admin to verify the FPC profile if access is blocked.',
            ],
          ),
        ],
      ),
    );
  }
}

class _FpcAccountSnapshot {
  final String userId;
  final String email;
  final String displayName;
  final String organization;
  final String phone;
  final String roleLabel;

  const _FpcAccountSnapshot({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.organization,
    required this.phone,
    required this.roleLabel,
  });

  String get organizationLabel => organization == UiStrings.t('not_added')
      ? UiStrings.t('fpc_workspace_label')
      : organization;

  static _FpcAccountSnapshot current() {
    final account = FpcAccountIdentity.current();
    return _FpcAccountSnapshot(
      userId: account.userId.isEmpty
          ? UiStrings.t('not_signed_in')
          : account.userId,
      email: account.email,
      displayName: account.displayName.isEmpty
          ? UiStrings.t('not_added')
          : account.displayName,
      organization: account.organizationName.isEmpty
          ? UiStrings.t('not_added')
          : account.organizationName,
      phone: account.phone.isEmpty ? UiStrings.t('not_added') : account.phone,
      roleLabel: account.roleLabel,
    );
  }
}

class _FpcHeroPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;

  const _FpcHeroPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppTheme.greenDark, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish(title),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  UiStrings.fromEnglish(subtitle),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                UiStrings.fromEnglish(trailing),
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: Material(
        color: Colors.transparent,
        child: Column(children: children),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.greenDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish(label),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String title;
  final String route;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.route,
  });
}

class _QuickActionGrid extends StatelessWidget {
  final List<_QuickAction> actions;

  const _QuickActionGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Get.offNamed(action.route),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Icon(action.icon, color: AppTheme.greenDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      UiStrings.fromEnglish(action.title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsPanel({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: Column(children: children),
    );
  }
}

class _WorkflowPanel extends StatelessWidget {
  final String title;
  final List<String> steps;

  const _WorkflowPanel({required this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.greenPale,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      LocaleText.number(i + 1),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      UiStrings.fromEnglish(steps[i]),
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UiStrings.fromEnglish(title),
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
