import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../controllers/language_controller.dart';
import '../models/farmer_inventory_item.dart';
import '../models/marketplace_listing.dart';
import '../services/marketplace_listing_service.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import 'package:kalsubai_farms/core/widgets/brand_text.dart';
import '../widgets/farmer_floating_bottom_nav.dart';
import '../widgets/fpc_bottom_nav.dart';
import 'package:kalsubai_farms/core/widgets/language_selector_button.dart';

class MarketplacePage extends StatefulWidget {
  final List<Map<String, String>> inventoryLots;
  final String? farmName;
  final Map<String, String>? initialSelectedLot;
  final bool buyerMode;
  final ValueChanged<FarmerBottomNavItem>? onBottomNavSelected;

  const MarketplacePage({
    super.key,
    required this.inventoryLots,
    this.farmName,
    this.initialSelectedLot,
    this.buyerMode = false,
    this.onBottomNavSelected,
  });

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  static const _allCrops = 'All crops';

  final _listingService = MarketplaceListingService();

  List<_ApmcRate> _remoteRates = const [];
  bool _isLoadingRates = false;
  List<MarketplaceListing> _farmerListings = const [];
  List<MarketplaceListing> _fpcListings = const [];
  bool _isLoadingListings = false;
  String _savingInventoryItemId = '';
  String _savingInterestListingId = '';

  List<_ApmcRate> get _fallbackRates => [
    _ApmcRate(
      marketKey: 'apmc_market_name_akole',
      crop: 'Finger Millet',
      minRate: 2760,
      modalRate: 3040,
      maxRate: 3310,
      arrivalQty: 42,
      demand: 'High',
      trend: 4.8,
      distanceKm: 18,
      updatedAt: DateTime.utc(2026, 6, 17, 8, 40),
      note: UiStrings.t('apmc_note_clean_lots'),
    ),
    _ApmcRate(
      marketKey: 'apmc_market_name_sangamner',
      crop: 'Foxtail Millet',
      minRate: 2480,
      modalRate: 2790,
      maxRate: 3060,
      arrivalQty: 31,
      demand: 'Good',
      trend: 2.6,
      distanceKm: 44,
      updatedAt: DateTime.utc(2026, 6, 17, 8, 20),
      note: UiStrings.t('apmc_note_dry_lots'),
    ),
    _ApmcRate(
      marketKey: 'apmc_market_name_nashik',
      crop: 'Little Millet',
      minRate: 2920,
      modalRate: 3180,
      maxRate: 3460,
      arrivalQty: 26,
      demand: 'High',
      trend: 5.2,
      distanceKm: 92,
      updatedAt: DateTime.utc(2026, 6, 17, 9, 5),
      note: UiStrings.t('apmc_note_sorted_grain'),
    ),
    _ApmcRate(
      marketKey: 'apmc_market_name_pune',
      crop: 'Kodo Millet',
      minRate: 2650,
      modalRate: 2915,
      maxRate: 3200,
      arrivalQty: 54,
      demand: 'Stable',
      trend: -1.4,
      distanceKm: 166,
      updatedAt: DateTime.utc(2026, 6, 17, 8, 55),
      note: UiStrings.t('apmc_note_high_arrival'),
    ),
    _ApmcRate(
      marketKey: 'apmc_market_name_rahuri',
      crop: 'Pearl Millet',
      minRate: 2180,
      modalRate: 2390,
      maxRate: 2575,
      arrivalQty: 68,
      demand: 'Stable',
      trend: 1.1,
      distanceKm: 71,
      updatedAt: DateTime.utc(2026, 6, 17, 8, 10),
      note: UiStrings.t('apmc_note_bulk_buyers'),
    ),
  ];

  List<_ApmcRate> get _rates =>
      _remoteRates.isEmpty ? _fallbackRates : _remoteRates;

