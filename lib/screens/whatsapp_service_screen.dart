import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../models/grading/crop_option.dart';
import '../services/grain_grading_service.dart';
import '../utils/whatsapp_service_handoff.dart';
import '../utils/whatsapp_result_downloader.dart';

class WhatsappServiceScreen extends StatefulWidget {
  final String? token;

  const WhatsappServiceScreen({super.key, this.token});

  @override
  State<WhatsappServiceScreen> createState() => _WhatsappServiceScreenState();
}

class _WhatsappServiceScreenState extends State<WhatsappServiceScreen> {
  final _question = TextEditingController();
  final _picker = ImagePicker();
  final _gradingService = GrainGradingService();
  bool _loading = true;
  bool _submitting = false;
  String _service = '';
  String _language = 'en';
  Map<String, dynamic> _farm = const {};
  Map<String, dynamic> _task = const {};
  Map<String, dynamic>? _result;
  List<CropOption> _crops = const [];
  CropOption? _selectedCrop;
  CropVariety? _selectedVariety;
  bool _loadingCrops = false;
  bool _downloading = false;
  XFile? _grainPhoto;
  XFile? _moisturePhoto;
  final List<XFile> _taskPhotos = <XFile>[];
  Uri? _returnToWhatsapp;
  String? _error;

  String get _token =>
      widget.token?.trim() ?? Uri.base.queryParameters['token']?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_token.length < 32) {
      setState(() {
        _loading = false;
        _error = _copy(
          'This service link is invalid.',
          'यह सेवा लिंक मान्य नहीं है।',
          'ही सेवा लिंक वैध नाही.',
        );
      });
      return;
    }
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'whatsapp-service-link',
        body: {'token': _token, 'action': 'load'},
      );
      final data = _map(response.data);
      if (data['success'] == false) {
        throw StateError('${data['error'] ?? 'Could not open this service.'}');
      }
      setState(() {
        _loading = false;
        _service = '${data['service'] ?? ''}';
        _language = '${data['language'] ?? 'en'}';
        _farm = _map(data['farm']);
        _task = _map(data['task']);
        final result = data['result'];
        _result = result is Map ? _map(result) : null;
      });
      if (_service == 'grading' && _result == null) {
        await _loadCropCatalog();
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _error = _copy(
          'This service link has expired or was already used.',
          'यह सेवा लिंक समाप्त हो गई है या पहले इस्तेमाल हो चुकी है।',
          'ही सेवा लिंक कालबाह्य झाली आहे किंवा आधी वापरली आहे.',
        );
      });
    }
  }

  Future<void> _pickPhoto(bool moisture) async {
    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (!mounted || photo == null) return;
    setState(() {
      if (moisture) {
        _moisturePhoto = photo;
      } else {
        _grainPhoto = photo;
      }
    });
  }

  Future<void> _loadCropCatalog() async {
    setState(() => _loadingCrops = true);
    try {
      final crops = await _gradingService.fetchCrops();
      final loaded = crops.isEmpty ? _fallbackCrops : crops;
      final farmCrop = (_farm['crop']?.toString() ?? '').trim().toLowerCase();
      CropOption selected = loaded.first;
      if (farmCrop.isNotEmpty) {
        selected = loaded.firstWhere(
          (crop) => crop.label.toLowerCase().contains(farmCrop) ||
              farmCrop.contains(crop.label.toLowerCase()) ||
              crop.value.toLowerCase() == farmCrop ||
              crop.aliases.any((alias) => alias.toLowerCase() == farmCrop),
          orElse: () => loaded.first,
        );
      }
      if (!mounted) return;
      setState(() {
        _crops = loaded;
        _selectedCrop = selected;
        _selectedVariety = selected.varieties.isEmpty
            ? null
            : selected.varieties.first;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _crops = _fallbackCrops;
        _selectedCrop = _fallbackCrops.first;
        _selectedVariety = _fallbackCrops.first.varieties.first;
      });
    } finally {
      if (mounted) setState(() => _loadingCrops = false);
    }
  }

  static const List<CropOption> _fallbackCrops = [
    CropOption(
      value: 'finger_millets',
      label: 'Finger Millet (Ragi)',
      aliases: ['ragi', 'nachni'],
      varieties: [CropVariety(value: 'local', label: 'Local')],
    ),
  ];

  Future<void> _captureTaskPhoto() async {
    if (_taskPhotos.length >= 3) return;
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );
    if (!mounted || photo == null) return;
    setState(() => _taskPhotos.add(photo));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_service == 'ai' && _question.text.trim().isEmpty) {
      setState(
        () => _error = _copy(
          'Enter your farm question.',
          'अपने खेत का सवाल लिखें।',
          'तुमचा शेताचा प्रश्न लिहा.',
        ),
      );
      return;
    }
    if (_service == 'grading' &&
        (_grainPhoto == null ||
            _moisturePhoto == null ||
            _selectedCrop == null ||
            (_selectedCrop!.varieties.isNotEmpty && _selectedVariety == null))) {
      setState(
        () => _error = _copy(
          'Upload both photos before submitting.',
          'भेजने से पहले दोनों फोटो अपलोड करें।',
          'पाठवण्यापूर्वी दोन्ही फोटो अपलोड करा.',
        ),
      );
      return;
    }
    if (_service == 'daily_tasks' &&
        (_task['id'] == null || _taskPhotos.length < 3)) {
      setState(
        () => _error = _copy(
          'Capture three photos from different parts of the farm.',
          'खेत के अलग-अलग हिस्सों से तीन फोटो लें।',
          'शेताच्या वेगवेगळ्या भागांतून तीन फोटो घ्या.',
        ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{'token': _token, 'action': 'complete'};
      if (_service == 'ai') {
        body['question'] = _question.text.trim();
      } else if (_service == 'grading') {
        final grain = await _grainPhoto!.readAsBytes();
        final moisture = await _moisturePhoto!.readAsBytes();
        body['grainImageBase64'] = base64Encode(grain);
        body['moistureImageBase64'] = base64Encode(moisture);
        body['grainImageMimeType'] = _mimeType(_grainPhoto!.name);
        body['moistureImageMimeType'] = _mimeType(_moisturePhoto!.name);
        body['cropType'] = _selectedCrop?.value ?? '';
        body['cropVariety'] = _selectedVariety?.value ?? '';
      } else if (_service == 'daily_tasks') {
        body['taskId'] = _task['id'];
        body['taskPhotos'] = [
          for (final photo in _taskPhotos)
            {
              'base64': base64Encode(await photo.readAsBytes()),
              'mimeType': _mimeType(photo.name),
            },
        ];
      }
      final response = await Supabase.instance.client.functions.invoke(
        'whatsapp-service-link',
        body: body,
      );
      final data = _map(response.data);
      if (data['success'] == false) {
        throw StateError('${data['error'] ?? 'Could not save the result.'}');
      }
      setState(() {
        _result = _map(data['result']);
        _returnToWhatsapp = whatsappServiceHandoffUri(
          data['returnToWhatsappUrl']?.toString(),
        );
      });
      if (_returnToWhatsapp != null) await _openWhatsApp(_returnToWhatsapp!);
    } catch (_) {
      setState(
        () => _error = _copy(
          'Could not complete this service. Please try again.',
          'सेवा पूरी नहीं हो सकी। फिर कोशिश करें।',
          'सेवा पूर्ण होऊ शकली नाही. पुन्हा प्रयत्न करा.',
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openWhatsApp(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _service.isEmpty) {
      return _message(_error!);
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title),
            Text(
              _copy('GrainRight service', 'GrainRight सेवा', 'GrainRight सेवा'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Chip(
                avatar: const Icon(Icons.check_circle, size: 16),
                label: Text(_copy('Completed', 'पूरा हुआ', 'पूर्ण')), 
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: AppTheme.surface,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _farmHeaderCard(),
                if (_error != null) _errorBox(_error!),
                if (_result != null) ...[
                  _resultCard(),
                  const SizedBox(height: 20),
                ],
                if (_result == null && _service == 'ai') _aiForm(),
                if (_result == null && _service == 'grading') _gradingForm(),
                if (_result == null && _service == 'daily_tasks')
                  _dailyTaskForm(),
                if (_result != null && _returnToWhatsapp != null)
                  FilledButton.icon(
                    onPressed: () => _openWhatsApp(_returnToWhatsapp!),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(
                      _copy('Open WhatsApp', 'WhatsApp खोलें', 'WhatsApp उघडा'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _copy(
          'Ask your farm question',
          'अपने खेत का सवाल पूछें',
          'तुमचा शेताचा प्रश्न विचारा',
        ),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _question,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: _copy(
            'Example: Why are my leaves turning yellow?',
            'उदाहरण: मेरी पत्तियाँ पीली क्यों हो रही हैं?',
            'उदाहरण: माझी पाने पिवळी का होत आहेत?',
          ),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(
          _submitting
              ? _copy('Submitting…', 'भेज रहे हैं…', 'पाठवत आहे…')
              : _copy('Submit question', 'सवाल भेजें', 'प्रश्न पाठवा'),
        ),
      ),
    ],
  );

  Widget _gradingForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _copy(
          'Upload two clear photos',
          'दो साफ फोटो अपलोड करें',
          'दोन स्पष्ट फोटो अपलोड करा',
        ),
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      if (_loadingCrops)
        const LinearProgressIndicator(minHeight: 3)
      else ...[
        DropdownButtonFormField<CropOption>(
          initialValue: _selectedCrop,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _copy('Crop', 'फसल', 'पीक'),
            prefixIcon: const Icon(Icons.eco_outlined),
            isDense: true,
          ),
          items: [
            for (final crop in _crops)
              DropdownMenuItem(value: crop, child: Text(_cropLabel(crop))),
          ],
          onChanged: _submitting
              ? null
              : (crop) {
                  if (crop == null) return;
                  setState(() {
                    _selectedCrop = crop;
                    _selectedVariety = crop.varieties.isEmpty
                        ? null
                        : crop.varieties.first;
                  });
                },
        ),
        const SizedBox(height: 8),
        if ((_selectedCrop?.varieties ?? const []).isNotEmpty)
          DropdownButtonFormField<CropVariety>(
            key: ValueKey(_selectedCrop?.value),
            initialValue: _selectedVariety,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _copy('Variety', 'किस्म', 'वाण'),
              prefixIcon: const Icon(Icons.spa_outlined),
              isDense: true,
            ),
            items: [
              for (final variety in _selectedCrop!.varieties)
                DropdownMenuItem(
                  value: variety,
                  child: Text(_varietyLabel(variety)),
                ),
            ],
            onChanged: _submitting
                ? null
                : (variety) => setState(() => _selectedVariety = variety),
          ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: () => _pickPhoto(false),
        icon: const Icon(Icons.grain),
        label: Text(
          _grainPhoto == null
              ? _copy(
                  'Choose grain photo',
                  'अनाज की फोटो चुनें',
                  'धान्याचा फोटो निवडा',
                )
              : _grainPhoto!.name,
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => _pickPhoto(true),
        icon: const Icon(Icons.water_drop_outlined),
        label: Text(
          _moisturePhoto == null
              ? _copy(
                  'Choose moisture-meter photo',
                  'नमी मीटर की फोटो चुनें',
                  'ओलावा मीटरचा फोटो निवडा',
                )
              : _moisturePhoto!.name,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(
          _submitting
              ? _copy('Analysing…', 'विश्लेषण हो रहा है…', 'विश्लेषण सुरू आहे…')
              : _copy(
                  'Analyse and submit',
                  'विश्लेषण करके भेजें',
                  'विश्लेषण करून पाठवा',
                ),
        ),
      ),
    ],
  );

  Widget _dailyTaskForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _copy('Today’s farm task', 'आज का खेत काम', 'आजचे शेतकाम'),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        _task['title_key']?.toString() ??
            _copy('Field check', 'खेत निरीक्षण', 'शेत तपासणी'),
      ),
      if ((_task['description_key']?.toString() ?? '').trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_task['description_key'].toString()),
        ),
      const SizedBox(height: 16),
      Text(
        _copy(
          'Capture one clear photo from each of three different farm areas.',
          'खेत के तीन अलग-अलग हिस्सों से एक-एक साफ फोटो लें।',
          'शेताच्या तीन वेगवेगळ्या भागांतून प्रत्येकी एक स्पष्ट फोटो घ्या.',
        ),
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < 3; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: _submitting || index < _taskPhotos.length
                ? null
                : _captureTaskPhoto,
            icon: Icon(
              index < _taskPhotos.length
                  ? Icons.check_circle_outline
                  : Icons.camera_alt_outlined,
            ),
            label: Text(
              index < _taskPhotos.length
                  ? _copy(
                      'Photo ${index + 1} captured',
                      'फोटो ${index + 1} लिया गया',
                      'फोटो ${index + 1} घेतला',
                    )
                  : _copy(
                      'Take photo ${index + 1}',
                      'फोटो ${index + 1} लें',
                      'फोटो ${index + 1} घ्या',
                    ),
            ),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(
          _submitting
              ? _copy('Saving…', 'सेव हो रहा है…', 'सेव होत आहे…')
              : _copy(
                  'Save task evidence',
                  'काम का प्रमाण सेव करें',
                  'कामाचा पुरावा सेव करा',
                ),
        ),
      ),
    ],
  );

  Widget _farmHeaderCard() => Card(
    margin: EdgeInsets.zero,
    color: AppTheme.greenDark,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0x33FFFFFF),
            child: Icon(Icons.agriculture_outlined, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _farm['name']?.toString() ?? _copy('Selected farm', 'चुना हुआ खेत', 'निवडलेले शेत'),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                if (_farm['crop'] != null)
                  Text(
                    '${_farm['crop']}',
                    style: const TextStyle(color: Color(0xFFDDEAD5), fontSize: 14),
                  ),
                if (_farm['location_label'] != null)
                  Text(
                    '${_farm['location_label']}',
                    style: const TextStyle(color: Color(0xFFDDEAD5), fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _resultCard() {
    final sections = _resultSections(_result ?? const {});
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_outlined, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _copy('Full result', 'पूरा परिणाम', 'संपूर्ण निकाल'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final section in sections) _resultSection(section),
            const SizedBox(height: 2),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _downloading ? null : _downloadResult,
                icon: _downloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  _downloading
                      ? _copy('Preparing PDF…', 'PDF बन रहा है…', 'PDF तयार होत आहे…')
                      : _copy('Download PDF report', 'PDF रिपोर्ट डाउनलोड करें', 'PDF रिपोर्ट डाउनलोड करा'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultSection(_ResultSection section) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.label, style: const TextStyle(color: AppTheme.greenDark, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          SelectableText(section.value, style: const TextStyle(height: 1.3)),
        ],
      ),
    ),
  );

  List<_ResultSection> _resultSections(Map<String, dynamic> result) {
    final sections = <_ResultSection>[];
    void visit(String key, dynamic value, [int depth = 0]) {
      if (value == null || key.endsWith('_path') || key == 'success' || key == 'code') return;
      final label = _prettyKey(key);
      if (value is Map) {
        final entries = value.entries.toList();
        if (entries.isEmpty) return;
        if (depth == 0) {
          for (final entry in entries) {
            visit('${entry.key}', entry.value, depth + 1);
          }
        } else {
          final lines = <String>[];
          for (final entry in entries) {
            if (entry.key.toString().endsWith('_path')) {
              continue;
            }
            lines.add('${_prettyKey(entry.key.toString())}: ${_displayValue(entry.value)}');
          }
          if (lines.isNotEmpty) sections.add(_ResultSection(label, lines.join('\n')));
        }
      } else if (value is List) {
        final lines = value.map(_displayValue).where((item) => item.isNotEmpty).toList();
        if (lines.isNotEmpty) sections.add(_ResultSection(label, lines.map((item) => '• $item').join('\n')));
      } else {
        sections.add(_ResultSection(label, _displayValue(value)));
      }
    }
    for (final entry in result.entries) {
      visit(entry.key, entry.value);
    }
    return sections.isEmpty
        ? [_ResultSection(_copy('Result', 'परिणाम', 'निकाल'), _resultText)]
        : sections;
  }

  String _prettyKey(String key) => key
      .replaceAll(RegExp(r'([a-z])([A-Z])'), r'$1 $2')
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');

  String _displayValue(dynamic value) {
    if (value == null) return '—';
    if (value is Map) return value.entries.map((entry) => '${_prettyKey(entry.key.toString())}: ${_displayValue(entry.value)}').join(', ');
    if (value is List) return value.map(_displayValue).join(', ');
    if (value is bool) return value ? 'Yes' : 'No';
    return '$value';
  }

  String _cropLabel(CropOption crop) => crop.label;

  String _varietyLabel(CropVariety variety) => variety.label;

  Future<void> _downloadResult() async {
    final result = _result;
    if (result == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final document = pw.Document();
      final sections = _resultSections(result);
      document.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('GrainRight Grain Grading Report'),
            ),
            pw.Text('Farm: ${_farm['name'] ?? 'Selected farm'}'),
            if ((_farm['location_label']?.toString() ?? '').isNotEmpty)
              pw.Text('Location: ${_farm['location_label']}'),
            pw.Text('Crop: ${_selectedCrop?.label ?? _farm['crop'] ?? '-'}'),
            pw.Text('Variety: ${_selectedVariety?.label ?? _farm['variety'] ?? '-'}'),
            pw.SizedBox(height: 16),
            for (final section in sections)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
              border: pw.Border.all(color: const PdfColor(0.82, 0.88, 0.82)),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(section.label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(section.value),
                  ],
                ),
              ),
            pw.SizedBox(height: 8),
            pw.Text('Generated: ${DateTime.now().toLocal().toString()}'),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await document.save());
      await downloadWhatsappResult(bytes, 'grainright-grading-report.pdf');
    } catch (_) {
      if (mounted) {
        setState(() => _error = _copy(
              'The report could not be downloaded. Please try again.',
              'रिपोर्ट डाउनलोड नहीं हो सकी। फिर कोशिश करें।',
              'रिपोर्ट डाउनलोड होऊ शकली नाही. पुन्हा प्रयत्न करा.',
            ));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String get _resultText {
    final answer = _result?['answer'] ?? _map(_result?['data'])['answer'];
    if (answer != null) return '$answer';
    final grade = _result?['grade'] ?? _map(_result?['result'])['grade'];
    if (grade is Map) {
      return _copy(
        'Grade: ${grade['grade'] ?? grade['final_grade'] ?? 'Available'}',
        'ग्रेड: ${grade['grade'] ?? grade['final_grade'] ?? 'उपलब्ध'}',
        'ग्रेड: ${grade['grade'] ?? grade['final_grade'] ?? 'उपलब्ध'}',
      );
    }
    return _copy(
      'Service completed. Return to WhatsApp and send CONTINUE.',
      'सेवा पूरी हुई। WhatsApp पर लौटकर CONTINUE भेजें।',
      'सेवा पूर्ण झाली. WhatsApp वर परत जाऊन CONTINUE पाठवा.',
    );
  }

  Widget _message(String message) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    ),
  );
  Widget _errorBox(String message) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(message, style: const TextStyle(color: Colors.red)),
  );
  String get _title => _service == 'grading'
      ? _copy('Grain grading', 'अनाज ग्रेडिंग', 'धान्य ग्रेडिंग')
      : _service == 'daily_tasks'
      ? _copy('Daily farm task', 'दैनिक खेत काम', 'दैनंदिन शेतकाम')
      : _copy('AI farm chat', 'खेत AI चैट', 'शेत AI चॅट');
  String _copy(String en, String hi, String mr) => _language == 'hi'
      ? hi
      : _language == 'mr'
      ? mr
      : en;
  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  String _mimeType(String name) =>
      name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
}

class _ResultSection {
  final String label;
  final String value;

  const _ResultSection(this.label, this.value);
}
