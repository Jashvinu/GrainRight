import 'package:flutter/material.dart';

import '../core/localization/locale_text.dart';
import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/farmer_delivery_timeline_item.dart';
import '../services/farmer_delivery_timeline_service.dart';

class FarmerDeliveryPage extends StatefulWidget {
  const FarmerDeliveryPage({super.key});

  @override
  State<FarmerDeliveryPage> createState() => _FarmerDeliveryPageState();
}

class _FarmerDeliveryPageState extends State<FarmerDeliveryPage> {
  final _service = FarmerDeliveryTimelineService();
  List<FarmerDeliveryTimelineItem> _items = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final items = await _service.loadForCurrentFarmer();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acknowledgeSeed(FarmerDeliveryTimelineItem item) async {
    try {
      await _service.acknowledgeSeed(item.acknowledgeSeedIssueId);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('farmer-delivery-timeline-page'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 116),
        children: [
          _DeliveryHeader(items: _items),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error.isNotEmpty)
            _DeliveryMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load delivery records',
              message: _error,
              actionLabel: 'Retry',
              onAction: _load,
            )
          else if (_items.isEmpty)
            const _DeliveryMessage(
              icon: Icons.local_shipping_outlined,
              title: 'No delivery records yet',
              message:
                  'Seed delivery, procurement delivery and payment updates will appear here after your FPC records them.',
            )
          else
            for (final group in _groups(_items)) ...[
              _GroupTitle(title: group.title, count: group.items.length),
              const SizedBox(height: 8),
              for (final item in group.items)
                _DeliveryTimelineCard(
                  item: item,
                  onAcknowledge: item.needsSeedAcknowledgement
                      ? () => _acknowledgeSeed(item)
                      : null,
                ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _DeliveryHeader extends StatelessWidget {
  final List<FarmerDeliveryTimelineItem> items;

  const _DeliveryHeader({required this.items});

  @override
  Widget build(BuildContext context) {
    final openPayments = items
        .where(
          (item) =>
              item.type == 'farmer_payment' &&
              !{'paid', 'reversed'}.contains(item.status),
        )
        .length;
    final pendingAck = items
        .where((item) => item.needsSeedAcknowledgement)
        .length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.greenDark,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UiStrings.fromEnglish('Delivery'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            UiStrings.fromEnglish(
              'Seed, procurement and payment updates from your FPC.',
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(label: 'Records', value: '${items.length}'),
              _MetricPill(label: 'Open payments', value: '$openPayments'),
              _MetricPill(label: 'To acknowledge', value: '$pendingAck'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryTimelineCard extends StatelessWidget {
  final FarmerDeliveryTimelineItem item;
  final VoidCallback? onAcknowledge;

  const _DeliveryTimelineCard({required this.item, this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDDE8D4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(item.type), color: AppTheme.greenDark),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    UiStrings.fromEnglish(item.typeLabel),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusChip(label: item.statusLabel),
              ],
            ),
            const SizedBox(height: 8),
            _DetailLine(icon: Icons.account_tree_outlined, text: item.fpcName),
            if (item.quantityKg != null)
              _DetailLine(
                icon: Icons.scale_outlined,
                text: '${_formatNumber(item.quantityKg!)} kg',
              ),
            if (item.amount != null)
              _DetailLine(
                icon: Icons.payments_outlined,
                text: '${item.currency} ${_formatNumber(item.amount!)}',
              ),
            if (item.hasPaymentStatus)
              _DetailLine(
                icon: Icons.account_balance_wallet_outlined,
                text: item.paymentStatusLabel,
              ),
            if (item.occurredAt != null)
              _DetailLine(
                icon: Icons.event_outlined,
                text:
                    '${LocaleText.date(item.occurredAt!.toLocal())} '
                    '${LocaleText.time(item.occurredAt!.toLocal())}',
              ),
            if (item.farmId.isNotEmpty)
              _DetailLine(icon: Icons.agriculture_outlined, text: item.farmId),
            if (item.hasEvidence)
              _DetailLine(
                icon: Icons.verified_outlined,
                text: UiStrings.fromEnglish('Evidence recorded'),
              ),
            if (onAcknowledge != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAcknowledge,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(UiStrings.fromEnglish('Confirm seed receipt')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
    'seed_request' => Icons.spa_outlined,
    'seed_delivery' => Icons.local_shipping_outlined,
    'procurement_delivery' => Icons.assignment_turned_in_outlined,
    'procurement_lot' => Icons.inventory_2_outlined,
    'farmer_payment' => Icons.payments_outlined,
    'buyer_dispatch' => Icons.fire_truck_outlined,
    _ => Icons.timeline_rounded,
  };
}

class _DeliveryMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _DeliveryMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.greenDark, size: 42),
          const SizedBox(height: 10),
          Text(
            UiStrings.fromEnglish(title),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            UiStrings.fromEnglish(message),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, height: 1.35),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onAction,
              child: Text(UiStrings.fromEnglish(actionLabel!)),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String title;
  final int count;

  const _GroupTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            UiStrings.fromEnglish(title),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        _StatusChip(label: '$count'),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Text(
          '${UiStrings.fromEnglish(label)}: $value',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(UiStrings.fromEnglish(label)),
      backgroundColor: AppTheme.greenPale,
      labelStyle: const TextStyle(
        color: AppTheme.greenDark,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final value = text.trim();
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              UiStrings.fromEnglish(value),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryGroup {
  final String title;
  final List<FarmerDeliveryTimelineItem> items;

  const _DeliveryGroup(this.title, this.items);
}

List<_DeliveryGroup> _groups(List<FarmerDeliveryTimelineItem> items) {
  final seeds = items
      .where((item) => {'seed_request', 'seed_delivery'}.contains(item.type))
      .toList(growable: false);
  final procurement = items
      .where(
        (item) =>
            {'procurement_delivery', 'procurement_lot'}.contains(item.type),
      )
      .toList(growable: false);
  final payments = items
      .where((item) => item.type == 'farmer_payment')
      .toList(growable: false);
  final dispatches = items
      .where((item) => item.type == 'buyer_dispatch')
      .toList(growable: false);
  return [
    if (seeds.isNotEmpty) _DeliveryGroup('Seeds', seeds),
    if (procurement.isNotEmpty) _DeliveryGroup('Procurement', procurement),
    if (payments.isNotEmpty) _DeliveryGroup('Payments', payments),
    if (dispatches.isNotEmpty) _DeliveryGroup('Sales dispatch', dispatches),
  ];
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