  String _selectedCrop = _allCrops;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRemoteRates());
    unawaited(_loadMarketplaceListings());
  }

  Future<void> _loadRemoteRates() async {
    if (_isLoadingRates) return;
    setState(() {
      _isLoadingRates = true;
    });
    try {
      final rows = await Supabase.instance.client
          .from('apmc_market_rates')
          .select(
            'market_key, market_name, crop, min_rate, modal_rate, max_rate, arrival_qty, demand, trend, distance_km, note, updated_at, active',
          )
          .eq('active', true)
          .order('updated_at', ascending: false)
          .limit(80)
          .timeout(const Duration(seconds: 4));
      final rates = (rows as List)
          .whereType<Map>()
          .map((row) => _ApmcRate.fromRemote(Map<String, dynamic>.from(row)))
          .where((rate) => rate.crop.trim().isNotEmpty && rate.modalRate > 0)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _remoteRates = rates;
      });
    } catch (_) {
      // Keep local fallback rates when the remote market table is unavailable.
    } finally {
      if (mounted) {
        setState(() => _isLoadingRates = false);
      }
    }
  }

  Future<void> _loadMarketplaceListings() async {
    if (_isLoadingListings) return;
    setState(() => _isLoadingListings = true);
    try {
      final listings = widget.buyerMode
          ? await _listingService.listFpcListings()
          : await _listingService.listFarmerListings();
      if (!mounted) return;
      setState(() {
        if (widget.buyerMode) {
          _fpcListings = listings;
        } else {
          _farmerListings = listings;
        }
      });
    } catch (_) {
      // Marketplace still shows local inventory and APMC rates if listing sync fails.
    } finally {
      if (mounted) setState(() => _isLoadingListings = false);
    }
  }

  Future<void> _listLotForSale(Map<String, String> lot) async {
    final remoteId = (lot['remoteId'] ?? '').trim();
    final inventoryId = (lot['itemId'] ?? '').trim();
    if (remoteId.isEmpty) {
      Get.snackbar(
        UiStrings.t('apmc_market'),
        UiStrings.t('sync_inventory_first_market'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    if (_savingInventoryItemId == remoteId) return;
    setState(() => _savingInventoryItemId = remoteId);
    try {
      final listing = await _listingService.createOrUpdateFromInventory(
        inventoryItemId: remoteId,
        inventoryId: inventoryId,
      );
      if (!mounted) return;
      setState(() {
        final next = _farmerListings.toList(growable: true);
        final index = next.indexWhere((item) => item.id == listing.id);
        if (index >= 0) {
          next[index] = listing;
        } else {
          next.insert(0, listing);
        }
        _farmerListings = next;
      });
      Get.snackbar(
        UiStrings.t('apmc_market'),
        UiStrings.t('listing_created_for_fpc'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      Get.snackbar(
        UiStrings.t('apmc_market'),
        UiStrings.t('listing_failed'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingInventoryItemId = '');
    }
  }

  Future<void> _markInterest(MarketplaceListing listing) async {
    if (_savingInterestListingId == listing.id || listing.interestedByMe) {
      return;
    }
    setState(() => _savingInterestListingId = listing.id);
    try {
      await _listingService.markInterest(listingId: listing.id);
      if (!mounted) return;
      await _loadMarketplaceListings();
      Get.snackbar(
        UiStrings.t('apmc_market'),
        UiStrings.t('buyer_interest_saved'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      Get.snackbar(
        UiStrings.t('apmc_market'),
        UiStrings.t('buyer_interest_failed'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingInterestListingId = '');
    }
  }

  List<String> get _cropOptions {
    final crops = <String>{_allCrops};
    crops.addAll(_rates.map((rate) => rate.crop));
    for (final lot in widget.inventoryLots) {
      final crop = lot['crop']?.trim();
      if (crop != null && crop.isNotEmpty) crops.add(crop);
    }
    crops.addAll(
      _farmerListings
          .map((listing) => listing.crop.trim())
          .where((crop) => crop.isNotEmpty),
    );
    crops.addAll(
      _fpcListings
          .map((listing) => listing.crop.trim())
          .where((crop) => crop.isNotEmpty),
    );
    return crops.toList(growable: false);
  }

  List<_ApmcRate> get _visibleRates {
    if (_selectedCrop == _allCrops) return _rates;
    return _rates
        .where((rate) => rate.crop.toLowerCase() == _selectedCrop.toLowerCase())
        .toList(growable: false);
  }

  List<Map<String, String>> get _visibleLots {
    final lots = _selectedCrop == _allCrops
        ? widget.inventoryLots
        : widget.inventoryLots
              .where(
                (lot) =>
                    (lot['crop'] ?? '').toLowerCase() ==
                    _selectedCrop.toLowerCase(),
              )
              .toList(growable: false);
    final selectedKey = _lotKey(widget.initialSelectedLot);
    if (selectedKey.isEmpty) return lots;
    final sorted = lots.toList(growable: false)
      ..sort((a, b) {
        final aSelected = _lotKey(a) == selectedKey;
        final bSelected = _lotKey(b) == selectedKey;
        if (aSelected == bSelected) return 0;
        return aSelected ? -1 : 1;
      });
    return sorted;
  }

  List<MarketplaceListing> get _visibleBuyerListings {
    if (_selectedCrop == _allCrops) return _fpcListings;
    return _fpcListings
        .where(
          (listing) =>
              listing.crop.toLowerCase() == _selectedCrop.toLowerCase(),
        )
        .toList(growable: false);
  }

  List<MarketplaceListing> get _visibleFarmerListings {
    if (_selectedCrop == _allCrops) return _farmerListings;
    return _farmerListings
        .where(
          (listing) =>
              listing.crop.toLowerCase() == _selectedCrop.toLowerCase(),
        )
        .toList(growable: false);
  }

  double _toDouble(String? value) => double.tryParse(value ?? '') ?? 0;

  int _toInt(String? value) => int.tryParse(value ?? '') ?? 0;

  String _lotKey(Map<String, String>? lot) {
    if (lot == null) return '';
    final remoteId = (lot['remoteId'] ?? '').trim();
    if (remoteId.isNotEmpty) return 'remote:$remoteId';
    final itemId = (lot['itemId'] ?? '').trim();
    if (itemId.isNotEmpty) return 'item:$itemId';
    return (lot['batchId'] ?? '').trim();
  }

  MarketplaceListing? _listingForLot(Map<String, String> lot) {
    final remoteId = (lot['remoteId'] ?? '').trim();
    final batchId = (lot['batchId'] ?? '').trim();
    for (final listing in _farmerListings) {
      if (remoteId.isNotEmpty && listing.inventoryItemId == remoteId) {
        return listing;
      }
      if (remoteId.isEmpty &&
          batchId.isNotEmpty &&
          listing.batchId == batchId) {
        return listing;
      }
    }
    return null;
  }

  String _categoryTitle(String category) {
    return switch (category) {
      FarmerInventoryProductCategory.byproduct => UiStrings.t(
        'inventory_section_byproducts',
      ),
      FarmerInventoryProductCategory.processedProduct => UiStrings.t(
        'inventory_section_made_products',
      ),
      _ => UiStrings.t('inventory_section_harvest_lots'),
    };
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      FarmerInventoryProductCategory.byproduct => Icons.eco_rounded,
      FarmerInventoryProductCategory.processedProduct =>
        Icons.shopping_bag_rounded,
      _ => Icons.inventory_2_rounded,
    };
  }

  int get _bestRate {
    final rates = _visibleRates.isEmpty ? _rates : _visibleRates;
    return rates.map((rate) => rate.modalRate).reduce((a, b) => a > b ? a : b);
  }

  void _handleBottomNav(FarmerBottomNavItem item) {
    if (item == FarmerBottomNavItem.marketplace) return;
    if (widget.onBottomNavSelected != null) {
      widget.onBottomNavSelected!(item);
      return;
    }
    Get.offAllNamed('/farmer', arguments: {'farmerTab': item.name});
  }

  Widget _buildLanguageSelector({bool compact = false}) {
    if (!Get.isRegistered<LanguageController>()) {
      return const SizedBox.shrink();
    }
    final languageCtrl = Get.find<LanguageController>();
    return Obx(
      () => LanguageSelectorButton(
        code: languageCtrl.language.value,
        compact: compact,
        onChanged: languageCtrl.setLanguage,
      ),
    );
  }

  List<Widget> _buildRateSection(List<_ApmcRate> rates) {
    return [
      _SectionHeader(
        icon: Icons.query_stats_rounded,
        title: UiStrings.t('today_mandi_rates'),
        actionLabel: UiStrings.f('markets_count', {'count': rates.length}),
      ),
      const SizedBox(height: 10),
      if (rates.isEmpty)
        _EmptyApmcPanel(
          title: UiStrings.t('no_mandi_rate_found'),
          message: UiStrings.t('try_all_crops_market_sync'),
        )
      else
        ...rates.map(
          (rate) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ApmcRateCard(rate: rate),
          ),
        ),
    ];
  }

  List<Widget> _buildSellableProductSections(List<Map<String, String>> lots) {
    final widgets = <Widget>[
      _SectionHeader(
        icon: Icons.storefront_rounded,
        title: UiStrings.t('my_sellable_products'),
        actionLabel: UiStrings.f('lots_count', {'count': lots.length}),
      ),
      const SizedBox(height: 10),
    ];
    if (lots.isEmpty) {
      widgets.add(
        _EmptyApmcPanel(
          title: UiStrings.t('no_sellable_products'),
          message: UiStrings.t('graded_lot_empty_message'),
        ),
      );
      return widgets;
    }

    const categories = [
      FarmerInventoryProductCategory.cropLot,
      FarmerInventoryProductCategory.byproduct,
      FarmerInventoryProductCategory.processedProduct,
    ];
    for (final category in categories) {
      final categoryLots = lots
          .where(
            (lot) =>
                (lot['productCategory'] ??
                    FarmerInventoryProductCategory.cropLot) ==
                category,
          )
          .toList(growable: false);
      if (categoryLots.isEmpty) continue;
      widgets.add(
        _ApmcCategoryHeader(
          icon: _categoryIcon(category),
          title: _categoryTitle(category),
          count: categoryLots.length,
        ),
      );
      widgets.add(const SizedBox(height: 8));
      widgets.addAll(
        categoryLots.map((lot) {
          final listing = _listingForLot(lot);
          final remoteId = (lot['remoteId'] ?? '').trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ApmcLotReadinessCard(
              lot: lot,
              modalRate: _bestRate,
              toDouble: _toDouble,
              toInt: _toInt,
              isListed: listing?.isActive == true,
              isSavingListing:
                  remoteId.isNotEmpty && _savingInventoryItemId == remoteId,
              onListForSale: () => _listLotForSale(lot),
            ),
          );
        }),
      );
      widgets.add(const SizedBox(height: 2));
    }
    return widgets;
  }

  List<Widget> _buildFarmerListingSection(List<MarketplaceListing> listings) {
    return [
      _SectionHeader(
        icon: Icons.handshake_rounded,
        title: UiStrings.t('active_fpc_listings'),
        actionLabel: UiStrings.f('listings_count', {'count': listings.length}),
      ),
      const SizedBox(height: 10),
      if (_isLoadingListings)
        _LoadingApmcPanel(label: UiStrings.t('marketplace_syncing'))
      else if (listings.isEmpty)
        _EmptyApmcPanel(
          title: UiStrings.t('no_active_fpc_listings'),
          message: UiStrings.t('list_products_for_fpc_message'),
        )
      else
        ...listings
            .take(6)
            .map(
              (listing) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MarketplaceListingCard(listing: listing),
              ),
            ),
    ];
  }

  List<Widget> _buildBuyerListingSection(List<MarketplaceListing> listings) {
    return [
      _SectionHeader(
        icon: Icons.shopping_cart_checkout_rounded,
        title: UiStrings.t('buy_from_farmers'),
        actionLabel: UiStrings.f('listings_count', {'count': listings.length}),
      ),
      const SizedBox(height: 10),
      if (_isLoadingListings)
        _LoadingApmcPanel(label: UiStrings.t('marketplace_syncing'))
      else if (listings.isEmpty)
        _EmptyApmcPanel(
          title: UiStrings.t('no_farmer_listing_found'),
          message: UiStrings.t('no_farmer_listing_message'),
        )
      else
        ...listings.map(
          (listing) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MarketplaceListingCard(
              listing: listing,
              buyerMode: true,
              isSavingInterest: _savingInterestListingId == listing.id,
              onMarkInterest: () => _markInterest(listing),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    Widget content() {
      final rates = _visibleRates;
      final lots = _visibleLots;
      final farmerListings = _visibleFarmerListings;
      final buyerListings = _visibleBuyerListings;
      final marketActions = <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(child: _buildLanguageSelector(compact: true)),
        ),
      ];
      final marketBody = SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  10,
                  18,
                  widget.buyerMode ? 28 : 150,
                ),
                children: [
                  _CropFilterBar(
                    crops: _cropOptions,
                    selected: _selectedCrop,
                    onSelected: (crop) => setState(() => _selectedCrop = crop),
                  ),
                  const SizedBox(height: 14),
                  _ApmcSaleWindowCard(
                    selectedCrop: _selectedCrop,
                    modalRate: _bestRate,
                  ),
                  const SizedBox(height: 14),
                  if (widget.buyerMode) ...[
                    ..._buildBuyerListingSection(buyerListings),
                    const SizedBox(height: 6),
                    ..._buildRateSection(rates),
                  ] else ...[
                    ..._buildRateSection(rates),
                    const SizedBox(height: 6),
                    ..._buildSellableProductSections(lots),
                    const SizedBox(height: 6),
                    ..._buildFarmerListingSection(farmerListings),
                  ],
                  const SizedBox(height: 6),
                  _SectionHeader(
                    icon: Icons.place_rounded,
                    title: UiStrings.t('nearby_market_choices'),
                    actionLabel: UiStrings.t('route_plan'),
                  ),
                  const SizedBox(height: 10),
                  _NearbyMarketPanel(),
                  const SizedBox(height: 14),
                  _ApmcChecklistPanel(),
                ],
              ),
            ),
            if (!widget.buyerMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: FarmerFloatingBottomNav(
                    selectedItem: FarmerBottomNavItem.marketplace,
                    onSelected: _handleBottomNav,
                  ),
                ),
              ),
          ],
        ),
      );

      if (widget.buyerMode) {
        return FpcWorkspaceScaffold(
          current: FpcNavTab.marketplace,
          title: UiStrings.t('apmc_market'),
          actions: marketActions,
          body: marketBody,
        );
      }

      return Scaffold(
        extendBody: true,
        backgroundColor: AppTheme.surface,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          elevation: 0,
          toolbarHeight: appHeaderToolbarHeight,
          centerTitle: true,
          iconTheme: const IconThemeData(color: AppTheme.greenDark),
          leadingWidth: appBackButtonLeadingWidth,
          leading: appBackButtonLeading(context),
          title: const BrandText(fontSize: 21),
          actions: marketActions,
        ),
        body: marketBody,
      );
    }

    if (!Get.isRegistered<LanguageController>()) return content();
    final language = Get.find<LanguageController>();
    return Obx(() {
      language.language.value;
      return content();
    });
  }
}

