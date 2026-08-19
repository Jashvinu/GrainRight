import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _saved = false;

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
      setState(() => _saved = true);
    } catch (error, stack) {
      debugPrint('[WhatsappFarmBoundaryScreen._saveBoundary] $error');
      debugPrintStack(stackTrace: stack);
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

  @override
  Widget build(BuildContext context) {
    if (_saved) return _success();
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

  Widget _success() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _text(
            en: 'Boundary saved',
            hi: 'सीमा सेव हो गई',
            mr: 'सीमा सेव झाली',
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: AppTheme.green,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _text(
                      en: 'Boundary saved',
                      hi: 'सीमा सेव हो गई',
                      mr: 'सीमा सेव झाली',
                    ),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _text(
                      en: 'Return to WhatsApp and send CONTINUE. GrainRight will ask the next farm question there.',
                      hi: 'WhatsApp पर वापस जाकर CONTINUE भेजें। GrainRight अगला खेत प्रश्न वहीं पूछेगा।',
                      mr: 'WhatsApp वर परत जाऊन CONTINUE पाठवा. GrainRight पुढील शेताचा प्रश्न तिथेच विचारेल.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _text({required String en, required String hi, required String mr}) {
    return switch (Localizations.localeOf(context).languageCode) {
      'hi' => hi,
      'mr' => mr,
      _ => en,
    };
  }
}
