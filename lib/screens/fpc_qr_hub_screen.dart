import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpcQrHubScreen extends StatelessWidget {
  const FpcQrHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.qrHub,
      title: 'Scan QR',
      showQrAction: false,
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          key: const Key('fpc-qr-hub'),
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth >= 920 ? 28 : 16,
            16,
            constraints.maxWidth >= 920 ? 28 : 16,
            120,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _QrHubHeader(),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, cardConstraints) {
                        final wide = cardConstraints.maxWidth >= 720;
                        final farmer = _QrFlowCard(
                          key: const Key('farmer-profile-qr-flow'),
                          color: AppTheme.greenDark,
                          icon: Icons.person_search_rounded,
                          title: 'Farmer profile QR',
                          subtitle: 'Verify and link one farmer to this FPC.',
                          accepted: 'Verified original farmer profile QR',
                          result:
                              'Opens identity, farm, crop and selling history',
                          action: 'Scan farmer QR',
                          onTap: () => Get.toNamed('/fpo/scan-farmer'),
                        );
                        final harvest = _QrFlowCard(
                          key: const Key('harvest-lot-qr-flow'),
                          color: const Color(0xFFC56A00),
                          icon: Icons.inventory_2_rounded,
                          title: 'Harvest / lot QR',
                          subtitle:
                              'Receive an approved harvest lot into the FPC ledger.',
                          accepted: 'Original final harvest trace QR',
                          result:
                              'Validates the lot before quantity, price and receipt',
                          action: 'Scan harvest QR',
                          onTap: () => Get.toNamed('/fpo/receiver'),
                        );
                        if (!wide) {
                          return Column(
                            children: [
                              farmer,
                              const SizedBox(height: 14),
                              harvest,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: farmer),
                            const SizedBox(width: 14),
                            Expanded(child: harvest),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const _QrGuardrailCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrHubHeader extends StatelessWidget {
  const _QrHubHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.greenDark,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish('Choose the QR type first'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  UiStrings.fromEnglish(
                    'Farmer identity and harvest receiving are separate verified flows. Select the correct card before opening the camera.',
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.4,
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

class _QrFlowCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String accepted;
  final String result;
  final String action;
  final VoidCallback onTap;

  const _QrFlowCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accepted,
    required this.result,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  UiStrings.fromEnglish(title),
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            UiStrings.fromEnglish(subtitle),
            style: const TextStyle(color: AppTheme.textMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _QrFlowDetail(
            icon: Icons.verified_outlined,
            label: 'Accepted QR',
            value: accepted,
            color: color,
          ),
          const SizedBox(height: 10),
          _QrFlowDetail(
            icon: Icons.arrow_forward_rounded,
            label: 'After validation',
            value: result,
            color: color,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: color),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(UiStrings.fromEnglish(action)),
          ),
        ],
      ),
    );
  }
}

class _QrFlowDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _QrFlowDetail({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                UiStrings.fromEnglish(label),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                UiStrings.fromEnglish(value),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QrGuardrailCard extends StatelessWidget {
  const _QrGuardrailCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1D59B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFF9A6700)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              UiStrings.fromEnglish(
                'The app rejects a Farmer QR in the Harvest flow and rejects a Harvest QR in the Farmer flow. No record is saved until the selected QR type passes validation.',
              ),
              style: const TextStyle(
                color: Color(0xFF6D4B00),
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
