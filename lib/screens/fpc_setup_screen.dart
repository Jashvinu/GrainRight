import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/fpc_operating_models.dart';
import '../services/fpc_operating_service.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpcSetupScreen extends StatefulWidget {
  const FpcSetupScreen({super.key});

  @override
  State<FpcSetupScreen> createState() => _FpcSetupScreenState();
}

class _FpcSetupScreenState extends State<FpcSetupScreen> {
  final _service = FpcOperatingService();
  FpcSessionContext? _session;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final session = await _service.loadSessionContext();
      if (!mounted) return;
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.settings,
      title: 'First-login FPC setup',
      showBottomNav: false,
      showQrAction: false,
      allowSetupGate: false,
      actions: [
        IconButton(
          tooltip: UiStrings.fromEnglish('Refresh'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.error),
              const SizedBox(height: 10),
              Text(UiStrings.authError(_error), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(UiStrings.fromEnglish('Retry')),
              ),
            ],
          ),
        ),
      );
    }
    final session = _session;
    if (session == null) return const SizedBox.shrink();
    final readiness = session.readiness;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _SetupHero(session: session),
          const SizedBox(height: 14),
          _ProgressCard(readiness: readiness),
          const SizedBox(height: 14),
          for (final item in readiness.items)
            _SetupStepCard(
              item: item,
              onOpen: () => unawaited(_openSetupItem(item)),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: readiness.isComplete ? () => Get.offNamed('/fpo') : null,
            icon: const Icon(Icons.dashboard_rounded),
            label: Text(UiStrings.fromEnglish('Open FPC dashboard')),
          ),
        ],
      ),
    );
  }

  Future<void> _openSetupItem(FpcSetupItem item) async {
    if (item.key == 'seed_stock') {
      await Get.toNamed(item.route, arguments: const {'tab': 'programs'});
      if (mounted) unawaited(_load());
      return;
    }
    if (item.key == 'field_team') {
      await Get.toNamed(
        item.route,
        arguments: item.complete
            ? null
            : const {'open_action': 'create_field_officer'},
      );
      if (mounted) unawaited(_load());
      return;
    }
    if (item.key == 'collection_center') {
      await Get.toNamed(
        item.route,
        arguments: const {
          'module': 'collection_center',
          'return_to_setup': true,
        },
      );
      if (mounted) unawaited(_load());
      return;
    }
    await Get.toNamed(item.route);
    if (mounted) unawaited(_load());
  }
}

class _SetupHero extends StatelessWidget {
  final FpcSessionContext session;

  const _SetupHero({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppTheme.greenPale,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              UiStrings.fromEnglish(session.membership.fpcName),
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              UiStrings.fromEnglish(
                'Complete the required checks before daily FPC operations.',
              ),
              style: const TextStyle(
                color: AppTheme.textDark,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final FpcSetupReadiness readiness;

  const _ProgressCard({required this.readiness});

  @override
  Widget build(BuildContext context) {
    final progress = readiness.requiredCount == 0
        ? 1.0
        : readiness.completeRequiredCount / readiness.requiredCount;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    UiStrings.fromEnglish('Setup readiness'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${readiness.completeRequiredCount}/${readiness.requiredCount}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.clamp(0, 1)),
            if (!readiness.isComplete) ...[
              const SizedBox(height: 8),
              Text(
                UiStrings.fromEnglish(
                  '${readiness.requiredCount - readiness.completeRequiredCount} required step(s) remaining.',
                ),
                style: const TextStyle(color: AppTheme.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupStepCard extends StatelessWidget {
  final FpcSetupItem item;
  final VoidCallback onOpen;

  const _SetupStepCard({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final complete = item.complete;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        minVerticalPadding: 8,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: complete
              ? AppTheme.greenPale
              : const Color(0xFFFFF7ED),
          foregroundColor: complete ? AppTheme.greenDark : Colors.orange,
          child: Icon(
            complete ? Icons.check_rounded : Icons.priority_high_rounded,
          ),
        ),
        title: Text(
          UiStrings.fromEnglish(item.title),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(UiStrings.fromEnglish(item.description)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(
                UiStrings.fromEnglish(
                  item.required ? (complete ? 'Done' : 'Required') : 'Optional',
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}
