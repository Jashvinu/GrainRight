import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../models/satellite/farm_summary_model.dart';
import '../utils/whatsapp_boundary_handoff.dart';
import '../widgets/satellite/satellite_map_view.dart';
import 'boundary_polygon_screen.dart';

class WhatsappFarmBoundaryScreen extends StatefulWidget {
  final String? token;

  const WhatsappFarmBoundaryScreen({super.key, this.token});

  @override
  State<WhatsappFarmBoundaryScreen> createState() =>
      _WhatsappFarmBoundaryScreenState();
}

class _WhatsappFarmBoundaryScreenState
    extends State<WhatsappFarmBoundaryScreen> {
  bool _saving = false;
  bool _saved = false;
  bool _refreshingSummary = false;
  bool _setupComplete = false;
  Map<String, dynamic> _farm = const {};
  FarmerFarmSummary? _monitoring;
  String? _summaryError;
  Uri? _returnToWhatsapp;

  String get _token =>
      widget.token?.trim() ?? Get.parameters['token']?.trim() ?? '';

  Future<void> _saveBoundary(List<List<double>> polygon) async {
    if (_saving || _saved) return;
    if (_token.length < 32) {
      throw StateError(
        _text(
          en: 'This WhatsApp boundary link is invalid.',
          hi: 'यह WhatsApp सीमा लिंक मान्य नहीं है।',
          mr: 'ही WhatsApp सीमा लिंक वैध नाही.',
        ),
      );
    }
    setState(() => _saving = true);
    try {
      final geometry = {
        'type': 'Polygon',
        'coordinates': [polygon],
      };
      final response = await Supabase.instance.client.functions.invoke(
        'whatsapp-onboarding-boundary',
        body: {'token': _token, 'geometry': geometry},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      if (data['success'] == false) {
        throw StateError('${data['error'] ?? 'Could not save boundary.'}');
      }
      if (!mounted) return;
      final returnToWhatsapp = whatsappBoundaryHandoffUri(
        data['returnToWhatsappUrl']?.toString(),
      );
      setState(() {
        _saved = true;
        _applySummaryData(data);
        _returnToWhatsapp = returnToWhatsapp;
      });
      if (returnToWhatsapp != null) {
        await _openWhatsApp(returnToWhatsapp);
      }
    } catch (error, stack) {
      debugPrint('[WhatsappFarmBoundaryScreen._saveBoundary] $error');
      debugPrintStack(stackTrace: stack);
      final raw = '$error'.toLowerCase();
      if (raw.contains('expired') || raw.contains('already used')) {
        throw StateError(
          _text(
            en: 'This boundary link has expired or was already used. Return to WhatsApp and send CONTINUE to request a fresh link.',
            hi: 'यह सीमा लिंक समाप्त हो गई है या पहले इस्तेमाल हो चुकी है। नया लिंक लेने के लिए WhatsApp पर CONTINUE भेजें।',
            mr: 'ही सीमा लिंक कालबाह्य झाली आहे किंवा आधी वापरली आहे. नवीन लिंकसाठी WhatsApp वर CONTINUE पाठवा.',
          ),
        );
      }
      throw StateError(
        _text(
          en: 'Boundary could not be saved. Check your internet and try again.',
          hi: 'सीमा सेव नहीं हो सकी। इंटरनेट जांचें और फिर कोशिश करें।',
          mr: 'सीमा सेव होऊ शकली नाही. इंटरनेट तपासा आणि पुन्हा प्रयत्न करा.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openWhatsApp(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stack) {
      debugPrint('[WhatsappFarmBoundaryScreen._openWhatsApp] $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> _refreshSummary() async {
    if (_refreshingSummary) return;
    setState(() {
      _refreshingSummary = true;
      _summaryError = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'whatsapp-onboarding-boundary',
        body: {'token': _token, 'action': 'refresh'},
      );
      final data = _map(response.data);
      if (data['success'] == false) {
        throw StateError('${data['error'] ?? 'Could not refresh farm data.'}');
      }
      if (!mounted) return;
      setState(() => _applySummaryData(data));
    } catch (error, stack) {
      debugPrint('[WhatsappFarmBoundaryScreen._refreshSummary] $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        setState(() {
          _summaryError = _text(
            en: 'Farm data could not be refreshed. Complete setup in WhatsApp and try again.',
            hi: 'खेत का डेटा रीफ्रेश नहीं हो सका। WhatsApp में सेटअप पूरा करके फिर कोशिश करें।',
            mr: 'शेताचा डेटा रिफ्रेश होऊ शकला नाही. WhatsApp मध्ये सेटअप पूर्ण करून पुन्हा प्रयत्न करा.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _refreshingSummary = false);
    }
  }

  void _applySummaryData(Map<String, dynamic> data) {
    final rawFarm = data['farm'];
    if (rawFarm is Map) {
      _farm = Map<String, dynamic>.from(rawFarm);
    }
    final rawSummary = data['summary'];
    _monitoring = rawSummary is Map
        ? FarmerFarmSummary.fromJson(Map<String, dynamic>.from(rawSummary))
        : null;
    _setupComplete = data['status'] == 'completed' || _monitoring != null;
  }

  @override
  Widget build(BuildContext context) {
    if (_saved) return _farmSummary();
    if (_token.length < 32) return _invalidLink();
    return BoundaryPolygonScreen(onBoundaryConfirmed: _saveBoundary);
  }

  Widget _invalidLink() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _text(
            en: 'Mark your farm boundary',
            hi: 'खेत की सीमा बनाएं',
            mr: 'शेताची सीमा काढा',
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _text(
                en: 'This WhatsApp boundary link is invalid or incomplete. Return to WhatsApp and request a new link.',
                hi: 'यह WhatsApp सीमा लिंक मान्य नहीं है। WhatsApp पर वापस जाकर नया लिंक लें।',
                mr: 'ही WhatsApp सीमा लिंक वैध नाही. WhatsApp वर परत जाऊन नवीन लिंक घ्या.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _farmSummary() {
    final polygon = _polygonFromGeometry(_farm['geometry']);
    final center = _centerForFarm(polygon);
    return Scaffold(
      appBar: AppBar(
        title: Text(_text(en: 'Your farm', hi: 'आपका खेत', mr: 'तुमचे शेत')),
        actions: [
          Tooltip(
            message: _text(
              en: 'Refresh farm data',
              hi: 'डेटा रीफ्रेश करें',
              mr: 'डेटा रिफ्रेश करा',
            ),
            child: IconButton(
              key: const Key('whatsapp_farm_refresh'),
              onPressed: _refreshingSummary ? null : _refreshSummary,
              icon: _refreshingSummary
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSummary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _farmHeader(),
            if (_farmDetailText().isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionCard(
                icon: Icons.agriculture_outlined,
                color: AppTheme.greenDark,
                title: _text(
                  en: 'Farm details',
                  hi: 'खेत का विवरण',
                  mr: 'शेताचा तपशील',
                ),
                body: _farmDetailText(),
              ),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: SatelliteMapView(
                key: const Key('whatsapp_saved_farm_map'),
                height: 360,
                farmPolygon: polygon,
                center: center,
                heatCircles: _monitoring == null
                    ? null
                    : _riskCircles(_monitoring!),
                showZoomControls: true,
                showReferenceLabels: false,
                satelliteOnly: true,
              ),
            ),
            const SizedBox(height: 14),
            if (_summaryError != null)
              _messageBanner(_summaryError!, isError: true),
            if (!_setupComplete) _setupPendingCard(),
            if (_setupComplete && _monitoring == null) _monitoringEmptyCard(),
            if (_monitoring != null) _monitoringSection(_monitoring!),
            const SizedBox(height: 12),
            _whatsappContinueCard(),
          ],
        ),
      ),
    );
  }

  Widget _farmHeader() {
    final name = '${_farm['name'] ?? ''}'.trim();
    final location = '${_farm['location_label'] ?? ''}'.trim();
    final acres = _number(_farm['area_acres']);
    final hectares = _number(_farm['area_hectares']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty
              ? _text(
                  en: 'Farm boundary saved',
                  hi: 'खेत की सीमा सेव हो गई',
                  mr: 'शेताची सीमा सेव झाली',
                )
              : name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        if (location.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 18,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  location,
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statChip(
              Icons.square_foot,
              acres == null ? '--' : '${acres.toStringAsFixed(2)} ac',
              _text(en: 'Area', hi: 'क्षेत्रफल', mr: 'क्षेत्रफळ'),
            ),
            _statChip(
              Icons.straighten,
              hectares == null ? '--' : '${hectares.toStringAsFixed(2)} ha',
              _text(
                en: 'Measured boundary',
                hi: 'मापी गई सीमा',
                mr: 'मोजलेली सीमा',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.greenDark),
          const SizedBox(width: 7),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _setupPendingCard() {
    return _sectionCard(
      icon: Icons.sync_rounded,
      color: AppTheme.weather,
      title: _text(
        en: 'Finish setup in WhatsApp',
        hi: 'WhatsApp में सेटअप पूरा करें',
        mr: 'WhatsApp मध्ये सेटअप पूर्ण करा',
      ),
      body: _text(
        en: 'Your boundary is saved. Complete the remaining farm questions in WhatsApp, then tap Refresh here to load satellite monitoring.',
        hi: 'आपकी खेत सीमा सेव है। WhatsApp में बाकी खेत के सवाल पूरे करें, फिर satellite monitoring लोड करने के लिए यहां Refresh दबाएं।',
        mr: 'तुमची शेत सीमा सेव झाली आहे. WhatsApp मध्ये उरलेले शेत प्रश्न पूर्ण करा आणि satellite monitoring साठी येथे Refresh दाबा.',
      ),
    );
  }

  Widget _monitoringEmptyCard() {
    return _sectionCard(
      icon: Icons.satellite_alt_outlined,
      color: AppTheme.monitoring,
      title: _text(
        en: 'Satellite monitoring',
        hi: 'Satellite monitoring',
        mr: 'Satellite monitoring',
      ),
      body: _text(
        en: 'The farm is ready, but no saved satellite scan is available yet. Tap Refresh after the next scan.',
        hi: 'खेत तैयार है, लेकिन अभी कोई saved satellite scan उपलब्ध नहीं है। अगली scan के बाद Refresh दबाएं।',
        mr: 'शेत तयार आहे, पण अजून saved satellite scan उपलब्ध नाही. पुढील scan नंतर Refresh दाबा.',
      ),
    );
  }

  Widget _monitoringSection(FarmerFarmSummary summary) {
    final disease = summary.diseaseScreen;
    final metricItems = [
      _metricTile(
        _text(en: 'Crop health', hi: 'फसल स्वास्थ्य', mr: 'पीक आरोग्य'),
        summary.cropHealth?.value,
        AppTheme.success,
      ),
      _metricTile(
        _text(en: 'Moisture', hi: 'नमी', mr: 'ओलावा'),
        summary.waterLevel?.value,
        AppTheme.weather,
      ),
      _metricTile(
        _text(
          en: 'High-risk cells',
          hi: 'अधिक जोखिम वाले cell',
          mr: 'जास्त जोखीम cell',
        ),
        disease.highRiskCells.toDouble(),
        AppTheme.warning,
        percentage: false,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text(
            en: 'Satellite monitoring',
            hi: 'Satellite monitoring',
            mr: 'Satellite monitoring',
          ),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (summary.lastUpdate == null)
          _sectionCard(
            icon: Icons.satellite_alt_outlined,
            color: AppTheme.monitoring,
            title: _text(
              en: 'Satellite monitoring is ready',
              hi: 'Satellite monitoring तैयार है',
              mr: 'Satellite monitoring तयार आहे',
            ),
            body: _text(
              en: 'Your farm details are saved. The first satellite scan will add crop health, moisture, risk cells, and more suggestions here.',
              hi: 'आपके खेत का विवरण सेव है। पहली satellite scan यहां crop health, moisture, risk cells और अधिक सुझाव जोड़ेगी।',
              mr: 'तुमच्या शेताचा तपशील सेव आहे. पहिल्या satellite scan नंतर येथे crop health, moisture, risk cells आणि अधिक सूचना दिसतील.',
            ),
          ),
        if (summary.lastUpdate == null) const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: metricItems),
        const SizedBox(height: 12),
        if (disease.riskCells.isNotEmpty)
          _sectionCard(
            icon: Icons.warning_amber_rounded,
            color: AppTheme.warning,
            title: _text(
              en: 'Field cells to check',
              hi: 'जांचने वाले खेत cell',
              mr: 'तपासायचे शेत cell',
            ),
            body: _text(
              en: '${disease.highRiskCells} high-risk cell(s) were found in the latest saved scan. Check the highlighted points on the map and inspect those areas in the field.',
              hi: 'नवीनतम saved scan में ${disease.highRiskCells} high-risk cell मिले। map पर दिखे points की खेत में जांच करें।',
              mr: 'नवीनतम saved scan मध्ये ${disease.highRiskCells} high-risk cell आढळले. map वरील points शेतात तपासा.',
            ),
          )
        else
          _sectionCard(
            icon: Icons.check_circle_outline,
            color: AppTheme.success,
            title: _text(
              en: 'No high-risk cells in the latest scan',
              hi: 'नवीनतम scan में high-risk cell नहीं',
              mr: 'नवीनतम scan मध्ये high-risk cell नाहीत',
            ),
            body: _text(
              en: 'Continue regular field checks and refresh after the next saved satellite scan.',
              hi: 'नियमित खेत जांच जारी रखें और अगली saved satellite scan के बाद Refresh करें।',
              mr: 'नियमित शेत तपासणी सुरू ठेवा आणि पुढील saved satellite scan नंतर Refresh करा.',
            ),
          ),
        const SizedBox(height: 12),
        _suggestionCard(summary),
      ],
    );
  }

  Widget _metricTile(
    String label,
    double? value,
    Color color, {
    bool percentage = true,
  }) {
    final display = value == null
        ? '--'
        : percentage
        ? '${(value * 100).toStringAsFixed(0)}%'
        : value.toStringAsFixed(0);
    return Container(
      constraints: const BoxConstraints(minWidth: 126),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            display,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionCard(FarmerFarmSummary summary) {
    final recommendation = summary.weatherContext?['recommendation'];
    final title = recommendation is Map
        ? '${recommendation['title'] ?? recommendation['label'] ?? ''}'.trim()
        : '';
    final detail = recommendation is Map
        ? '${recommendation['detail'] ?? recommendation['summary'] ?? recommendation['recommendation'] ?? ''}'
              .trim()
        : '';
    final suggestion = detail.isNotEmpty
        ? detail
        : summary.diseaseScreen.highRiskCells > 0
        ? _text(
            en: 'Inspect the highlighted high-risk cells in the field and send a photo in WhatsApp if you see leaf damage.',
            hi: 'map पर दिखे high-risk cell की खेत में जांच करें और पत्तियों को नुकसान दिखे तो WhatsApp पर photo भेजें।',
            mr: 'map वरील high-risk cell शेतात तपासा आणि पानांचे नुकसान दिसल्यास WhatsApp वर photo पाठवा.',
          )
        : _text(
            en: 'Continue regular field checks and refresh after the next satellite scan.',
            hi: 'नियमित खेत जांच जारी रखें और अगली satellite scan के बाद Refresh करें।',
            mr: 'नियमित शेत तपासणी सुरू ठेवा आणि पुढील satellite scan नंतर Refresh करा.',
          );
    return _sectionCard(
      icon: Icons.lightbulb_outline,
      color: AppTheme.gold,
      title: title.isEmpty
          ? _text(
              en: 'Suggested next step',
              hi: 'अगला सुझाव',
              mr: 'पुढील सूचना',
            )
          : title,
      body: suggestion,
    );
  }

  Widget _whatsappContinueCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_returnToWhatsapp != null)
          FilledButton.icon(
            onPressed: () => _openWhatsApp(_returnToWhatsapp!),
            icon: const Icon(Icons.chat_outlined),
            label: Text(
              _text(
                en: 'Continue in WhatsApp',
                hi: 'WhatsApp में जारी रखें',
                mr: 'WhatsApp मध्ये पुढे जा',
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          _text(
            en: 'This page is read-only after the boundary is saved.',
            hi: 'सीमा सेव होने के बाद यह page केवल देखने के लिए है।',
            mr: 'सीमा सेव केल्यानंतर हे page फक्त पाहण्यासाठी आहे.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
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

  List<CircleMarker> _riskCircles(FarmerFarmSummary summary) {
    return summary.diseaseScreen.riskCells
        .where((cell) => cell.hasLocation)
        .map((cell) {
          final highRisk = cell.compositeRisk >= 0.55;
          final color = highRisk ? AppTheme.danger : AppTheme.warning;
          return CircleMarker(
            point: LatLng(cell.lat, cell.lng),
            radius: highRisk ? 28 : 22,
            useRadiusInMeter: true,
            color: color.withValues(alpha: 0.28),
            borderColor: color,
            borderStrokeWidth: 1.5,
          );
        })
        .toList(growable: false);
  }

  Widget _messageBanner(String message, {required bool isError}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _sectionCard(
        icon: isError ? Icons.error_outline : Icons.info_outline,
        color: isError ? AppTheme.error : AppTheme.weather,
        title: isError
            ? _text(
                en: 'Refresh failed',
                hi: 'रीफ्रेश विफल',
                mr: 'रिफ्रेश अयशस्वी',
              )
            : _text(en: 'Notice', hi: 'सूचना', mr: 'सूचना'),
        body: message,
      ),
    );
  }

  List<LatLng> _polygonFromGeometry(dynamic raw) {
    if (raw is! Map) return const [];
    final coordinates = raw['coordinates'];
    if (coordinates is! List ||
        coordinates.isEmpty ||
        coordinates.first is! List) {
      return const [];
    }
    final ring = coordinates.first as List;
    return ring
        .whereType<List>()
        .where((point) => point.length >= 2)
        .map((point) {
          return LatLng(_number(point[1]) ?? 0, _number(point[0]) ?? 0);
        })
        .where((point) => point.latitude != 0 || point.longitude != 0)
        .toList(growable: false);
  }

  LatLng? _centerForFarm(List<LatLng> polygon) {
    final latitude = _number(_farm['centroid_latitude']);
    final longitude = _number(_farm['centroid_longitude']);
    if (latitude != null && longitude != null) {
      return LatLng(latitude, longitude);
    }
    if (polygon.isEmpty) return null;
    return LatLng(
      polygon.map((point) => point.latitude).reduce((a, b) => a + b) /
          polygon.length,
      polygon.map((point) => point.longitude).reduce((a, b) => a + b) /
          polygon.length,
    );
  }

  double? _number(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse('${raw ?? ''}'.trim());
  }

  Map<String, dynamic> _map(dynamic raw) {
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  String _text({required String en, required String hi, required String mr}) {
    return switch (Localizations.localeOf(context).languageCode) {
      'hi' => hi,
      'mr' => mr,
      _ => en,
    };
  }

  String _farmDetailText() {
    final labels = <String, String>{
      'crop': _text(en: 'Crop', hi: 'फसल', mr: 'पीक'),
      'variety': _text(en: 'Variety', hi: 'किस्म', mr: 'वाण'),
      'season': _text(en: 'Season', hi: 'मौसम', mr: 'हंगाम'),
      'irrigation': _text(en: 'Irrigation', hi: 'सिंचाई', mr: 'सिंचन'),
      'soil_type': _text(en: 'Soil', hi: 'मिट्टी', mr: 'माती'),
      'ownership_type': _text(en: 'Ownership', hi: 'स्वामित्व', mr: 'मालकी'),
      'seed_source': _text(
        en: 'Seed source',
        hi: 'बीज स्रोत',
        mr: 'बियाणे स्रोत',
      ),
      'harvest_intent': _text(
        en: 'Harvest use',
        hi: 'कटाई उपयोग',
        mr: 'कापणीचा उपयोग',
      ),
      'sowing_date': _text(
        en: 'Sowing date',
        hi: 'बुवाई तारीख',
        mr: 'पेरणी तारीख',
      ),
    };
    return labels.entries
        .map((entry) {
          final value = '${_farm[entry.key] ?? ''}'.trim();
          return value.isEmpty ? '' : '${entry.value}: $value';
        })
        .where((line) => line.isNotEmpty)
        .join('\n');
  }
}
