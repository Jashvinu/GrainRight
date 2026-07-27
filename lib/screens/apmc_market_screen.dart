import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import 'package:kalsubai_farms/core/widgets/brand_text.dart';
import 'package:kalsubai_farms/core/widgets/language_selector_button.dart';
import '../controllers/language_controller.dart';
import '../models/marketplace_listing.dart';
import '../services/apmc_market_service.dart';
import '../services/marketplace_listing_service.dart';
import '../widgets/farmer_floating_bottom_nav.dart';
import '../widgets/fpc_bottom_nav.dart';

String _marketText(String english) => UiStrings.fromEnglish(english);

String _displayMarketplaceGrade(String raw) {
  final value = raw.trim();
  final normalized = value.toLowerCase();
  if (normalized.isEmpty ||
      normalized == '--' ||
      normalized == 'n/a' ||
      normalized == 'na' ||
      normalized == 'not graded') {
    return '';
  }
  return value;
}

String _money(num value) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
).format(value);

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

class _MarketplacePageState extends State<MarketplacePage>
    with SingleTickerProviderStateMixin {
  final _listingService = MarketplaceListingService();
  final _apmcService = ApmcMarketService();
  final _searchController = TextEditingController();
  late final TabController _tabs;

  List<MarketplaceInputProduct> _buyProducts = const [];
  List<MarketplaceListing> _sellListings = const [];
  List<MarketplaceListing> _myListings = const [];
  List<MarketplaceNegotiation> _negotiations = const [];
  List<MarketplaceOrder> _orders = const [];
  FpcProfitSummary _profitSummary = FpcProfitSummary.zero;
  List<ApmcMarketRate> _rates = const [];
  String _apmcSource = '';
  String _listingFilter = 'all';
  String _selectedMarketCategory = 'all';
  bool _loading = true;
  bool _loadingRates = false;
  bool _hasRequestedRates = false;
  bool _refreshingRates = false;
  String _marketplaceError = '';
  String _apmcError = '';
  String _savingId = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this, initialIndex: 0)
      ..addListener(_handleTabChanged);
    unawaited(_loadListingData());
    final selected = widget.initialSelectedLot;
    if (selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openListingForm(selected);
      });
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_handleTabChanged);
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabs.indexIsChanging) return;
    _searchController.clear();
    if (_tabs.index != 0) _selectedMarketCategory = 'all';
    setState(() {});
    if (_tabs.index == 1 && !_hasRequestedRates) {
      unawaited(_loadInitialRates());
    }
  }

  Future<void> _loadListingData() async {
    setState(() {
      _loading = true;
      _marketplaceError = '';
    });
    try {
      final results = widget.buyerMode
          ? await Future.wait<Object>([
              _listingService.listSellListings(),
              _listingService.listNegotiations(fpcWorkspace: true),
              _listingService.listOrders(fpcWorkspace: true),
              _listingService.profitSummary(),
            ])
          : await Future.wait<Object>([
              _listingService.listBuyProducts(),
              _listingService.listFarmerListings(),
              _listingService.listNegotiations(fpcWorkspace: false),
              _listingService.listOrders(fpcWorkspace: false),
            ]);
      if (!mounted) return;
      setState(() {
        if (widget.buyerMode) {
          _sellListings = results[0] as List<MarketplaceListing>;
          _negotiations = results[1] as List<MarketplaceNegotiation>;
          _orders = results[2] as List<MarketplaceOrder>;
          _profitSummary = results[3] as FpcProfitSummary;
        } else {
          _buyProducts = results[0] as List<MarketplaceInputProduct>;
          _myListings = results[1] as List<MarketplaceListing>;
          _negotiations = results[2] as List<MarketplaceNegotiation>;
          _orders = results[3] as List<MarketplaceOrder>;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _marketplaceError = _marketplaceErrorText(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInitialRates() async {
    if (_loadingRates) return;
    setState(() {
      _loadingRates = true;
      _hasRequestedRates = true;
      _apmcError = '';
    });
    try {
      final result = await _apmcService.search();
      if (!mounted) return;
      setState(() {
        _rates = result.rates;
        _apmcSource = result.source;
      });
    } catch (error) {
      if (mounted) setState(() => _apmcError = '$error');
    } finally {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  Future<void> _searchApmc({bool refresh = false}) async {
    if (_refreshingRates) return;
    setState(() {
      _refreshingRates = true;
      _apmcError = '';
    });
    try {
      final result = await _apmcService.search(
        query: _searchController.text.trim(),
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _rates = result.rates;
        _apmcSource = result.source;
      });
      if (refresh && !result.refreshed) {
        final message = result.refreshReason == 'api_key_not_configured'
            ? _marketText(
                'Official rate sync needs setup. No live rates were downloaded.',
              )
            : result.rates.isEmpty
            ? _marketText('No official rates are available yet.')
            : _marketText(
                'Live refresh is unavailable. The latest saved official rates are shown.',
              );
        Get.snackbar(
          _marketText('Official APMC rates'),
          message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _apmcError = '$error');
    } finally {
      if (mounted) setState(() => _refreshingRates = false);
    }
  }

  List<MarketplaceInputProduct> get _visibleBuyProducts {
    final query = _searchController.text.trim().toLowerCase();
    return _buyProducts
        .where((product) {
          final searchable =
              '${product.name} ${product.category} ${product.brand}'
                  .toLowerCase();
          return _matchesMarketCategory(searchable) &&
              (query.isEmpty || searchable.contains(query));
        })
        .toList(growable: false);
  }

  List<MarketplaceListing> get _visibleSellListings {
    final query = _searchController.text.trim().toLowerCase();
    return _sellListings
        .where((listing) {
          final searchable =
              '${listing.displayProductName} ${listing.productCategory} ${listing.crop} ${listing.variety} ${listing.locationLabel}'
                  .toLowerCase();
          return _matchesMarketCategory(searchable) &&
              (query.isEmpty || searchable.contains(query));
        })
        .toList(growable: false);
  }

  bool _matchesMarketCategory(String searchable) {
    return switch (_selectedMarketCategory) {
      'grains' => _containsAny(searchable, const [
        'grain',
        'millet',
        'ragi',
        'bajra',
        'wheat',
        'maize',
        'corn',
        'rice',
      ]),
      'pulses' => _containsAny(searchable, const [
        'pulse',
        'lentil',
        'dal',
        'gram',
        'chana',
        'bean',
      ]),
      'oilseeds' => _containsAny(searchable, const [
        'oilseed',
        'groundnut',
        'soybean',
        'mustard',
        'sesame',
      ]),
      'inputs' => _containsAny(searchable, const [
        'fertilizer',
        'seed',
        'pesticide',
        'protect',
        'input',
      ]),
      'equipment' => _containsAny(searchable, const [
        'tool',
        'equipment',
        'irrigation',
        'pump',
        'machinery',
      ]),
      'feed' => _containsAny(searchable, const ['feed', 'fodder', 'animal']),
      _ => true,
    };
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  void _selectMarketCategory(String category) {
    setState(() => _selectedMarketCategory = category);
  }

  List<MarketplaceListing> get _visibleMyListings {
    final query = _searchController.text.trim().toLowerCase();
    return _myListings
        .where((listing) {
          final status = listing.status.toLowerCase();
          final matchesStatus = switch (_listingFilter) {
            'active' => listing.isActive,
            'sold' => listing.isSold,
            'draft' => status == 'draft',
            'paused' => listing.isPaused,
            'expired' => status == 'expired',
            _ => true,
          };
          final matchesQuery =
              query.isEmpty ||
              '${listing.displayProductName} ${listing.crop} ${listing.variety}'
                  .toLowerCase()
                  .contains(query);
          return matchesStatus && matchesQuery;
        })
        .toList(growable: false);
  }

  List<Map<String, String>> get _listableInventoryLots {
    final selectedFarm = (widget.farmName ?? '').trim().toLowerCase();
    final listedInventoryIds = _myListings
        .map((listing) => listing.inventoryItemId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    return widget.inventoryLots
        .where((lot) {
          final remoteId = (lot['remoteId'] ?? '').trim();
          final lotFarm = (lot['farmName'] ?? '').trim().toLowerCase();
          final belongsToSelectedFarm =
              selectedFarm.isEmpty || lotFarm == selectedFarm;
          return remoteId.isNotEmpty &&
              belongsToSelectedFarm &&
              !listedInventoryIds.contains(remoteId);
        })
        .toList(growable: false);
  }

  Future<void> _openListingForm(
    Map<String, String> lot, {
    MarketplaceListing? listing,
  }) async {
    final remoteId = (lot['remoteId'] ?? listing?.inventoryItemId ?? '').trim();
    if (remoteId.isEmpty) {
      Get.snackbar(
        _marketText('Inventory sync required'),
        _marketText(
          'Sync this harvest item before listing it in the marketplace.',
        ),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final result = await showModalBottomSheet<_ListingFormValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ListingFormSheet(lot: lot, listing: listing),
    );
    if (result == null || !mounted) return;
    setState(() => _savingId = remoteId);
    try {
      if (listing == null) {
        await _listingService.createOrUpdateFromInventory(
          inventoryItemId: remoteId,
          inventoryId: (lot['itemId'] ?? '').trim(),
          title: result.title,
          askingPricePerUnit: result.price,
          listingNote: result.description,
          description: result.description,
          locationLabel: result.location,
          priceUnit: (lot['unit'] ?? 'kg').trim(),
        );
      } else {
        await _listingService.updateListing(
          listingId: listing.id,
          title: result.title,
          description: result.description,
          askingPricePerUnit: result.price,
          locationLabel: result.location,
        );
      }
      await _loadListingData();
      if (!mounted) return;
      _tabs.animateTo(2);
      Get.snackbar(
        _marketText('Listing saved'),
        _marketText('Your inventory product is now live in Marketplace.'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      Get.snackbar(
        _marketText('Could not save listing'),
        _marketplaceErrorText(error),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingId = '');
    }
  }

  String _marketplaceErrorText(Object error) {
    if (error is MarketplaceListingException) {
      return _marketText(error.message);
    }
    return _marketText(
      'Marketplace is temporarily unavailable. Please refresh and try again.',
    );
  }

  Future<void> _changeListingStatus(
    MarketplaceListing listing,
    String status,
  ) async {
    if (_savingId.isNotEmpty) return;
    setState(() => _savingId = listing.id);
    try {
      await _listingService.updateStatus(listingId: listing.id, status: status);
      await _loadListingData();
    } catch (error) {
      Get.snackbar(
        _marketText('Could not update listing'),
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingId = '');
    }
  }

  Future<double?> _requestRate({
    required String title,
    double? initialValue,
  }) async {
    final controller = TextEditingController(
      text: initialValue == null ? '' : '$initialValue',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_marketText(title)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: _marketText('Rate per kg'),
            prefixText: '₹ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_marketText('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed != null && parsed >= 0) {
                Navigator.pop(dialogContext, parsed);
              }
            },
            child: Text(_marketText('Continue')),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _counterOffer(MarketplaceNegotiation negotiation) async {
    final rate = await _requestRate(
      title: 'Counteroffer',
      initialValue: negotiation.currentOffer?.pricePerUnit,
    );
    if (rate == null) return;
    setState(() => _savingId = negotiation.id);
    try {
      await _listingService.counterOffer(
        requestId: negotiation.id,
        fpcWorkspace: widget.buyerMode,
        pricePerUnit: rate,
      );
      await _loadListingData();
      Get.snackbar(
        _marketText('Counteroffer sent'),
        _marketText('The other party can now accept or counter this rate.'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      Get.snackbar(
        _marketText('Could not send counteroffer'),
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingId = '');
    }
  }

  Future<void> _acceptOffer(MarketplaceNegotiation negotiation) async {
    final offer = negotiation.currentOffer;
    if (offer == null) return;
    setState(() => _savingId = negotiation.id);
    try {
      await _listingService.acceptOffer(
        requestId: negotiation.id,
        offerId: offer.id,
        fpcWorkspace: widget.buyerMode,
      );
      await _loadListingData();
      if (mounted) _tabs.animateTo(3);
      Get.snackbar(
        _marketText('Whole-lot order created'),
        _marketText('The accepted rate is provisional until arrival grading.'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      Get.snackbar(
        _marketText('Could not accept offer'),
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingId = '');
    }
  }

  Future<void> _proposeFinalRate(MarketplaceOrder order) async {
    final rate = await _requestRate(
      title: 'Propose final rate after grading',
      initialValue: order.finalRate ?? order.provisionalRate,
    );
    if (rate == null) return;
    setState(() => _savingId = order.id);
    try {
      await _listingService.proposeFinalRate(
        orderId: order.id,
        finalRate: rate,
      );
      await _loadListingData();
    } catch (error) {
      Get.snackbar(
        _marketText('Could not propose final rate'),
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingId = '');
    }
  }

  Future<void> _confirmFinalRate(MarketplaceOrder order) async {
    setState(() => _savingId = order.id);
    try {
      await _listingService.confirmFinalRate(order.id);
      await _loadListingData();
      Get.snackbar(
        _marketText('Final rate confirmed'),
        _marketText('The FPC can now accept procurement and post the payable.'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      Get.snackbar(
        _marketText('Could not confirm final rate'),
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingId = '');
    }
  }

  Future<void> _acceptProcurement(MarketplaceOrder order) async {
    setState(() => _savingId = order.id);
    try {
      await _listingService.acceptProcurement(order.id);
      await _loadListingData();
      Get.snackbar(
        _marketText('Procurement accepted'),
        _marketText('Stock receipt and farmer payable draft are now posted.'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      Get.snackbar(
        _marketText('Could not accept procurement'),
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingId = '');
    }
  }

  Future<void> _recordCost(MarketplaceOrder order) async {
    final result = await showDialog<_CostFormValue>(
      context: context,
      builder: (_) => const _CostDialog(),
    );
    if (result == null) return;
    setState(() => _savingId = order.id);
    try {
      await _listingService.recordCost(
        orderId: order.id,
        category: result.category,
        amount: result.amount,
        description: result.description,
      );
      await _loadListingData();
      Get.snackbar(
        _marketText('Cost recorded'),
        _marketText('The cost is included in the FPC net-margin summary.'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      Get.snackbar(
        _marketText('Could not record cost'),
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _savingId = '');
    }
  }

  void _handleBottomNav(FarmerBottomNavItem item) {
    if (item == FarmerBottomNavItem.marketplace) return;
    if (widget.onBottomNavSelected != null) {
      widget.onBottomNavSelected!(item);
    } else {
      Get.offAllNamed('/farmer', arguments: {'farmerTab': item.name});
    }
  }

  Widget _languageSelector() {
    if (!Get.isRegistered<LanguageController>()) return const SizedBox.shrink();
    final language = Get.find<LanguageController>();
    return Obx(
      () => LanguageSelectorButton(
        code: language.language.value,
        compact: true,
        onChanged: language.setLanguage,
      ),
    );
  }

  Widget _body() {
    final showingApmc = _tabs.index == 1;
    final activeError = showingApmc ? _apmcError : _marketplaceError;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          _MarketplaceIntro(
            title: switch (_tabs.index) {
              1 => _marketText('APMC Markets'),
              2 =>
                widget.buyerMode
                    ? _marketText('Negotiations')
                    : _marketText('My Listings'),
              3 => _marketText('Orders'),
              _ =>
                widget.buyerMode
                    ? _marketText('Farmer Produce')
                    : _marketText('Verified Farm Inputs'),
            },
            subtitle: switch (_tabs.index) {
              1 => _marketText('Official daily mandi prices across India'),
              2 =>
                widget.buyerMode
                    ? _marketText('Counter or accept whole-lot offers')
                    : _marketText('Manage products listed from your inventory'),
              3 => _marketText(
                'Track arrival, grading, final rate, procurement and payment',
              ),
              _ =>
                widget.buyerMode
                    ? _marketText('Verified harvest lots listed by Farmers')
                    : _marketText('Only verified supplier products are shown'),
            },
          ),
          _MarketplaceSearch(
            controller: _searchController,
            hint: switch (_tabs.index) {
              1 => _marketText('Search commodity or crop'),
              2 => _marketText('Search your listings'),
              _ => _marketText('Search marketplace products'),
            },
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_tabs.index == 1) unawaited(_searchApmc());
            },
          ),
          _MarketplaceSectionTabs(
            controller: _tabs,
            fpcWorkspace: widget.buyerMode,
          ),
          if (activeError.isNotEmpty)
            _InlineError(
              message: activeError,
              onRetry: () => unawaited(
                showingApmc ? _loadInitialRates() : _loadListingData(),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                if (widget.buyerMode)
                  _ProduceTab(
                    loading: _loading,
                    listings: _visibleSellListings,
                    profit: _profitSummary,
                    onListing: (listing) => Get.to(
                      () => MarketplaceProductDetailPage(
                        listing: listing,
                        listingService: _listingService,
                        fpcWorkspace: true,
                      ),
                    ),
                  )
                else
                  _BuyTab(
                    loading: _loading,
                    products: _visibleBuyProducts,
                    selectedCategory: _selectedMarketCategory,
                    onCategory: _selectMarketCategory,
                    onProduct: (product) => Get.to(
                      () => MarketplaceProductDetailPage(
                        product: product,
                        listingService: _listingService,
                      ),
                    ),
                  ),
                _ApmcTab(
                  loading: _loadingRates || _refreshingRates,
                  rates: _rates,
                  source: _apmcSource,
                  onSearch: () => _searchApmc(),
                  onRefresh: () => _searchApmc(refresh: true),
                ),
                if (widget.buyerMode)
                  _NegotiationsTab(
                    loading: _loading,
                    negotiations: _negotiations,
                    savingId: _savingId,
                    fpcWorkspace: true,
                    onCounter: _counterOffer,
                    onAccept: _acceptOffer,
                  )
                else
                  _MyListingsTab(
                    loading: _loading,
                    listings: _visibleMyListings,
                    allListings: _myListings,
                    inventoryLots: _listableInventoryLots,
                    farmName: widget.farmName,
                    filter: _listingFilter,
                    savingId: _savingId,
                    onListInventory: _openListingForm,
                    onFilter: (filter) =>
                        setState(() => _listingFilter = filter),
                    onOpen: (listing) => Get.to(
                      () => MarketplaceProductDetailPage(
                        listing: listing,
                        listingService: _listingService,
                        ownerMode: true,
                      ),
                    ),
                    onEdit: (listing) => _openListingForm({
                      'remoteId': listing.inventoryItemId,
                      'productName': listing.displayProductName,
                      'crop': listing.crop,
                      'variety': listing.variety,
                      'quantity': '${listing.quantity}',
                      'unit': listing.unit,
                      'farmName': listing.farmName,
                    }, listing: listing),
                    onStatus: _changeListingStatus,
                  ),
                _OrdersTab(
                  loading: _loading,
                  orders: _orders,
                  negotiations: widget.buyerMode ? const [] : _negotiations,
                  savingId: _savingId,
                  fpcWorkspace: widget.buyerMode,
                  onCounter: _counterOffer,
                  onAcceptOffer: _acceptOffer,
                  onRecordArrival: (_) => Get.toNamed('/fpo/receiver'),
                  onProposeFinalRate: _proposeFinalRate,
                  onConfirmFinalRate: _confirmFinalRate,
                  onAcceptProcurement: _acceptProcurement,
                  onRecordCost: _recordCost,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scaffold() {
    if (widget.buyerMode) {
      return FpcWorkspaceScaffold(
        current: FpcNavTab.marketplace,
        title: _marketText('Marketplace'),
        actions: [_languageSelector(), const SizedBox(width: 10)],
        body: _body(),
      );
    }
    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        toolbarHeight: appHeaderToolbarHeight,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        centerTitle: true,
        title: const BrandText(fontSize: 21),
        actions: [_languageSelector(), const SizedBox(width: 10)],
      ),
      body: Padding(
        padding: const EdgeInsets.only(bottom: 110),
        child: _body(),
      ),
      bottomNavigationBar: FarmerFloatingBottomNavDock(
        selectedItem: FarmerBottomNavItem.marketplace,
        onSelected: _handleBottomNav,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<LanguageController>()) return _scaffold();
    final language = Get.find<LanguageController>();
    return Obx(() {
      language.language.value;
      return _scaffold();
    });
  }
}

class _MarketplaceIntro extends StatelessWidget {
  final String title;
  final String subtitle;

  const _MarketplaceIntro({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12.5,
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

class _MarketplaceSearch extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _MarketplaceSearch({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: _marketText('Clear search'),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
    );
  }
}

class _MarketplaceSectionTabs extends StatelessWidget {
  final TabController controller;
  final bool fpcWorkspace;

  const _MarketplaceSectionTabs({
    required this.controller,
    required this.fpcWorkspace,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7EF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE8D6)),
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppTheme.greenDark,
          borderRadius: BorderRadius.circular(14),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.greenDark,
        labelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
        tabs: [
          _MarketplaceSectionTab(
            icon: fpcWorkspace
                ? Icons.agriculture_rounded
                : Icons.shopping_basket_rounded,
            label: _marketText(fpcWorkspace ? 'Produce' : 'Buy'),
          ),
          _MarketplaceSectionTab(
            icon: Icons.query_stats_rounded,
            label: _marketText('APMC'),
          ),
          _MarketplaceSectionTab(
            icon: fpcWorkspace
                ? Icons.handshake_outlined
                : Icons.list_alt_rounded,
            label: _marketText(fpcWorkspace ? 'Negotiations' : 'My Listings'),
          ),
          _MarketplaceSectionTab(
            icon: Icons.receipt_long_rounded,
            label: _marketText('Orders'),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceSectionTab extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MarketplaceSectionTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _BuyTab extends StatelessWidget {
  final bool loading;
  final List<MarketplaceInputProduct> products;
  final String selectedCategory;
  final ValueChanged<String> onCategory;
  final ValueChanged<MarketplaceInputProduct> onProduct;

  const _BuyTab({
    required this.loading,
    required this.products,
    required this.selectedCategory,
    required this.onCategory,
    required this.onProduct,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const _LoadingList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        _FeatureBanner(
          icon: Icons.verified_user_outlined,
          title: _marketText('Verified farm inputs'),
          body: _marketText(
            'Open a verified product to submit an enquiry. Unverified or placeholder products are never shown.',
          ),
        ),
        const SizedBox(height: 18),
        _MarketplaceSectionHeader(
          icon: Icons.category_outlined,
          title: _marketText('Shop by category'),
          action: selectedCategory == 'all' ? null : _marketText('Clear'),
          onAction: selectedCategory == 'all' ? null : () => onCategory('all'),
        ),
        const SizedBox(height: 10),
        _MarketplaceCategoryList(
          selected: selectedCategory,
          onSelected: onCategory,
        ),
        const SizedBox(height: 22),
        _MarketplaceSectionHeader(
          icon: Icons.verified_user_outlined,
          title: _marketText('Verified farm inputs'),
          count: products.length,
        ),
        const SizedBox(height: 10),
        if (products.isEmpty)
          _EmptyState(
            icon: Icons.inventory_2_outlined,
            title: _marketText('No verified input products yet'),
            body: _marketText(
              'Products appear only after supplier verification. Please check again later.',
            ),
          )
        else
          _MarketplaceProductGrid(
            itemCount: products.take(6).length,
            itemBuilder: (index) => _MarketplaceInputTile(
              product: products[index],
              onTap: () => onProduct(products[index]),
            ),
          ),
        const SizedBox(height: 22),
        const _MarketplaceTrustPanel(),
      ],
    );
  }
}

class _MarketplaceSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? count;
  final String? action;
  final VoidCallback? onAction;

  const _MarketplaceSectionHeader({
    required this.icon,
    required this.title,
    this.count,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21, color: AppTheme.greenDark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (count != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              LocaleText.number(count!),
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          )
        else if (action != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

class _MarketCategoryOption {
  final String key;
  final String label;
  final IconData icon;

  const _MarketCategoryOption(this.key, this.label, this.icon);
}

const _marketCategories = <_MarketCategoryOption>[
  _MarketCategoryOption('all', 'All products', Icons.apps_rounded),
  _MarketCategoryOption('grains', 'Grains & millets', Icons.grain_rounded),
  _MarketCategoryOption('pulses', 'Pulses & lentils', Icons.spa_outlined),
  _MarketCategoryOption('oilseeds', 'Oilseeds', Icons.water_drop_outlined),
  _MarketCategoryOption('inputs', 'Seeds & inputs', Icons.eco_outlined),
  _MarketCategoryOption(
    'equipment',
    'Farm equipment',
    Icons.agriculture_rounded,
  ),
  _MarketCategoryOption('feed', 'Animal feed', Icons.pets_outlined),
];

class _MarketplaceCategoryList extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _MarketplaceCategoryList({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _marketCategories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final category = _marketCategories[index];
          final isSelected = category.key == selected;
          return SizedBox(
            width: 94,
            child: Material(
              color: isSelected ? AppTheme.greenDark : Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: () => onSelected(category.key),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.greenDark
                          : const Color(0xFFDDE8D8),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        category.icon,
                        color: isSelected ? Colors.white : AppTheme.greenDark,
                        size: 29,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _marketText(category.label),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.textDark,
                          fontSize: 10.5,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MarketplaceProductGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  const _MarketplaceProductGrid({
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(
            itemCount,
            (index) => SizedBox(width: width, child: itemBuilder(index)),
          ),
        );
      },
    );
  }
}

class _MarketplaceListingTile extends StatelessWidget {
  final MarketplaceListing listing;
  final VoidCallback onTap;

  const _MarketplaceListingTile({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final location = listing.locationLabel.trim().isNotEmpty
        ? listing.locationLabel
        : listing.farmName;
    return _MarketplaceProductTileShell(
      onTap: onTap,
      image: _ProductVisual(
        icon: _categoryIcon(listing.productCategory),
        imagePath: listing.imagePaths.firstOrNull ?? '',
        fallbackAsset: _produceFallbackAsset(listing),
      ),
      badge: _marketText('Farm direct'),
      title: listing.displayProductName,
      subtitle: [
        if (listing.grade.trim().isNotEmpty) listing.grade,
        if (listing.moisturePercent != null)
          '${LocaleText.number(listing.moisturePercent!)}% ${_marketText('moisture')}',
      ].join(' • '),
      location: location,
      quantity: '${LocaleText.number(listing.quantity)} ${listing.unit}',
      price: listing.askingPricePerUnit == null
          ? _marketText('Price on request')
          : '${_money(listing.askingPricePerUnit!)} / ${listing.priceUnit}',
    );
  }
}

class _MarketplaceInputTile extends StatelessWidget {
  final MarketplaceInputProduct product;
  final VoidCallback onTap;

  const _MarketplaceInputTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MarketplaceProductTileShell(
      onTap: onTap,
      image: _ProductVisual(
        icon: _categoryIcon(product.category),
        imagePath: product.imagePath,
      ),
      badge: _marketText('Verified input'),
      title: product.name,
      subtitle: [
        product.brand,
        product.packageSize,
      ].where((value) => value.trim().isNotEmpty).join(' • '),
      location: product.supplierName,
      quantity: product.category,
      price: product.price == null
          ? _marketText('Price on request')
          : '${_money(product.price!)} / ${product.priceUnit}',
    );
  }
}

class _MarketplaceProductTileShell extends StatelessWidget {
  final Widget image;
  final String badge;
  final String title;
  final String subtitle;
  final String location;
  final String quantity;
  final String price;
  final VoidCallback onTap;

  const _MarketplaceProductTileShell({
    required this.image,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.quantity,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDDE6D9)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.2,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle.isEmpty
                          ? _marketText('Quality checked')
                          : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (location.trim().isNotEmpty) ...[
                      _CompactMarketplaceLine(
                        icon: Icons.location_on_outlined,
                        text: location,
                      ),
                      const SizedBox(height: 5),
                    ],
                    _CompactMarketplaceLine(
                      icon: Icons.inventory_2_outlined,
                      text: quantity,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactMarketplaceLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CompactMarketplaceLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppTheme.textMuted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 9.5),
          ),
        ),
      ],
    );
  }
}

class _MarketplaceTrustPanel extends StatelessWidget {
  const _MarketplaceTrustPanel();

  @override
  Widget build(BuildContext context) {
    const benefits = [
      (Icons.currency_rupee_rounded, 'APMC price guidance'),
      (Icons.verified_user_outlined, 'Verified products'),
      (Icons.bolt_rounded, 'Fast buying requests'),
      (Icons.public_rounded, 'All-India market view'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F3),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE8D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _marketText('Why use Kalsubai Market?'),
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: benefits
                    .map(
                      (benefit) => SizedBox(
                        width: width,
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                benefit.$1,
                                color: AppTheme.greenDark,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _marketText(benefit.$2),
                                style: const TextStyle(
                                  color: AppTheme.textDark,
                                  fontSize: 10.5,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProduceTab extends StatelessWidget {
  final bool loading;
  final List<MarketplaceListing> listings;
  final FpcProfitSummary profit;
  final ValueChanged<MarketplaceListing> onListing;

  const _ProduceTab({
    required this.loading,
    required this.listings,
    required this.profit,
    required this.onListing,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const _LoadingList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        _FeatureBanner(
          icon: Icons.agriculture_rounded,
          title: _marketText('Whole harvest lots'),
          body: _marketText(
            'Open a Farmer listing to offer a rate. One accepted negotiation reserves the entire listed lot.',
          ),
        ),
        const SizedBox(height: 12),
        _MarketCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _marketText('FPC net-margin summary'),
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _MetricText(
                    label: _marketText('Revenue'),
                    value: _money(profit.revenue),
                  ),
                  _MetricText(
                    label: _marketText('Acquisition'),
                    value: _money(profit.acquisitionCost),
                  ),
                  _MetricText(
                    label: _marketText('Operating costs'),
                    value: _money(profit.operatingCost),
                  ),
                  _MetricText(
                    label: _marketText('Net margin'),
                    value: _money(profit.netMargin),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _MarketplaceSectionHeader(
          icon: Icons.inventory_2_outlined,
          title: _marketText('Available Farmer produce'),
          count: listings.length,
        ),
        const SizedBox(height: 10),
        if (listings.isEmpty)
          _EmptyState(
            icon: Icons.agriculture_outlined,
            title: _marketText('No active Farmer listings'),
            body: _marketText(
              'Verified inventory-backed Farmer lots will appear here.',
            ),
          )
        else
          _MarketplaceProductGrid(
            itemCount: listings.length,
            itemBuilder: (index) => _MarketplaceListingTile(
              listing: listings[index],
              onTap: () => onListing(listings[index]),
            ),
          ),
      ],
    );
  }
}

class _NegotiationsTab extends StatelessWidget {
  final bool loading;
  final List<MarketplaceNegotiation> negotiations;
  final String savingId;
  final bool fpcWorkspace;
  final ValueChanged<MarketplaceNegotiation> onCounter;
  final ValueChanged<MarketplaceNegotiation> onAccept;

  const _NegotiationsTab({
    required this.loading,
    required this.negotiations,
    required this.savingId,
    required this.fpcWorkspace,
    required this.onCounter,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const _LoadingList();
    if (negotiations.isEmpty) {
      return _EmptyState(
        icon: Icons.handshake_outlined,
        title: _marketText('No negotiations yet'),
        body: _marketText('Offers and Farmer counteroffers will appear here.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      itemCount: negotiations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _NegotiationCard(
        negotiation: negotiations[index],
        loading: savingId == negotiations[index].id,
        fpcWorkspace: fpcWorkspace,
        onCounter: () => onCounter(negotiations[index]),
        onAccept: () => onAccept(negotiations[index]),
      ),
    );
  }
}

class _NegotiationCard extends StatelessWidget {
  final MarketplaceNegotiation negotiation;
  final bool loading;
  final bool fpcWorkspace;
  final VoidCallback onCounter;
  final VoidCallback onAccept;

  const _NegotiationCard({
    required this.negotiation,
    required this.loading,
    required this.fpcWorkspace,
    required this.onCounter,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final offer = negotiation.currentOffer;
    final ownRole = fpcWorkspace ? 'fpc_admin' : 'farmer';
    final canRespond =
        negotiation.isOpen &&
        offer != null &&
        offer.isOpen &&
        offer.offeredByRole != ownRole;
    return _MarketCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  negotiation.listing.displayProductName,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              _StatusBadge(
                label: _titleCase(negotiation.status.replaceAll('_', ' ')),
                color: negotiation.isOpen ? AppTheme.green : AppTheme.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_marketText('Whole lot')}: ${negotiation.listing.quantity} ${negotiation.listing.unit}',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (offer != null) ...[
            const SizedBox(height: 6),
            Text(
              '${_money(offer.pricePerUnit)} / ${offer.unit} • ${_marketText(offer.offeredByRole == 'farmer' ? 'Farmer offer' : 'FPC offer')}',
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (canRespond)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: loading ? null : onCounter,
                    child: Text(_marketText('Counter')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: loading ? null : onAccept,
                    child: Text(
                      loading
                          ? _marketText('Saving...')
                          : _marketText('Accept whole lot'),
                    ),
                  ),
                ),
              ],
            )
          else if (negotiation.isOpen)
            Text(
              _marketText('Waiting for the other party to respond.'),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  final bool loading;
  final List<MarketplaceOrder> orders;
  final List<MarketplaceNegotiation> negotiations;
  final String savingId;
  final bool fpcWorkspace;
  final ValueChanged<MarketplaceNegotiation> onCounter;
  final ValueChanged<MarketplaceNegotiation> onAcceptOffer;
  final ValueChanged<MarketplaceOrder> onRecordArrival;
  final ValueChanged<MarketplaceOrder> onProposeFinalRate;
  final ValueChanged<MarketplaceOrder> onConfirmFinalRate;
  final ValueChanged<MarketplaceOrder> onAcceptProcurement;
  final ValueChanged<MarketplaceOrder> onRecordCost;

  const _OrdersTab({
    required this.loading,
    required this.orders,
    required this.negotiations,
    required this.savingId,
    required this.fpcWorkspace,
    required this.onCounter,
    required this.onAcceptOffer,
    required this.onRecordArrival,
    required this.onProposeFinalRate,
    required this.onConfirmFinalRate,
    required this.onAcceptProcurement,
    required this.onRecordCost,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const _LoadingList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        if (negotiations.isNotEmpty) ...[
          _SectionTitle(
            title: _marketText('Open negotiations'),
            count: negotiations.length,
          ),
          const SizedBox(height: 10),
          ...negotiations.map(
            (negotiation) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _NegotiationCard(
                negotiation: negotiation,
                loading: savingId == negotiation.id,
                fpcWorkspace: fpcWorkspace,
                onCounter: () => onCounter(negotiation),
                onAccept: () => onAcceptOffer(negotiation),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SectionTitle(
          title: _marketText('Whole-lot orders'),
          count: orders.length,
        ),
        const SizedBox(height: 10),
        if (orders.isEmpty)
          _EmptyState(
            icon: Icons.receipt_long_outlined,
            title: _marketText('No accepted orders yet'),
            body: _marketText(
              'An order is created only after one party accepts the current whole-lot offer.',
            ),
          )
        else
          ...orders.map(
            (order) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OrderCard(
                order: order,
                loading: savingId == order.id,
                fpcWorkspace: fpcWorkspace,
                onRecordArrival: () => onRecordArrival(order),
                onProposeFinalRate: () => onProposeFinalRate(order),
                onConfirmFinalRate: () => onConfirmFinalRate(order),
                onAcceptProcurement: () => onAcceptProcurement(order),
                onRecordCost: () => onRecordCost(order),
              ),
            ),
          ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final MarketplaceOrder order;
  final bool loading;
  final bool fpcWorkspace;
  final VoidCallback onRecordArrival;
  final VoidCallback onProposeFinalRate;
  final VoidCallback onConfirmFinalRate;
  final VoidCallback onAcceptProcurement;
  final VoidCallback onRecordCost;

  const _OrderCard({
    required this.order,
    required this.loading,
    required this.fpcWorkspace,
    required this.onRecordArrival,
    required this.onProposeFinalRate,
    required this.onConfirmFinalRate,
    required this.onAcceptProcurement,
    required this.onRecordCost,
  });

  @override
  Widget build(BuildContext context) {
    return _MarketCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.listing.displayProductName.isEmpty
                      ? order.orderNumber
                      : order.listing.displayProductName,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              _StatusBadge(
                label: _titleCase(order.status.replaceAll('_', ' ')),
                color: order.canAcceptProcurement
                    ? Colors.orange.shade700
                    : AppTheme.green,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.orderNumber,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _MetricText(
                label: _marketText('Whole lot'),
                value: '${order.quantity} ${order.unit}',
              ),
              _MetricText(
                label: _marketText('Provisional rate'),
                value: '${_money(order.provisionalRate)} / ${order.unit}',
              ),
              if (order.arrivalQuantityKg != null)
                _MetricText(
                  label: _marketText('Arrival weight'),
                  value: '${order.arrivalQuantityKg} kg',
                ),
              if (order.arrivalGrade.isNotEmpty)
                _MetricText(
                  label: _marketText('Arrival grade'),
                  value: order.arrivalGrade,
                ),
              if (order.finalRate != null)
                _MetricText(
                  label: _marketText('Final rate'),
                  value: '${_money(order.finalRate!)} / kg',
                ),
            ],
          ),
          if (order.status == 'arrived_quarantine' ||
              order.status == 'final_rate_pending' ||
              order.status == 'final_rate_confirmed') ...[
            const SizedBox(height: 12),
            Text(
              _marketText(
                'Quarantine: stock and farmer payable remain unposted until final confirmation and FPC acceptance.',
              ),
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
          if (!fpcWorkspace && order.canReceive) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.green.withValues(alpha: 0.22),
                  ),
                ),
                child: QrImageView(
                  data: jsonEncode(_marketplaceQrPayload(order)),
                  version: QrVersions.auto,
                  size: 176,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _marketText('Marketplace order QR'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textDark,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _marketText(
                'Show this QR to the FPC when the whole harvest lot arrives.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (fpcWorkspace && order.canReceive)
                  FilledButton.icon(
                    onPressed: onRecordArrival,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(_marketText('QR receive')),
                  ),
                if (fpcWorkspace && order.canProposeFinalRate)
                  FilledButton(
                    onPressed: onProposeFinalRate,
                    child: Text(_marketText('Propose final rate')),
                  ),
                if (!fpcWorkspace && order.needsFarmerConfirmation)
                  FilledButton(
                    onPressed: onConfirmFinalRate,
                    child: Text(_marketText('Confirm final rate')),
                  ),
                if (fpcWorkspace && order.canAcceptProcurement)
                  FilledButton(
                    onPressed: onAcceptProcurement,
                    child: Text(_marketText('Accept procurement')),
                  ),
                if (fpcWorkspace)
                  OutlinedButton.icon(
                    onPressed: onRecordCost,
                    icon: const Icon(Icons.receipt_outlined),
                    label: Text(_marketText('Record cost')),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _marketplaceQrPayload(MarketplaceOrder order) {
  final listing = order.listing;
  return {
    ...order.qrPayload,
    'type': 'grainright_marketplace_order',
    'orderId': order.id,
    'orderNumber': order.orderNumber,
    'listingId': order.listingId,
    'batchId': listing.batchId,
    'quantity': order.quantity,
    'quantityKg': _quantityInKg(order.quantity, order.unit),
    'unit': order.unit,
    'grade': listing.grade,
    'moisturePercent': listing.moisturePercent,
    'crop': listing.crop,
    'variety': listing.variety,
    'farmerId': listing.farmerId,
    'farmId': listing.farmId,
    'farm': listing.farmName,
  };
}

double? _quantityInKg(double quantity, String unit) {
  switch (unit.trim().toLowerCase()) {
    case 'kg':
    case 'kgs':
    case 'kilogram':
    case 'kilograms':
      return quantity;
    case 'qtl':
    case 'quintal':
    case 'quintals':
      return quantity * 100;
    case 'ton':
    case 'tons':
    case 'tonne':
    case 'tonnes':
      return quantity * 1000;
    default:
      return null;
  }
}

class _MetricText extends StatelessWidget {
  final String label;
  final String value;

  const _MetricText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApmcTab extends StatelessWidget {
  final bool loading;
  final List<ApmcMarketRate> rates;
  final String source;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;

  const _ApmcTab({
    required this.loading,
    required this.rates,
    required this.source,
    required this.onSearch,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && rates.isEmpty) return const _LoadingList();
    DateTime? latestArrival;
    DateTime? latestSync;
    for (final rate in rates) {
      if (rate.arrivalDate != null &&
          (latestArrival == null || rate.arrivalDate!.isAfter(latestArrival))) {
        latestArrival = rate.arrivalDate;
      }
      if (rate.syncedAt != null &&
          (latestSync == null || rate.syncedAt!.isAfter(latestSync))) {
        latestSync = rate.syncedAt;
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        _FeatureBanner(
          icon: Icons.query_stats_rounded,
          title: _marketText('All-India APMC market rates'),
          body: _marketText(
            'Search official AGMARKNET mandi prices by crop, market, district or state. Rates are in rupees per quintal.',
          ),
          action: _marketText('Refresh official rates'),
          onAction: onRefresh,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search_rounded),
                label: Text(_marketText('Search rates')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionTitle(
          title: _marketText('Market products'),
          count: rates.length,
        ),
        if (source.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            '${_marketText('Source')}: $source',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
          ),
        ],
        if (latestArrival != null || latestSync != null) ...[
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              if (latestArrival != null)
                _InfoPill(
                  icon: Icons.calendar_today_outlined,
                  text:
                      '${_marketText('Latest rate date')}: ${DateFormat('dd MMM yyyy').format(latestArrival.toLocal())}',
                ),
              if (latestSync != null)
                _InfoPill(
                  icon: Icons.sync_rounded,
                  text:
                      '${_marketText('Last official sync')}: ${DateFormat('dd MMM, HH:mm').format(latestSync.toLocal())}',
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (rates.isEmpty)
          _EmptyState(
            icon: Icons.query_stats_outlined,
            title: _marketText('No official rates found'),
            body: _marketText(
              'No rates are available for this search yet. Try another crop or check again later.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: rates
                    .map(
                      (rate) => SizedBox(
                        width: width,
                        child: _ApmcRateCard(rate: rate),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
      ],
    );
  }
}

class _MyListingsTab extends StatelessWidget {
  final bool loading;
  final List<MarketplaceListing> listings;
  final List<MarketplaceListing> allListings;
  final List<Map<String, String>> inventoryLots;
  final String? farmName;
  final String filter;
  final String savingId;
  final ValueChanged<String> onFilter;
  final ValueChanged<Map<String, String>> onListInventory;
  final ValueChanged<MarketplaceListing> onOpen;
  final ValueChanged<MarketplaceListing> onEdit;
  final void Function(MarketplaceListing, String) onStatus;

  const _MyListingsTab({
    required this.loading,
    required this.listings,
    required this.allListings,
    required this.inventoryLots,
    required this.farmName,
    required this.filter,
    required this.savingId,
    required this.onFilter,
    required this.onListInventory,
    required this.onOpen,
    required this.onEdit,
    required this.onStatus,
  });

  int _count(String value) => allListings.where((listing) {
    final status = listing.status.toLowerCase();
    return switch (value) {
      'active' => listing.isActive,
      'sold' => listing.isSold,
      'draft' => status == 'draft',
      'paused' => listing.isPaused,
      'expired' => status == 'expired',
      _ => true,
    };
  }).length;

  @override
  Widget build(BuildContext context) {
    if (loading) return const _LoadingList();
    const filters = ['all', 'active', 'sold', 'draft', 'paused', 'expired'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        _FeatureBanner(
          icon: Icons.inventory_2_outlined,
          title: (farmName ?? '').trim().isEmpty
              ? _marketText('Sell from farm inventory')
              : '${_marketText('Sell from')} ${farmName!.trim()}',
          body: inventoryLots.isEmpty
              ? _marketText(
                  'No synced inventory is ready to list. Add or sync a harvest item from the Farm screen first.',
                )
              : '${inventoryLots.length} ${_marketText('inventory products are ready to list in the market.')}',
        ),
        if (inventoryLots.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 174,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: inventoryLots.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _InventoryListingCandidateCard(
                lot: inventoryLots[index],
                saving: savingId == inventoryLots[index]['remoteId'],
                onList: () => onListInventory(inventoryLots[index]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _SectionTitle(
          title: _marketText('Your market listings'),
          count: allListings.length,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final value = filters[index];
              return ChoiceChip(
                selected: value == filter,
                onSelected: (_) => onFilter(value),
                label: Text(
                  '${_marketText(value == 'all' ? 'All' : _titleCase(value))} (${_count(value)})',
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (listings.isEmpty)
          _EmptyState(
            icon: Icons.list_alt_rounded,
            title: _marketText('No listings in this status'),
            body: _marketText(
              'List a synced product from Inventory to see it here.',
            ),
          )
        else
          ...listings.map(
            (listing) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MyListingCard(
                listing: listing,
                loading: savingId == listing.id,
                onOpen: () => onOpen(listing),
                onEdit: () => onEdit(listing),
                onPause: () =>
                    onStatus(listing, listing.isPaused ? 'listed' : 'paused'),
                onSold: () => onStatus(listing, 'sold'),
              ),
            ),
          ),
      ],
    );
  }
}

class _InventoryListingCandidateCard extends StatelessWidget {
  final Map<String, String> lot;
  final bool saving;
  final VoidCallback onList;

  const _InventoryListingCandidateCard({
    required this.lot,
    required this.saving,
    required this.onList,
  });

  @override
  Widget build(BuildContext context) {
    final productName = (lot['productName'] ?? '').trim();
    final crop = (lot['crop'] ?? '').trim();
    final variety = (lot['variety'] ?? '').trim();
    final title = productName.isNotEmpty
        ? productName
        : [crop, variety].where((value) => value.isNotEmpty).join(' ');
    final quantity = (lot['quantity'] ?? '').trim();
    final unit = (lot['unit'] ?? '').trim();
    final grade = _displayMarketplaceGrade(lot['grade'] ?? '');
    return SizedBox(
      width: 248,
      child: _MarketCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _categoryIcon(lot['productCategory'] ?? ''),
                    color: AppTheme.greenDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title.isEmpty ? _marketText('Farm product') : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              [
                if (quantity.isNotEmpty) '$quantity $unit'.trim(),
                if (grade.isNotEmpty) '${_marketText('Grade')} $grade',
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: saving ? null : onList,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_business_rounded, size: 18),
                label: Text(_marketText('List in market')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MarketplaceProductDetailPage extends StatefulWidget {
  final MarketplaceListing? listing;
  final MarketplaceInputProduct? product;
  final MarketplaceListingService listingService;
  final bool ownerMode;
  final bool fpcWorkspace;

  const MarketplaceProductDetailPage({
    super.key,
    this.listing,
    this.product,
    required this.listingService,
    this.ownerMode = false,
    this.fpcWorkspace = false,
  }) : assert(listing != null || product != null);

  @override
  State<MarketplaceProductDetailPage> createState() =>
      _MarketplaceProductDetailPageState();
}

class _MarketplaceProductDetailPageState
    extends State<MarketplaceProductDetailPage> {
  bool _saving = false;

  Future<void> _request() async {
    final request = await showModalBottomSheet<_PurchaseRequestValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PurchaseRequestSheet(
        initialProduct:
            widget.listing?.displayProductName ?? widget.product?.name ?? '',
        initialUnit:
            widget.listing?.unit ?? widget.product?.priceUnit ?? 'unit',
        initialQuantity: widget.listing?.quantity,
        initialPrice: widget.listing?.askingPricePerUnit,
        wholeLotOffer: widget.fpcWorkspace,
      ),
    );
    if (request == null) return;
    setState(() => _saving = true);
    try {
      await widget.listingService.createPurchaseRequest(
        listingId: widget.listing?.id ?? '',
        productId: widget.product?.id ?? '',
        productName: request.productName,
        quantity: request.quantity,
        unit: request.unit,
        proposedPrice: request.proposedPrice,
        message: request.message,
      );
      if (!mounted) return;
      Get.snackbar(
        _marketText(
          widget.fpcWorkspace ? 'Whole-lot offer sent' : 'Request submitted',
        ),
        _marketText(
          widget.fpcWorkspace
              ? 'The Farmer can accept or counter the offer.'
              : 'The verified supplier enquiry has been saved.',
        ),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      Get.snackbar(
        _marketText('Request failed'),
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final product = widget.product;
    final title = listing?.displayProductName ?? product!.name;
    final description = listing?.description.trim().isNotEmpty == true
        ? listing!.description
        : product?.description.trim().isNotEmpty == true
        ? product!.description
        : _marketText('No additional product description was provided.');
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(_marketText('Product details')),
      ),
      bottomNavigationBar: widget.ownerMode
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _request,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.shopping_cart_checkout_rounded),
                  label: Text(
                    _marketText(
                      widget.fpcWorkspace
                          ? 'Offer for whole lot'
                          : 'Request verified product',
                    ),
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          _ProductVisual(
            icon: _categoryIcon(
              listing?.productCategory ?? product?.category ?? '',
            ),
            imagePath:
                listing?.imagePaths.firstOrNull ?? product?.imagePath ?? '',
            fallbackAsset: listing == null
                ? ''
                : _produceFallbackAsset(listing),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (listing?.isActive == true || product?.isVerified == true)
                const _StatusBadge(label: 'Verified', color: AppTheme.green),
            ],
          ),
          const SizedBox(height: 8),
          if (listing?.askingPricePerUnit != null)
            Text(
              '${_money(listing!.askingPricePerUnit!)} / ${listing.priceUnit}',
              style: const TextStyle(
                fontSize: 22,
                color: AppTheme.green,
                fontWeight: FontWeight.w900,
              ),
            )
          else if (product?.price != null)
            Text(
              '${_money(product!.price!)} / ${product.priceUnit}',
              style: const TextStyle(
                fontSize: 22,
                color: AppTheme.green,
                fontWeight: FontWeight.w900,
              ),
            )
          else
            Text(
              _marketText('Price on request'),
              style: const TextStyle(
                color: AppTheme.green,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 18),
          _DetailSection(
            title: _marketText('About this product'),
            body: description,
          ),
          if (listing != null) ...[
            const SizedBox(height: 12),
            _DetailFacts(
              facts: [
                (
                  _marketText('Quantity'),
                  '${LocaleText.number(listing.quantity)} ${listing.unit}',
                ),
                (
                  _marketText('Grade'),
                  listing.grade.isEmpty
                      ? _marketText('Not provided')
                      : listing.grade,
                ),
                (
                  _marketText('Moisture'),
                  listing.moisturePercent == null
                      ? _marketText('Not provided')
                      : '${LocaleText.number(listing.moisturePercent!)}%',
                ),
                (
                  _marketText('Variety'),
                  listing.variety.isEmpty
                      ? _marketText('Not provided')
                      : listing.variety,
                ),
                (
                  _marketText('Location'),
                  listing.locationLabel.isEmpty
                      ? listing.farmName
                      : listing.locationLabel,
                ),
                (_marketText('Views'), LocaleText.number(listing.viewCount)),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            _DetailFacts(
              facts: [
                (_marketText('Category'), product!.category),
                (
                  _marketText('Brand'),
                  product.brand.isEmpty
                      ? _marketText('Not provided')
                      : product.brand,
                ),
                (
                  _marketText('Pack size'),
                  product.packageSize.isEmpty
                      ? _marketText('Not provided')
                      : product.packageSize,
                ),
                (
                  _marketText('Supplier'),
                  product.supplierName.isEmpty
                      ? _marketText('Verified supplier')
                      : product.supplierName,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MyListingCard extends StatelessWidget {
  final MarketplaceListing listing;
  final bool loading;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onPause;
  final VoidCallback onSold;

  const _MyListingCard({
    required this.listing,
    required this.loading,
    required this.onOpen,
    required this.onEdit,
    required this.onPause,
    required this.onSold,
  });

  @override
  Widget build(BuildContext context) {
    final grade = _displayMarketplaceGrade(listing.grade);
    return _MarketCard(
      onTap: onOpen,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: _ProductVisual(
                  icon: _categoryIcon(listing.productCategory),
                  imagePath: listing.imagePaths.firstOrNull ?? '',
                  fallbackAsset: _produceFallbackAsset(listing),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.displayProductName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _StatusBadge(
                          label: _titleCase(listing.status),
                          color: listing.isActive
                              ? AppTheme.green
                              : AppTheme.textMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (grade.isNotEmpty) '${_marketText('Grade')} $grade',
                        '${LocaleText.number(listing.quantity)} ${listing.unit}',
                      ].join(' • '),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      listing.askingPricePerUnit == null
                          ? _marketText('Price on request')
                          : '${_money(listing.askingPricePerUnit!)} / ${listing.priceUnit}',
                      style: const TextStyle(
                        color: AppTheme.green,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_marketText('Views')}: ${LocaleText.number(listing.viewCount)} • ${_marketText('Requests')}: ${LocaleText.number(listing.interestCount)}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!listing.isSold) ...[
            const Divider(height: 22),
            if (loading)
              const LinearProgressIndicator(minHeight: 2)
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(_marketText('Edit')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPause,
                      icon: Icon(
                        listing.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _marketText(listing.isPaused ? 'Resume' : 'Pause'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSold,
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: Text(_marketText('Sold')),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _ApmcRateCard extends StatelessWidget {
  final ApmcMarketRate rate;

  const _ApmcRateCard({required this.rate});

  @override
  Widget build(BuildContext context) {
    final date = rate.arrivalDate == null
        ? ''
        : DateFormat('dd MMM yyyy').format(rate.arrivalDate!.toLocal());
    return _MarketCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppTheme.green,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rate.commodity,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      [
                        rate.variety,
                        rate.grade,
                      ].where((value) => value.isNotEmpty).join(' • '),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_money(rate.modalPrice)}/qtl',
                style: const TextStyle(
                  color: AppTheme.green,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _IconLine(
            icon: Icons.location_on_outlined,
            text: '${rate.market}, ${rate.district}, ${rate.state}',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _RateValue(
                  label: _marketText('Minimum'),
                  value: rate.minPrice,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RateValue(
                  label: _marketText('Modal'),
                  value: rate.modalPrice,
                  emphasized: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RateValue(
                  label: _marketText('Maximum'),
                  value: rate.maxPrice,
                ),
              ),
            ],
          ),
          if (date.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              '${_marketText('Arrival date')}: $date',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.greenDark),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateValue extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasized;

  const _RateValue({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: emphasized ? AppTheme.greenPale : const Color(0xFFF7F8F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
          ),
          const SizedBox(height: 3),
          Text(
            _money(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: emphasized ? AppTheme.green : AppTheme.textDark,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  const _FeatureBanner({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F8EF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCEAD7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: AppTheme.green, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 7),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 34),
                    ),
                    child: Text(action!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          LocaleText.number(count),
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MarketCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _MarketCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE0E8DC)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ProductVisual extends StatelessWidget {
  final IconData icon;
  final String imagePath;
  final String fallbackAsset;

  const _ProductVisual({
    required this.icon,
    required this.imagePath,
    this.fallbackAsset = '',
  });

  @override
  Widget build(BuildContext context) {
    Widget fallback() => ColoredBox(
      color: const Color(0xFFEDF6E9),
      child: Center(child: Icon(icon, color: AppTheme.green, size: 38)),
    );
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        ),
      );
    }
    if (imagePath.startsWith('assets/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: fallbackAsset.isEmpty
          ? fallback()
          : Image.asset(
              fallbackAsset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        _marketText(label),
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppTheme.textMuted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E8DC)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.green, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.error,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.error, fontSize: 11.5),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(_marketText('Retry'))),
        ],
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ListingFormValue {
  final String title;
  final double price;
  final String description;
  final String location;

  const _ListingFormValue({
    required this.title,
    required this.price,
    required this.description,
    required this.location,
  });
}

class _ListingFormSheet extends StatefulWidget {
  final Map<String, String> lot;
  final MarketplaceListing? listing;

  const _ListingFormSheet({required this.lot, this.listing});

  @override
  State<_ListingFormSheet> createState() => _ListingFormSheetState();
}

class _ListingFormSheetState extends State<_ListingFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _price;
  late final TextEditingController _description;
  late final TextEditingController _location;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final listing = widget.listing;
    final lotName = (widget.lot['productName'] ?? '').trim();
    _title = TextEditingController(
      text:
          listing?.displayProductName ??
          (lotName.isEmpty
              ? '${widget.lot['crop'] ?? ''} ${widget.lot['variety'] ?? ''}'
                    .trim()
              : lotName),
    );
    _price = TextEditingController(
      text: listing?.askingPricePerUnit?.toStringAsFixed(0) ?? '',
    );
    _description = TextEditingController(text: listing?.description ?? '');
    _location = TextEditingController(
      text: listing?.locationLabel ?? widget.lot['farmName'] ?? '',
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lotQuantity = (widget.lot['quantity'] ?? '').trim();
    final lotUnit = (widget.lot['unit'] ?? 'kg').trim();
    final lotGrade = _displayMarketplaceGrade(widget.lot['grade'] ?? '');
    final lotFarm = (widget.lot['farmName'] ?? '').trim();
    return _FormSheet(
      title: _marketText(
        widget.listing == null ? 'List product in Market' : 'Edit listing',
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7EF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCE8D6)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: AppTheme.greenDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _marketText('Listing from synced inventory'),
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (lotQuantity.isNotEmpty)
                              '$lotQuantity $lotUnit'.trim(),
                            if (lotGrade.isNotEmpty)
                              '${_marketText('Grade')} $lotGrade',
                            if (lotFarm.isNotEmpty) lotFarm,
                          ].join(' • '),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(
                labelText: _marketText('Product name'),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? _marketText('Product name is required')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    '${_marketText('Asking price per')} ${lotUnit.isEmpty ? 'kg' : lotUnit}',
                prefixText: '₹ ',
              ),
              validator: (value) =>
                  (double.tryParse((value ?? '').trim()) ?? 0) <= 0
                  ? _marketText('Enter a valid price')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: InputDecoration(
                labelText: _marketText('Pickup location'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: _marketText('Product description'),
                hintText: _marketText(
                  'Describe quality, moisture, packaging and pickup details',
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.of(context).pop(
                    _ListingFormValue(
                      title: _title.text.trim(),
                      price: double.parse(_price.text.trim()),
                      description: _description.text.trim(),
                      location: _location.text.trim(),
                    ),
                  );
                },
                icon: const Icon(Icons.storefront_rounded),
                label: Text(
                  _marketText(
                    widget.listing == null ? 'Publish listing' : 'Save changes',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CostFormValue {
  final String category;
  final double amount;
  final String description;

  const _CostFormValue({
    required this.category,
    required this.amount,
    required this.description,
  });
}

class _CostDialog extends StatefulWidget {
  const _CostDialog();

  @override
  State<_CostDialog> createState() => _CostDialogState();
}

class _CostDialogState extends State<_CostDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _category = 'procurement_logistics';

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const categories = [
      'procurement_logistics',
      'processing',
      'packaging',
      'sales_logistics',
      'adjustment',
    ];
    return AlertDialog(
      title: Text(_marketText('Record order cost')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(labelText: _marketText('Category')),
              items: categories
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        _marketText(_titleCase(value.replaceAll('_', ' '))),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: _marketText('Amount'),
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: _marketText('Description'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_marketText('Cancel')),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amount.text.trim());
            final description = _description.text.trim();
            if (amount == null || amount == 0 || description.isEmpty) return;
            Navigator.pop(
              context,
              _CostFormValue(
                category: _category,
                amount: amount,
                description: description,
              ),
            );
          },
          child: Text(_marketText('Save cost')),
        ),
      ],
    );
  }
}

class _PurchaseRequestValue {
  final String productName;
  final double? quantity;
  final String unit;
  final double? proposedPrice;
  final String message;

  const _PurchaseRequestValue({
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.proposedPrice,
    required this.message,
  });
}

class _PurchaseRequestSheet extends StatefulWidget {
  final String initialProduct;
  final String initialUnit;
  final double? initialQuantity;
  final double? initialPrice;
  final bool wholeLotOffer;

  const _PurchaseRequestSheet({
    this.initialProduct = '',
    this.initialUnit = 'unit',
    this.initialQuantity,
    this.initialPrice,
    this.wholeLotOffer = false,
  });

  @override
  State<_PurchaseRequestSheet> createState() => _PurchaseRequestSheetState();
}

class _PurchaseRequestSheetState extends State<_PurchaseRequestSheet> {
  late final TextEditingController _product;
  final _quantity = TextEditingController();
  final _message = TextEditingController();
  final _price = TextEditingController();
  late final TextEditingController _unit;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _product = TextEditingController(text: widget.initialProduct);
    _unit = TextEditingController(text: widget.initialUnit);
    _quantity.text = widget.initialQuantity?.toString() ?? '';
    _price.text = widget.initialPrice?.toString() ?? '';
  }

  @override
  void dispose() {
    _product.dispose();
    _quantity.dispose();
    _message.dispose();
    _price.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FormSheet(
      title: _marketText(
        widget.wholeLotOffer
            ? 'Offer for whole lot'
            : 'Request verified product',
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _product,
              readOnly: widget.initialProduct.isNotEmpty,
              decoration: InputDecoration(
                labelText: _marketText('Product needed'),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? _marketText('Product name is required')
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantity,
                    readOnly: widget.wholeLotOffer,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _marketText('Quantity'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 104,
                  child: TextFormField(
                    controller: _unit,
                    readOnly: widget.wholeLotOffer,
                    decoration: InputDecoration(labelText: _marketText('Unit')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.wholeLotOffer) ...[
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _marketText('Offer rate per unit'),
                  prefixText: '₹ ',
                ),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  return parsed == null || parsed < 0
                      ? _marketText('A valid offer rate is required')
                      : null;
                },
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _message,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: _marketText('Message'),
                hintText: _marketText(
                  'Add delivery location or quality requirements',
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.of(context).pop(
                    _PurchaseRequestValue(
                      productName: _product.text.trim(),
                      quantity: double.tryParse(_quantity.text.trim()),
                      unit: _unit.text.trim().isEmpty
                          ? 'unit'
                          : _unit.text.trim(),
                      proposedPrice: double.tryParse(_price.text.trim()),
                      message: _message.text.trim(),
                    ),
                  );
                },
                child: Text(
                  _marketText(
                    widget.wholeLotOffer ? 'Send offer' : 'Submit request',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormSheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _FormSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        16,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5DDD2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final String body;

  const _DetailSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return _MarketCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: AppTheme.textMuted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _DetailFacts extends StatelessWidget {
  final List<(String, String)> facts;

  const _DetailFacts({required this.facts});

  @override
  Widget build(BuildContext context) {
    return _MarketCard(
      child: Column(
        children: facts
            .map(
              (fact) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        fact.$1,
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        fact.$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

IconData _categoryIcon(String category) {
  final value = category.toLowerCase();
  if (value.contains('fert')) return Icons.science_outlined;
  if (value.contains('seed')) return Icons.grass_rounded;
  if (value.contains('irrig')) return Icons.water_drop_outlined;
  if (value.contains('tool') || value.contains('equip')) {
    return Icons.agriculture_rounded;
  }
  if (value.contains('pest') || value.contains('protect')) {
    return Icons.health_and_safety_outlined;
  }
  if (value.contains('feed')) return Icons.pets_outlined;
  if (value.contains('processed')) return Icons.shopping_bag_outlined;
  if (value.contains('byproduct')) return Icons.eco_outlined;
  return Icons.grain_rounded;
}

String _produceFallbackAsset(MarketplaceListing listing) {
  final value =
      '${listing.displayProductName} ${listing.crop} ${listing.variety}'
          .toLowerCase();
  if (value.contains('pearl millet') || value.contains('bajra')) {
    return 'assets/marketplace/pearl_millet_fallback.png';
  }
  return '';
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