class _CropFilterBar extends StatelessWidget {
  final List<String> crops;
  final String selected;
  final ValueChanged<String> onSelected;

  const _CropFilterBar({
    required this.crops,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: crops.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final crop = crops[index];
          final isSelected = crop == selected;
          return ChoiceChip(
            label: Text(UiStrings.option(crop)),
            selected: isSelected,
            onSelected: (_) => onSelected(crop),
            selectedColor: AppTheme.greenPale,
            labelStyle: TextStyle(
              color: isSelected ? AppTheme.greenDark : AppTheme.textDark,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: isSelected ? AppTheme.green : const Color(0xFFE1E8DD),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ApmcSaleWindowCard extends StatelessWidget {
  final String selectedCrop;
  final int modalRate;

  const _ApmcSaleWindowCard({
    required this.selectedCrop,
    required this.modalRate,
  });

  @override
  Widget build(BuildContext context) {
    final cropLabel = selectedCrop == _MarketplacePageState._allCrops
        ? UiStrings.t('millet_lots')
        : UiStrings.option(selectedCrop);
    return _ApmcPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E0),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.schedule_rounded, color: AppTheme.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    UiStrings.t('best_sale_window'),
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    UiStrings.f('apmc_sale_window_body', {
                      'crop': cropLabel,
                      'rate': modalRate,
                      'currency': UiStrings.t('currency_symbol'),
                      'unit': UiStrings.t('qtl_unit'),
                    }),
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String actionLabel;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.greenDark, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          actionLabel,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ApmcCategoryHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;

  const _ApmcCategoryHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.green, size: 18),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          UiStrings.f('lots_count', {'count': count}),
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LoadingApmcPanel extends StatelessWidget {
  final String label;

  const _LoadingApmcPanel({required this.label});

  @override
  Widget build(BuildContext context) {
    return _ApmcPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketplaceListingCard extends StatelessWidget {
  final MarketplaceListing listing;
  final bool buyerMode;
  final bool isSavingInterest;
  final VoidCallback? onMarkInterest;

  const _MarketplaceListingCard({
    required this.listing,
    this.buyerMode = false,
    this.isSavingInterest = false,
    this.onMarkInterest,
  });

  @override
  Widget build(BuildContext context) {
    final unitLabel = switch (listing.unit.trim().toLowerCase()) {
      'kg' => UiStrings.t('kg_unit'),
      'qtl' => UiStrings.t('qtl_unit'),
      'bag' => UiStrings.t('bag_unit'),
      'packet' => UiStrings.t('packet_unit'),
      final value when value.isNotEmpty => value,
      _ => UiStrings.t('kg_unit'),
    };
    final quantity =
        '${LocaleText.number(listing.quantity, fractionDigits: 1)} $unitLabel';
    final moisture = listing.moisturePercent;
    final price = listing.askingPricePerUnit;
    return _ApmcPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    listing.displayProductName,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _ApmcTrendPill(
                  icon: buyerMode && listing.interestedByMe
                      ? Icons.check_circle_rounded
                      : Icons.storefront_rounded,
                  label: buyerMode && listing.interestedByMe
                      ? UiStrings.t('interest_marked')
                      : UiStrings.t('active'),
                  color: AppTheme.green,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              listing.farmName.trim().isEmpty
                  ? _localizedLotId(listing.batchId)
                  : '${UiStrings.label(listing.farmName)} - ${_localizedLotId(listing.batchId)}',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ApmcChip(icon: Icons.scale_rounded, label: quantity),
                if (listing.grade.trim().isNotEmpty)
                  _ApmcChip(
                    icon: Icons.verified_rounded,
                    label: UiStrings.f('grade_value', {'grade': listing.grade}),
                  ),
                if (moisture != null)
                  _ApmcChip(
                    icon: Icons.water_drop_rounded,
                    label: '${LocaleText.number(moisture, fractionDigits: 1)}%',
                  ),
                if (price != null)
                  _ApmcChip(
                    icon: Icons.currency_rupee_rounded,
                    label:
                        '${LocaleText.number(price, fractionDigits: 0)} ${UiStrings.t('per_unit')}',
                  ),
              ],
            ),
            if (listing.listingNote.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                listing.listingNote,
                style: const TextStyle(
                  color: AppTheme.textDark,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (buyerMode)
              SizedBox(
                width: double.infinity,
                child: listing.interestedByMe
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(UiStrings.t('interest_marked')),
                      )
                    : ElevatedButton.icon(
                        onPressed: isSavingInterest ? null : onMarkInterest,
                        icon: isSavingInterest
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.shopping_cart_rounded, size: 18),
                        label: Text(UiStrings.t('mark_interest')),
                      ),
              )
            else
              Row(
                children: [
                  const Icon(
                    Icons.groups_2_rounded,
                    size: 18,
                    color: AppTheme.green,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      UiStrings.f('buyer_interest_count', {
                        'count': listing.interestCount,
                      }),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _localizedRateNote(String note) {
  return switch (note) {
    'Clean graded lots are getting faster bids.' => UiStrings.t(
      'apmc_note_clean_lots',
    ),
    'Buyers prefer dry lots below 12 percent moisture.' => UiStrings.t(
      'apmc_note_dry_lots',
    ),
    'Premium for sorted grain and uniform bag weight.' => UiStrings.t(
      'apmc_note_sorted_grain',
    ),
    'Arrival is higher today; hold if moisture is high.' => UiStrings.t(
      'apmc_note_high_arrival',
    ),
    'Bulk buyers active for clean farm-gate pickup.' => UiStrings.t(
      'apmc_note_bulk_buyers',
    ),
    _ => note,
  };
}

String _localizedLotId(String value) {
  final trimmed = value.trim();
  final lotMatch = RegExp(
    r'^lot\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (lotMatch != null) {
    return '${UiStrings.t('lot')} ${LocaleText.digits(lotMatch.group(1) ?? '')}';
  }
  final batchMatch = RegExp(
    r'^batch\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (batchMatch != null) {
    return '${UiStrings.t('batch')} ${LocaleText.digits(batchMatch.group(1) ?? '')}';
  }
  return LocaleText.digits(trimmed);
}

class _ApmcRateCard extends StatelessWidget {
  final _ApmcRate rate;

  const _ApmcRateCard({required this.rate});

  @override
  Widget build(BuildContext context) {
    final trendColor = rate.trend >= 0 ? AppTheme.green : AppTheme.error;
    final trendIcon = rate.trend >= 0
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;
    return _ApmcPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rate.marketLabel,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${UiStrings.option(rate.crop)} - ${UiStrings.f('updated_at', {'time': LocaleText.time(rate.updatedAt)})}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _ApmcTrendPill(
                  icon: trendIcon,
                  label:
                      '${rate.trend >= 0 ? '+' : ''}${LocaleText.number(rate.trend, fractionDigits: 1)}%',
                  color: trendColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _RateMetric(
                    label: UiStrings.t('min_rate'),
                    value:
                        '${UiStrings.t('currency_symbol')} ${LocaleText.number(rate.minRate)}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RateMetric(
                    label: UiStrings.t('modal_rate'),
                    value:
                        '${UiStrings.t('currency_symbol')} ${LocaleText.number(rate.modalRate)}',
                    strong: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RateMetric(
                    label: UiStrings.t('max_rate'),
                    value:
                        '${UiStrings.t('currency_symbol')} ${LocaleText.number(rate.maxRate)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ApmcChip(
                  icon: Icons.grain_rounded,
                  label:
                      '${LocaleText.number(rate.arrivalQty)} ${UiStrings.t('qtl_unit')}',
                ),
                _ApmcChip(
                  icon: Icons.bolt_rounded,
                  label: UiStrings.option(rate.demand),
                ),
                _ApmcChip(
                  icon: Icons.route_rounded,
                  label:
                      '${LocaleText.number(rate.distanceKm)} ${UiStrings.t('km_unit')}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _localizedRateNote(rate.note),
              style: const TextStyle(
                color: AppTheme.textDark,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Get.snackbar(
                      UiStrings.t('apmc_agent'),
                      UiStrings.f('request_sent_for_market', {
                        'market': rate.marketLabel,
                      }),
                      snackPosition: SnackPosition.BOTTOM,
                    ),
                    icon: const Icon(Icons.support_agent_rounded, size: 18),
                    label: Text(UiStrings.t('contact')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Get.snackbar(
                      UiStrings.t('sale_plan'),
                      UiStrings.f('sale_plan_prepared_for_crop', {
                        'crop': UiStrings.option(rate.crop),
                      }),
                      snackPosition: SnackPosition.BOTTOM,
                    ),
                    icon: const Icon(Icons.sell_rounded, size: 18),
                    label: Text(UiStrings.t('plan_sale')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RateMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _RateMetric({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: strong ? AppTheme.greenPale : const Color(0xFFF7F9F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: strong ? const Color(0xFFCFE4C9) : const Color(0xFFE6ECE2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: strong ? AppTheme.greenDark : Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: strong ? 15 : 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApmcLotReadinessCard extends StatelessWidget {
  final Map<String, String> lot;
  final int modalRate;
  final double Function(String? value) toDouble;
  final int Function(String? value) toInt;
  final VoidCallback? onListForSale;
  final bool isListed;
  final bool isSavingListing;

  const _ApmcLotReadinessCard({
    required this.lot,
    required this.modalRate,
    required this.toDouble,
    required this.toInt,
    this.onListForSale,
    this.isListed = false,
    this.isSavingListing = false,
  });

  @override
  Widget build(BuildContext context) {
    final batchId = lot['batchId'] ?? UiStrings.t('lot');
    final crop = lot['crop'] ?? UiStrings.t('millet');
    final grade = lot['grade'] ?? '--';
    final moisture = toDouble(lot['moisture']);
    final qty = toDouble(lot['estimatedYield']);
    final score = toInt(lot['score']);
    final value = (qty / 100) * modalRate;
    final ready = moisture > 0 && moisture <= 12.5 && score >= 70;

    return _ApmcPanel(
      tint: ready ? AppTheme.greenPale.withValues(alpha: 0.24) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _localizedLotId(batchId),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _ApmcTrendPill(
                  icon: ready
                      ? Icons.check_circle_rounded
                      : Icons.pending_actions_rounded,
                  label: UiStrings.t(ready ? 'ready' : 'prepare'),
                  color: ready ? AppTheme.green : AppTheme.gold,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ApmcChip(
                  icon: Icons.grass_rounded,
                  label: UiStrings.option(crop),
                ),
                _ApmcChip(
                  icon: Icons.verified_rounded,
                  label: UiStrings.f('grade_value', {'grade': grade}),
                ),
                _ApmcChip(
                  icon: Icons.water_drop_rounded,
                  label: '${LocaleText.number(moisture, fractionDigits: 1)}%',
                ),
                _ApmcChip(
                  icon: Icons.scale_rounded,
                  label:
                      '${LocaleText.number(qty, fractionDigits: 1)} ${UiStrings.t('kg_unit')}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              UiStrings.f('estimated_value_modal', {
                'currency': UiStrings.t('currency_symbol'),
                'value': LocaleText.number(value, fractionDigits: 0),
              }),
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (onListForSale != null || isListed) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: isListed
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(UiStrings.t('listed_for_fpc')),
                      )
                    : ElevatedButton.icon(
                        onPressed: isSavingListing ? null : onListForSale,
                        icon: isSavingListing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.storefront_rounded, size: 18),
                        label: Text(UiStrings.t('list_for_sale')),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NearbyMarketPanel extends StatelessWidget {
  const _NearbyMarketPanel();

  @override
  Widget build(BuildContext context) {
    const markets = [
      ('apmc_market_name_akole', 18, 'best_for_small_millet_lots'),
      ('apmc_market_name_sangamner', 44, 'good_buyer_depth'),
      ('apmc_market_name_nashik', 92, 'premium_sorted_grain_market'),
    ];

    return _ApmcPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: markets
              .map(
                (market) => Padding(
                  padding: EdgeInsets.only(
                    bottom: market == markets.last ? 0 : 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.greenPale,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppTheme.green,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              UiStrings.t(market.$1),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              UiStrings.t(market.$3),
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${LocaleText.number(market.$2)} ${UiStrings.t('km_unit')}',
                        style: const TextStyle(
                          color: AppTheme.greenDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ApmcChecklistPanel extends StatelessWidget {
  const _ApmcChecklistPanel();

  @override
  Widget build(BuildContext context) {
    const items = [
      'apmc_check_bag_count',
      'apmc_check_moisture_grade',
      'apmc_check_farmer_qr',
      'apmc_check_morning_arrival',
    ];

    return _ApmcPanel(
      tint: const Color(0xFFFFFBEB),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_rounded, color: AppTheme.gold),
                const SizedBox(width: 8),
                Text(
                  UiStrings.t('before_going_apmc'),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.green,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        UiStrings.t(item),
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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

class _EmptyApmcPanel extends StatelessWidget {
  final String title;
  final String message;

  const _EmptyApmcPanel({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return _ApmcPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: AppTheme.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
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

class _ApmcPanel extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const _ApmcPanel({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tint ?? Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8DD)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ApmcChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ApmcChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8DD)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.green),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApmcTrendPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ApmcTrendPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApmcRate {
  final String marketKey;
  final String marketName;
  final String crop;
  final int minRate;
  final int modalRate;
  final int maxRate;
  final int arrivalQty;
  final String demand;
  final double trend;
  final int distanceKm;
  final DateTime updatedAt;
  final String note;

  _ApmcRate({
    required this.marketKey,
    this.marketName = '',
    required this.crop,
    required this.minRate,
    required this.modalRate,
    required this.maxRate,
    required this.arrivalQty,
    required this.demand,
    required this.trend,
    required this.distanceKm,
    required this.updatedAt,
    required this.note,
  });

  factory _ApmcRate.fromRemote(Map<String, dynamic> row) {
    return _ApmcRate(
      marketKey: _text(row, const ['market_key', 'marketKey']),
      marketName: _text(row, const ['market_name', 'marketName', 'market']),
      crop: _text(row, const ['crop', 'commodity', 'crop_name', 'cropName']),
      minRate: _int(row, const ['min_rate', 'minRate', 'minimum_rate']),
      modalRate: _int(row, const ['modal_rate', 'modalRate', 'model_rate']),
      maxRate: _int(row, const ['max_rate', 'maxRate', 'maximum_rate']),
      arrivalQty: _int(row, const ['arrival_qty', 'arrivalQty', 'arrival']),
      demand: _text(row, const ['demand', 'demand_level'], fallback: 'Stable'),
      trend: _double(row, const ['trend', 'trend_percent', 'trendPercent']),
      distanceKm: _int(row, const ['distance_km', 'distanceKm', 'distance']),
      updatedAt:
          DateTime.tryParse(
            _text(row, const ['updated_at', 'updatedAt', 'rate_date']),
          ) ??
          DateTime.now(),
      note: _text(row, const ['note', 'advice', 'remark']),
    );
  }

  String get marketLabel {
    final name = marketName.trim();
    if (name.isNotEmpty) return UiStrings.label(name);
    final key = marketKey.trim();
    return key.isEmpty ? UiStrings.t('apmc_market') : UiStrings.t(key);
  }

  static String _text(
    Map<String, dynamic> row,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = '$value'.trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static int _int(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed.round();
      }
    }
    return 0;
  }

  static double _double(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }
}
