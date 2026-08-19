import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
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
  bool _openingMap = false;
  bool _saved = false;
  String? _error;

  String get _token =>
      widget.token?.trim() ?? Get.parameters['token']?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _drawAndSave();
    });
  }

  Future<void> _drawAndSave() async {
    if (_saving || _openingMap || _saved) return;
    if (_token.length < 32) {
      setState(() => _error = 'This WhatsApp boundary link is invalid.');
      return;
    }
    setState(() {
      _openingMap = true;
      _error = null;
    });
    final polygon = await Get.to<List<List<double>>>(
      () => const BoundaryPolygonScreen(),
    );
    if (!mounted) return;
    setState(() => _openingMap = false);
    if (polygon == null || polygon.length < 4) return;

    setState(() {
      _saving = true;
      _error = null;
    });
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
      setState(() => _saved = true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst('StateError: ', ''),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mark your farm boundary')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _saved ? _success() : _form(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.landscape_outlined, size: 56, color: AppTheme.green),
        const SizedBox(height: 18),
        const Text(
          'Draw the same farm boundary used by GrainRight.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          'The boundary map is opening. Mark at least three corners, save the polygon, then return to WhatsApp and send CONTINUE.',
          textAlign: TextAlign.center,
        ),
        if (_error != null) ...[
          const SizedBox(height: 18),
          Text(_error!, style: const TextStyle(color: AppTheme.error)),
        ],
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _saving ? null : _drawAndSave,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.edit_location_alt_outlined),
          label: Text(
            _saving
                ? 'Saving boundary...'
                : _openingMap
                ? 'Opening boundary map...'
                : 'Open boundary map',
          ),
        ),
      ],
    );
  }

  Widget _success() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline, size: 64, color: AppTheme.green),
        const SizedBox(height: 18),
        const Text(
          'Boundary saved',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          'Return to WhatsApp and send CONTINUE. GrainRight will ask the remaining farm questions there.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        OutlinedButton(
          onPressed: () => Get.back(),
          child: Text(UiStrings.t('close')),
        ),
      ],
    );
  }
}
