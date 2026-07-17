import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../services/local_app_database.dart';
import '../services/offline_map_download_manager.dart';
import '../services/offline_map_service.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final _service = OfflineMapService();
  final _searchController = TextEditingController();
  final _radiusController = TextEditingController(
    text: OfflineMapService.defaultRadiusKm.toStringAsFixed(0),
  );
  Timer? _debounce;
  StreamSubscription<OfflineMapDownloadProgress>? _managerSubscription;

  List<OfflinePlacePrediction> _predictions = const [];
  List<OfflineMapRegionRecord> _regions = const [];
  OfflinePlaceResult? _selectedPlace;
  OfflineMapDownloadProgress? _progress;
  bool _searching = false;
  bool _resolving = false;
  bool _downloading = false;
  bool _tileConfigLoaded = false;
  bool _hasOfflineTileSource = false;
  int _searchGeneration = 0;
  String _sourceLabel = UiStrings.t('offline_tile_source');
  String? _searchError;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTileConfig());
    _loadRegions();
    final manager = OfflineMapDownloadManager.instance;
    _progress = manager.lastProgress;
    _downloading = manager.isDownloading;
    _managerSubscription = manager.progressStream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _downloading = OfflineMapDownloadManager.instance.isDownloading;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _downloadError = _friendlyError(error);
          _downloading = false;
        });
        _loadRegions();
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _managerSubscription?.cancel();
    _searchController.dispose();
    _radiusController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    final regions = await _service.listRegions();
    if (mounted) setState(() => _regions = regions);
  }

  Future<void> _loadTileConfig() async {
    final hasTileSource = await _service.hasOfflineTileSource();
    final sourceLabel = await _service.offlineTileSourceLabel();
    if (!mounted) return;
    setState(() {
      _tileConfigLoaded = true;
      _hasOfflineTileSource = hasTileSource;
      _sourceLabel = sourceLabel;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _searchGeneration += 1;
    final generation = _searchGeneration;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = value.trim();
      if (query.length < 2) {
        if (mounted) {
          setState(() {
            _predictions = const [];
            _searchError = null;
            _searching = false;
          });
        }
        return;
      }
      setState(() {
        _searching = true;
        _searchError = null;
      });
      try {
        final predictions = await _service.searchPlaces(query);
        if (!mounted || generation != _searchGeneration) return;
        setState(() => _predictions = predictions);
      } catch (e) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() => _searchError = _friendlyError(e));
      } finally {
        if (mounted && generation == _searchGeneration) {
          setState(() => _searching = false);
        }
      }
    });
  }

  Future<void> _selectPrediction(OfflinePlacePrediction prediction) async {
    _debounce?.cancel();
    _searchGeneration += 1;
    setState(() {
      _resolving = true;
      _searchError = null;
    });
    try {
      final place = await _service.resolvePrediction(prediction);
      if (!mounted) return;
      if (place == null) {
        setState(() => _searchError = UiStrings.t('could_not_load_place'));
        return;
      }
      FocusScope.of(context).unfocus();
      setState(() {
        _selectedPlace = place;
        _predictions = const [];
        _searchController.text = place.title;
      });
    } catch (e) {
      if (mounted) setState(() => _searchError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _downloadSelected() async {
    final place = _selectedPlace;
    if (place == null || _downloading) return;
    await _downloadRegion(place);
  }

  Future<void> _redownloadRegion(OfflineMapRegionRecord region) async {
    final place = OfflinePlaceResult(
      placeId: region.regionId,
      title: region.label,
      address: UiStrings.t('stored_offline_region'),
      latitude: region.centerLat,
      longitude: region.centerLng,
    );
    await _downloadRegion(
      place,
      radiusKm: region.radiusKm,
      minZoom: region.minZoom
          .clamp(
            OfflineMapService.minDownloadZoom,
            OfflineMapService.maxDownloadZoom,
          )
          .toInt(),
      maxZoom: region.maxZoom
          .clamp(
            OfflineMapService.defaultMaxZoom,
            OfflineMapService.maxDownloadZoom,
          )
          .toInt(),
    );
  }

  Future<void> _downloadRegion(
    OfflinePlaceResult place, {
    double? radiusKm,
    int minZoom = OfflineMapService.defaultMinZoom,
    int maxZoom = OfflineMapService.defaultMaxZoom,
  }) async {
    final radius =
        radiusKm ??
        double.tryParse(_radiusController.text.trim()) ??
        OfflineMapService.defaultRadiusKm;
    setState(() {
      _downloading = true;
      _downloadError = null;
      _progress = null;
    });
    await OfflineMapDownloadManager.instance.startDownload(
      place: place,
      radiusKm: max(
        1,
        min(OfflineMapService.defaultMaxRadiusKm, radius.toDouble()),
      ),
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }

  Future<void> _deleteRegion(OfflineMapRegionRecord region) async {
    await _service.deleteRegion(region);
    await _loadRegions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          UiStrings.f('offline_map_deleted', {'region': region.label}),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canDownload =
        _tileConfigLoaded &&
        _hasOfflineTileSource &&
        _service.supportsOfflineDownloads;
    final warningMessage = _offlineWarningMessage();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('offline_field_maps')),
      ),
      body: RefreshIndicator(
        color: AppTheme.green,
        onRefresh: _loadRegions,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            if (warningMessage != null) _TileSourceWarning(warningMessage),
            _SearchPanel(
              controller: _searchController,
              radiusController: _radiusController,
              predictions: _predictions,
              selectedPlace: _selectedPlace,
              searching: _searching,
              resolving: _resolving,
              downloading: _downloading,
              searchError: _searchError,
              downloadError: _downloadError,
              progress: _progress,
              canDownload: canDownload,
              sourceLabel: _sourceLabel,
              onChanged: _onSearchChanged,
              onSelect: _selectPrediction,
              onDownload: _downloadSelected,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    UiStrings.t('stored_field_maps'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.greenDark,
                    ),
                  ),
                ),
                Text(
                  LocaleText.number(_regions.length),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_regions.isEmpty)
              const _EmptyRegions()
            else
              for (final region in _regions)
                _RegionTile(
                  region: region,
                  downloading: _downloading,
                  onUpdate: () => _redownloadRegion(region),
                  onDelete: () => _deleteRegion(region),
                ),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('MAPTILER_API_KEY')) {
      return UiStrings.t('maptiler_key_required');
    }
    if (text.contains('OFFLINE_TILE_URL_TEMPLATE')) {
      return UiStrings.t('offline_tile_template_required');
    }
    if (text.contains('This region still needs')) {
      return LocaleText.digits(text.replaceFirst('Bad state: ', ''));
    }
    if (text.length <= 160) return LocaleText.digits(text);
    return LocaleText.digits('${text.substring(0, 160)}...');
  }

  String? _offlineWarningMessage() {
    if (!_tileConfigLoaded) return null;
    if (!_service.supportsOfflineDownloads) {
      return UiStrings.t('offline_downloads_unavailable');
    }
    if (!_hasOfflineTileSource) {
      return UiStrings.t('offline_imagery_not_configured');
    }
    return null;
  }
}

