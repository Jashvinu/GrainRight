import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../services/local_app_database.dart';
import '../services/offline_map_service.dart';

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
  StreamSubscription<OfflineMapDownloadProgress>? _downloadSubscription;

  List<OfflinePlacePrediction> _predictions = const [];
  List<OfflineMapRegionRecord> _regions = const [];
  OfflinePlaceResult? _selectedPlace;
  OfflineMapDownloadProgress? _progress;
  bool _searching = false;
  bool _resolving = false;
  bool _downloading = false;
  String? _searchError;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _downloadSubscription?.cancel();
    _searchController.dispose();
    _radiusController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    final regions = await _service.listRegions();
    if (mounted) setState(() => _regions = regions);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = value.trim();
      if (query.length < 2) {
        if (mounted) {
          setState(() {
            _predictions = const [];
            _searchError = null;
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
        if (!mounted) return;
        setState(() => _predictions = predictions);
      } catch (e) {
        if (!mounted) return;
        setState(() => _searchError = _friendlyError(e));
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _selectPrediction(OfflinePlacePrediction prediction) async {
    setState(() {
      _resolving = true;
      _searchError = null;
    });
    try {
      final place = await _service.resolvePrediction(prediction);
      if (!mounted) return;
      if (place == null) {
        setState(() => _searchError = 'Could not load that place.');
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
      address: 'Stored offline region',
      latitude: region.centerLat,
      longitude: region.centerLng,
    );
    await _downloadRegion(
      place,
      radiusKm: region.radiusKm,
      minZoom: region.minZoom,
      maxZoom: region.maxZoom,
    );
  }

  Future<void> _downloadRegion(
    OfflinePlaceResult place, {
    double? radiusKm,
    int minZoom = OfflineMapService.defaultMinZoom,
    int maxZoom = OfflineMapService.defaultMaxZoom,
  }) async {
    final radius =
        radiusKm ?? double.tryParse(_radiusController.text.trim()) ?? 15;
    setState(() {
      _downloading = true;
      _downloadError = null;
      _progress = null;
    });
    await _downloadSubscription?.cancel();
    _downloadSubscription = _service
        .downloadRegion(
          place: place,
          radiusKm: max(1, min(30, radius.toDouble())),
          minZoom: minZoom,
          maxZoom: maxZoom,
        )
        .listen(
          (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _downloadError = _friendlyError(error);
                _downloading = false;
              });
              _loadRegions();
            }
          },
          onDone: () {
            if (mounted) {
              setState(() => _downloading = false);
              _loadRegions();
            }
          },
          cancelOnError: true,
        );
  }

  Future<void> _deleteRegion(OfflineMapRegionRecord region) async {
    await _service.deleteRegion(region);
    await _loadRegions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${region.label} offline map')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canDownload = _service.hasOfflineTileSource;

    return Scaffold(
      appBar: AppBar(title: const Text('Offline Maps')),
      body: RefreshIndicator(
        color: AppTheme.green,
        onRefresh: _loadRegions,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            if (!canDownload) const _TileSourceWarning(),
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
              sourceLabel: _service.offlineTileSourceLabel,
              onChanged: _onSearchChanged,
              onSelect: _selectPrediction,
              onDownload: _downloadSelected,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Stored Regions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.greenDark,
                    ),
                  ),
                ),
                Text(
                  '${_regions.length}',
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
    if (text.contains('OFFLINE_TILE_URL_TEMPLATE')) {
      return 'Set OFFLINE_TILE_URL_TEMPLATE to your licensed/self-hosted tile endpoint.';
    }
    if (text.length <= 160) return text;
    return '${text.substring(0, 160)}...';
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E7DF)),
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
                labelText: 'Search village or field area',
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
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE6ECE5)),
                  borderRadius: BorderRadius.circular(8),
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
                      decoration: const InputDecoration(
                        labelText: 'Radius km',
                        prefixIcon: Icon(Icons.radio_button_unchecked_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Zoom 10-16. Satellite remains online-only.',
                      style: TextStyle(
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
                label: Text(downloading ? 'Downloading' : 'Download Map'),
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
                '${progress!.downloadedTiles}/${progress!.totalTiles} tiles from $sourceLabel',
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
                    '${place.latitude.toStringAsFixed(5)}, ${place.longitude.toStringAsFixed(5)}',
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
                  region.status.toUpperCase(),
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
              '${region.radiusKm.toStringAsFixed(0)} km radius, zoom ${region.minZoom}-${region.maxZoom}, ${region.downloadedTileCount}/${region.tileCount} tiles, ${sizeMb.toStringAsFixed(1)} MB',
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
                  label: const Text('Update'),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: downloading ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
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
  const _TileSourceWarning();

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
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFF9A6B00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline download needs OFFLINE_TILE_URL_TEMPLATE set to a licensed or self-hosted India tile endpoint. Google satellite and public OSM tiles are not bulk cached.',
              style: TextStyle(
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
      child: const Column(
        children: [
          Icon(Icons.map_outlined, size: 42, color: AppTheme.textMuted),
          SizedBox(height: 10),
          Text(
            'No downloaded maps yet',
            style: TextStyle(
              color: AppTheme.greenDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Search a village or field area while online, then download the surrounding map for field use.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
