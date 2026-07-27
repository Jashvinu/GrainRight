import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/fpc_farmer_profile.dart';
import '../services/fpc_operating_service.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpcFarmerDirectoryScreen extends StatefulWidget {
  const FpcFarmerDirectoryScreen({super.key});

  @override
  State<FpcFarmerDirectoryScreen> createState() =>
      _FpcFarmerDirectoryScreenState();
}

class _FpcFarmerDirectoryScreenState extends State<FpcFarmerDirectoryScreen> {
  final _service = FpcOperatingService();
  final _searchController = TextEditingController();
  List<FpcFarmerProfile> _farmers = const [];
  String _status = 'all';
  String _error = '';
  bool _loading = true;
  bool _openedInitialProfile = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final farmers = await _service.loadFarmerDirectory();
      if (!mounted) return;
      setState(() => _farmers = farmers);
      _openRequestedProfile(farmers);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openRequestedProfile(List<FpcFarmerProfile> farmers) {
    if (_openedInitialProfile) return;
    final arguments = Get.arguments;
    if (arguments is! Map) return;
    final farmerId = '${arguments['farmerId'] ?? ''}'.trim();
    if (farmerId.isEmpty) return;
    _openedInitialProfile = true;
    FpcFarmerProfile? requested;
    for (final farmer in farmers) {
      if (farmer.farmerId == farmerId) {
        requested = farmer;
        break;
      }
    }
    final selected = requested;
    if (selected == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showProfile(selected);
    });
  }

  List<FpcFarmerProfile> get _visibleFarmers {
    final query = _searchController.text.trim().toLowerCase();
    return _farmers
        .where((farmer) {
          final matchesStatus = switch (_status) {
            'active' => farmer.isActive,
            'inactive' => !farmer.isActive,
            _ => true,
          };
          return matchesStatus &&
              (query.isEmpty || farmer.searchText.contains(query));
        })
        .toList(growable: false);
  }

  void _showProfile(FpcFarmerProfile farmer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FarmerProfileSheet(farmer: farmer),
    );
  }

  @override
  Widget build(BuildContext context) {
    final farmers = _visibleFarmers;
    return FpcWorkspaceScaffold(
      current: FpcNavTab.farmerScan,
      title: 'Farmers',
      actions: [
        IconButton(
          tooltip: UiStrings.fromEnglish('Refresh farmers'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            key: const Key('fpc-farmer-directory'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth >= 920 ? 28 : 16,
              16,
              constraints.maxWidth >= 920 ? 28 : 16,
              120,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DirectoryHeader(
                        total: _farmers.length,
                        active: _farmers.where((item) => item.isActive).length,
                      ),
                      const SizedBox(height: 14),
                      _SearchAndFilter(
                        controller: _searchController,
                        status: _status,
                        onSearch: (_) => setState(() {}),
                        onStatus: (value) => setState(() => _status = value),
                      ),
                      const SizedBox(height: 14),
                      if (_loading)
                        const _DirectoryLoading()
                      else if (_error.isNotEmpty)
                        _DirectoryMessage(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load farmer records',
                          message: _error,
                          actionLabel: 'Retry',
                          onAction: _load,
                        )
                      else if (farmers.isEmpty)
                        _DirectoryMessage(
                          icon: _farmers.isEmpty
                              ? Icons.group_add_outlined
                              : Icons.search_off_rounded,
                          title: _farmers.isEmpty
                              ? 'No linked farmers yet'
                              : 'No farmers match this search',
                          message: _farmers.isEmpty
                              ? 'Scan a verified farmer profile QR to add the first farmer.'
                              : 'Try a name, phone, village, farm, crop, or farmer ID.',
                          actionLabel: _farmers.isEmpty ? 'Scan farmer' : null,
                          onAction: _farmers.isEmpty
                              ? () => Get.toNamed('/fpo/qr')
                              : null,
                        )
                      else
                        _FarmerGrid(farmers: farmers, onOpen: _showProfile),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryHeader extends StatelessWidget {
  final int total;
  final int active;

  const _DirectoryHeader({required this.total, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.greenDark,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 16,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish('Farmer directory'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$total linked farmers • $active active',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  UiStrings.fromEnglish(
                    'Open one profile to review verified identity, farm, crop, production and selling history.',
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.35,
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

class _SearchAndFilter extends StatelessWidget {
  final TextEditingController controller;
  final String status;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onStatus;

  const _SearchAndFilter({
    required this.controller,
    required this.status,
    required this.onSearch,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            onChanged: onSearch,
            decoration: InputDecoration(
              labelText: UiStrings.fromEnglish('Search farmers'),
              hintText: UiStrings.fromEnglish(
                'Name, phone, village, crop or farmer ID',
              ),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: UiStrings.fromEnglish('Clear search'),
                      onPressed: () {
                        controller.clear();
                        onSearch('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                for (final option in const [
                  ('all', 'All'),
                  ('active', 'Active'),
                  ('inactive', 'Inactive'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: status == option.$1,
                    onSelected: (_) => onStatus(option.$1),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmerGrid extends StatelessWidget {
  final List<FpcFarmerProfile> farmers;
  final ValueChanged<FpcFarmerProfile> onOpen;

  const _FarmerGrid({required this.farmers, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final farmer in farmers)
              SizedBox(
                width: width,
                child: _FarmerCard(farmer: farmer, onTap: () => onOpen(farmer)),
              ),
          ],
        );
      },
    );
  }
}

class _FarmerCard extends StatelessWidget {
  final FpcFarmerProfile farmer;
  final VoidCallback onTap;

  const _FarmerCard({required this.farmer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDDE8D4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: AppTheme.greenPale,
                    child: Text(
                      _initials(farmer.name),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _value(farmer.name, 'Farmer'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _value(farmer.farmerId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(active: farmer.isActive),
                ],
              ),
              const SizedBox(height: 14),
              _InlineDetail(icon: Icons.phone_outlined, text: farmer.phone),
              _InlineDetail(
                icon: Icons.location_on_outlined,
                text: farmer.village,
              ),
              _InlineDetail(
                icon: Icons.agriculture_outlined,
                text: [
                  farmer.crop,
                  farmer.variety,
                ].where((item) => item.isNotEmpty).join(' • '),
              ),
              _InlineDetail(
                icon: Icons.landscape_outlined,
                text: farmer.primaryFarm,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    farmer.isVerified
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: farmer.isVerified
                        ? AppTheme.green
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      farmer.isVerified
                          ? 'Verified farmer profile'
                          : _value(farmer.kycStatus, 'KYC not recorded'),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FarmerProfileSheet extends StatelessWidget {
  final FpcFarmerProfile farmer;

  const _FarmerProfileSheet({required this.farmer});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, controller) => Material(
        key: const Key('fpc-farmer-profile-sheet'),
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 5,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: AppTheme.greenPale,
                        child: Icon(
                          Icons.person_rounded,
                          color: AppTheme.greenDark,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _value(farmer.name, 'Farmer'),
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _value(farmer.farmerId),
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: UiStrings.fromEnglish('Close'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ProfileTag(
                        icon: Icons.verified_rounded,
                        text: _value(farmer.kycStatus, 'Not recorded'),
                      ),
                      _ProfileTag(
                        icon: Icons.link_rounded,
                        text: farmer.isActive ? 'Active link' : 'Inactive link',
                      ),
                      if (farmer.fpcRating.isNotEmpty)
                        _ProfileTag(
                          icon: Icons.star_rounded,
                          text: 'Rating ${farmer.fpcRating}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ProfileSection(
                    title: 'Verified farmer details',
                    icon: Icons.badge_outlined,
                    rows: [
                      ('Phone', farmer.phone),
                      ('Village', farmer.village),
                      ('Farmer ID', farmer.farmerId),
                      ('Masked identity', farmer.maskedIdentity),
                      ('Profile detail', farmer.detail),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ProfileSection(
                    title: 'Farm and current crop',
                    icon: Icons.agriculture_outlined,
                    rows: [
                      ('Primary farm', farmer.primaryFarm),
                      ('Farm ID', farmer.farmId),
                      ('Area', farmer.area),
                      ('Crop', farmer.crop),
                      ('Variety', farmer.variety),
                      ('Season', farmer.season),
                      ('Expected yield', farmer.expectedYield),
                      ('Current grade', farmer.currentGrade),
                      ('Crop detail', farmer.currentCropDetail),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HistorySection(
                    title: 'Past crop production',
                    icon: Icons.history_rounded,
                    emptyText:
                        'No past production was included in the farmer QR.',
                    rows: farmer.productionHistory,
                    fields: const [
                      ('Season', 'season'),
                      ('Crop', 'crop'),
                      ('Yield', 'yield'),
                      ('Grade', 'grade'),
                      ('Detail', 'detail'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HistorySection(
                    title: 'Selling history',
                    icon: Icons.receipt_long_outlined,
                    emptyText:
                        'No selling history was included in the farmer QR.',
                    rows: farmer.sellingHistory,
                    fields: const [
                      ('Date', 'date'),
                      ('Buyer', 'buyer'),
                      ('Quantity', 'quantity'),
                      ('Rate', 'rate'),
                      ('Rating', 'rating'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ProfileSection(
                    title: 'FPC record',
                    icon: Icons.account_tree_outlined,
                    rows: [
                      ('Linked on', _formatDate(farmer.linkedAt)),
                      ('Last updated', _formatDate(farmer.updatedAt)),
                      ('Link status', farmer.linkStatus),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Get.toNamed(
                        '/fpo/grain-grading',
                        arguments: farmer.gradingArguments,
                      );
                    },
                    icon: const Icon(Icons.grain_rounded),
                    label: Text(
                      UiStrings.fromEnglish('Grade this farmer’s lot'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  const _ProfileSection({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((row) => row.$2.trim().isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.greenDark),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Text(
              UiStrings.fromEnglish('No details recorded.'),
              style: const TextStyle(color: AppTheme.textMuted),
            )
          else
            for (final row in visible)
              _ProfileRow(label: row.$1, value: row.$2),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String emptyText;
  final List<Map<String, dynamic>> rows;
  final List<(String, String)> fields;

  const _HistorySection({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.rows,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.greenDark),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(emptyText, style: const TextStyle(color: AppTheme.textMuted))
          else
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const Divider(height: 22),
              for (final field in fields)
                if (_mapText(rows[index], field.$2).isNotEmpty)
                  _ProfileRow(
                    label: field.$1,
                    value: _mapText(rows[index], field.$2),
                  ),
            ],
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ProfileTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppTheme.greenDark),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineDetail extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineDetail({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;

  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE7F7EE) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: TextStyle(
          color: active ? const Color(0xFF087F5B) : AppTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DirectoryLoading extends StatelessWidget {
  const _DirectoryLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(42),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _DirectoryMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _DirectoryMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppTheme.greenDark),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, height: 1.4),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

String _value(String value, [String fallback = 'Not recorded']) =>
    value.trim().isEmpty ? fallback : value.trim();

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  return parts.isEmpty
      ? 'F'
      : parts.map((part) => part[0]).join().toUpperCase();
}

String _mapText(Map<String, dynamic> row, String key) {
  final value = row[key];
  return value == null ? '' : '$value'.trim();
}

String _formatDate(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}