class _SearchPanel extends StatelessWidget {
  final TextEditingController controller;
  final TextEditingController radiusController;
  final List<OfflinePlacePrediction> predictions;
  final OfflinePlaceResult? selectedPlace;
  final bool searching;
  final bool resolving;
  final bool downloading;
  final bool canDownload;
  final String sourceLabel;
  final String? searchError;
  final String? downloadError;
  final OfflineMapDownloadProgress? progress;
  final ValueChanged<String> onChanged;
  final ValueChanged<OfflinePlacePrediction> onSelect;
  final VoidCallback onDownload;

  const _SearchPanel({
    required this.controller,
    required this.radiusController,
    required this.predictions,
    required this.selectedPlace,
    required this.searching,
    required this.resolving,
    required this.downloading,
    required this.canDownload,
    required this.sourceLabel,
    required this.onChanged,
    required this.onSelect,
    required this.onDownload,
    this.searchError,
    this.downloadError,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedPlace;
    final progressValue = progress?.fraction ?? 0;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE1E7DF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              enabled: !downloading,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              decoration: InputDecoration(
                labelText: UiStrings.t('search_village_field_area'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searching || resolving
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            if (searchError != null) ...[
              const SizedBox(height: 8),
              Text(
                searchError!,
                style: TextStyle(
                  color: Colors.red.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (predictions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.white,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFFE6ECE5)),
                ),
                child: Column(
                  children: [
                    for (final prediction in predictions.take(6))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(prediction.title),
                        subtitle: prediction.subtitle.isEmpty
                            ? null
                            : Text(prediction.subtitle),
                        onTap: () => onSelect(prediction),
                      ),
                  ],
                ),
              ),
            ],
            if (selected != null) ...[
              const SizedBox(height: 12),
              _SelectedPlaceCard(place: selected),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: TextField(
                      controller: radiusController,
                      enabled: !downloading,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: UiStrings.t('radius_km'),
                        helperText: UiStrings.t('best_detail_km'),
                        prefixIcon: const Icon(
                          Icons.radio_button_unchecked_rounded,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _downloadHint,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: canDownload && !downloading ? onDownload : null,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(
                  UiStrings.t(
                    downloading ? 'downloading' : 'download_field_map',
                  ),
                ),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progressValue.clamp(0, 1),
                color: AppTheme.green,
                backgroundColor: AppTheme.greenPale,
              ),
              const SizedBox(height: 6),
              Text(
                UiStrings.f('offline_tiles_progress', {
                  'downloaded': progress!.downloadedTiles,
                  'total': progress!.totalTiles,
                  'source': sourceLabel,
                }),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (downloadError != null) ...[
              const SizedBox(height: 8),
              Text(
                downloadError!,
                style: TextStyle(
                  color: Colors.red.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _downloadHint {
    return UiStrings.t('offline_map_download_hint');
  }
}

class _SelectedPlaceCard extends StatelessWidget {
  final OfflinePlaceResult place;

  const _SelectedPlaceCard({required this.place});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.map_outlined, color: AppTheme.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.title,
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    UiStrings.f('lat_lng_value', {
                      'lat': LocaleText.number(
                        place.latitude,
                        fractionDigits: 5,
                      ),
                      'lng': LocaleText.number(
                        place.longitude,
                        fractionDigits: 5,
                      ),
                    }),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
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

class _RegionTile extends StatelessWidget {
  final OfflineMapRegionRecord region;
  final bool downloading;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  const _RegionTile({
    required this.region,
    required this.downloading,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final sizeMb = region.sizeBytes / (1024 * 1024);
    final statusColor = switch (region.status) {
      'ready' => AppTheme.green,
      'failed' => Colors.red.shade600,
      _ => const Color(0xFFB8860B),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.offline_pin_outlined, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    region.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  UiStrings.option(region.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: region.progress.clamp(0, 1),
              color: statusColor,
              backgroundColor: const Color(0xFFE8EEE7),
            ),
            const SizedBox(height: 8),
            Text(
              UiStrings.f('offline_region_detail', {
                'radius': region.radiusKm,
                'minZoom': region.minZoom,
                'maxZoom': region.maxZoom,
                'downloaded': region.downloadedTileCount,
                'total': region.tileCount,
                'size': LocaleText.number(sizeMb, fractionDigits: 1),
              }),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (region.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                region.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.red.shade600, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: downloading ? null : onUpdate,
                  icon: const Icon(Icons.update_rounded),
                  label: Text(
                    UiStrings.t(region.status == 'paused' ? 'resume' : 'update'),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: downloading ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(UiStrings.t('delete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TileSourceWarning extends StatelessWidget {
  final String message;

  const _TileSourceWarning(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7DF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8D7A1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A6B00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF6E4D00),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRegions extends StatelessWidget {
  const _EmptyRegions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E7DF)),
      ),
      child: Column(
        children: [
          const Icon(Icons.map_outlined, size: 42, color: AppTheme.textMuted),
          const SizedBox(height: 10),
          Text(
            UiStrings.t('no_downloaded_field_maps'),
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            UiStrings.t('no_downloaded_field_maps_detail'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
