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
  Map<String, dynamic> _farmer = const {};
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
  Uint8List? _grainPhotoBytes;
  Uint8List? _moisturePhotoBytes;
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
        _farmer = _map(data['farmer']);
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

  Future<void> _pickPhoto(bool moisture, ImageSource source) async {
    final photo = await _picker.pickImage(source: source, imageQuality: 88);
    if (!mounted || photo == null) return;
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (moisture) {
        _moisturePhoto = photo;
        _moisturePhotoBytes = bytes;
      } else {
        _grainPhoto = photo;
        _grainPhotoBytes = bytes;
      }
    });
  }

  Future<void> _removePhoto(bool moisture) async {
    setState(() {
      if (moisture) {
        _moisturePhoto = null;
        _moisturePhotoBytes = null;
      } else {
        _grainPhoto = null;
        _grainPhotoBytes = null;
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
          (crop) =>
              crop.label.toLowerCase().contains(farmCrop) ||
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
            (_selectedCrop!.varieties.isNotEmpty &&
                _selectedVariety == null))) {
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
        final grain = _grainPhotoBytes ?? await _grainPhoto!.readAsBytes();
        final moisture =
            _moisturePhotoBytes ?? await _moisturePhoto!.readAsBytes();
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
                        _copy(
                          'Open WhatsApp',
                          'WhatsApp खोलें',
                          'WhatsApp उघडा',
                        ),
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
      _gradingIntroCard(),
      const SizedBox(height: 14),
      _gradingStepTitle(
        '1',
        _copy(
          'Select crop and variety',
          'फसल और किस्म चुनें',
          'पीक आणि वाण निवडा',
        ),
      ),
      const SizedBox(height: 8),
      if (_loadingCrops)
        const LinearProgressIndicator(minHeight: 3)
      else
        _cropSelectionCard(),
      const SizedBox(height: 16),
      _gradingStepTitle(
        '2',
        _copy(
          'Add two clear photos',
          'दो साफ फोटो जोड़ें',
          'दोन स्पष्ट फोटो जोडा',
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _copy(
          'Use the camera or choose a photo from your phone.',
          'कैमरा इस्तेमाल करें या फोन से फोटो चुनें।',
          'कॅमेरा वापरा किंवा फोनमधून फोटो निवडा.',
        ),
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
      ),
      const SizedBox(height: 10),
      _photoCaptureCard(
        moisture: false,
        title: _copy('Grain sample', 'अनाज का नमूना', 'धान्याचा नमुना'),
        subtitle: _copy(
          'Spread a small sample in good light.',
          'थोड़ा अनाज अच्छी रोशनी में फैलाएँ।',
          'थोडे धान्य चांगल्या प्रकाशात पसरवा.',
        ),
        icon: Icons.grain_outlined,
      ),
      const SizedBox(height: 10),
      _photoCaptureCard(
        moisture: true,
        title: _copy(
          'Moisture-meter reading',
          'नमी मीटर की रीडिंग',
          'ओलावा मीटरचे मोजमाप',
        ),
        subtitle: _copy(
          'Keep the meter reading visible and sharp.',
          'मीटर की रीडिंग साफ और दिखाई देने वाली रखें।',
          'मीटरचे मोजमाप स्पष्ट आणि दिसेल असे ठेवा.',
        ),
        icon: Icons.water_drop_outlined,
      ),
      const SizedBox(height: 12),
      _photoProgress(),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _submitting ? null : _submit,
        icon: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.auto_awesome_outlined),
        label: Text(
          _submitting
              ? _copy('Analysing…', 'विश्लेषण हो रहा है…', 'विश्लेषण सुरू आहे…')
              : _copy(
                  'Analyse grain quality',
                  'अनाज की गुणवत्ता जाँचें',
                  'धान्याची गुणवत्ता तपासा',
                ),
        ),
      ),
    ],
  );

  Widget _gradingIntroCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppTheme.greenDark, AppTheme.green],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 24,
          backgroundColor: Color(0x2EFFFFFF),
          child: Icon(Icons.assessment_outlined, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _copy(
                  'Check your grain quality',
                  'अपने अनाज की गुणवत्ता जाँचें',
                  'तुमच्या धान्याची गुणवत्ता तपासा',
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _copy(
                  'Choose the crop, add two photos, and get a simple result.',
                  'फसल चुनें, दो फोटो जोड़ें और आसान परिणाम पाएँ।',
                  'पीक निवडा, दोन फोटो जोडा आणि सोपा निकाल मिळवा.',
                ),
                style: const TextStyle(color: Colors.white70, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _gradingStepTitle(String number, String title) => Row(
    children: [
      CircleAvatar(
        radius: 13,
        backgroundColor: AppTheme.greenPale,
        child: Text(
          number,
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _cropSelectionCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      border: Border.all(color: const Color(0xFFE2EBDD)),
    ),
    child: Column(
      children: [
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
        if ((_selectedCrop?.varieties ?? const []).isNotEmpty) ...[
          const SizedBox(height: 10),
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
        ],
      ],
    ),
  );

  Widget _photoCaptureCard({
    required bool moisture,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final photo = moisture ? _moisturePhoto : _grainPhoto;
    final bytes = moisture ? _moisturePhotoBytes : _grainPhotoBytes;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: photo == null ? const Color(0xFFE2EBDD) : AppTheme.green,
          width: photo == null ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.greenDark, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (photo != null)
                const Icon(Icons.check_circle, color: AppTheme.green, size: 20),
            ],
          ),
          if (bytes != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              child: Image.memory(
                bytes,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              photo?.name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _pickPhoto(moisture, ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(_copy('Take photo', 'कैमरा', 'कॅमेरा')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _pickPhoto(moisture, ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(_copy('Choose', 'चुनें', 'निवडा')),
                ),
              ),
              if (photo != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _copy('Remove photo', 'फोटो हटाएँ', 'फोटो काढा'),
                  onPressed: _submitting ? null : () => _removePhoto(moisture),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoProgress() {
    final count =
        (_grainPhoto != null ? 1 : 0) + (_moisturePhoto != null ? 1 : 0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: count / 2,
              backgroundColor: const Color(0xFFE5ECE0),
              color: AppTheme.green,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$count/2 ${_copy('photos added', 'फोटो जुड़े', 'फोटो जोडले')}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

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
                  _farm['name']?.toString() ??
                      _copy('Selected farm', 'चुना हुआ खेत', 'निवडलेले शेत'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_farm['crop'] != null)
                  Text(
                    '${_farm['crop']}',
                    style: const TextStyle(
                      color: Color(0xFFDDEAD5),
                      fontSize: 14,
                    ),
                  ),
                if (_farm['location_label'] != null)
                  Text(
                    '${_farm['location_label']}',
                    style: const TextStyle(
                      color: Color(0xFFDDEAD5),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _resultCard() {
    final result = _result ?? const <String, dynamic>{};
    final quality = _map(result['quality']);
    final moisture = _map(result['moisture']);
    final confidence = _map(result['confidence']);
    final grade =
        '${quality['grade'] ?? result['final_grade'] ?? result['grade'] ?? '—'}';
    final score = _displayValue(quality['score'] ?? result['final_score']);
    final moisturePercent = _displayValue(
      moisture['percent_estimate'] ?? result['moisture_percent'],
    );
    final risk = '${moisture['risk_level'] ?? result['moisture_risk'] ?? '—'}';
    final confidenceValue = _displayValue(
      confidence['overall'] ?? result['confidence_score'],
    );
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _farmerDetailsStrip(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metricTile(
                    _copy('Grade', 'ग्रेड', 'ग्रेड'),
                    grade,
                    Icons.verified_outlined,
                    AppTheme.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricTile(
                    _copy('Score', 'स्कोर', 'गुण'),
                    score,
                    Icons.speed_outlined,
                    AppTheme.gold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricTile(
                    _copy('Moisture', 'नमी', 'ओलावा'),
                    '$moisturePercent%',
                    Icons.water_drop_outlined,
                    Colors.blueGrey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _resultSummaryBox(
              grade: grade,
              risk: risk,
              confidence: confidenceValue,
            ),
            const SizedBox(height: 10),
            _aiSuggestionBox(),
            const SizedBox(height: 4),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                _copy('More details', 'अधिक जानकारी', 'अधिक माहिती'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              children: [
                for (final section in _compactResultSections(result))
                  _resultSection(section),
              ],
            ),
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
                      ? _copy(
                          'Preparing PDF…',
                          'PDF बन रहा है…',
                          'PDF तयार होत आहे…',
                        )
                      : _copy(
                          'Download PDF report',
                          'PDF रिपोर्ट डाउनलोड करें',
                          'PDF रिपोर्ट डाउनलोड करा',
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _farmerDetailsStrip() {
    final name = '${_farmer['name'] ?? _farmer['farmer_name'] ?? 'Farmer'}'
        .trim();
    final farmerId = '${_farmer['id'] ?? _farmer['farmer_id'] ?? ''}'.trim();
    final location = '${_farmer['location'] ?? _farm['location_label'] ?? ''}'
        .trim();
    final farmName =
        '${_farm['name'] ?? _copy('Selected farm', 'चुना हुआ खेत', 'निवडलेले शेत')}'
            .trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9F4),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: const Color(0xFFE2EBDD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 18,
                color: AppTheme.greenDark,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (farmerId.isNotEmpty)
                _detailText('${_copy('ID', 'आईडी', 'आयडी')}: $farmerId'),
              _detailText('${_copy('Farm', 'खेत', 'शेत')}: $farmName'),
              if (location.isNotEmpty) _detailText(location),
              _detailText(
                '${_copy('Crop', 'फसल', 'पीक')}: ${_resultCropLabel()}',
              ),
              _detailText(
                '${_copy('Variety', 'किस्म', 'वाण')}: ${_resultVarietyLabel()}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailText(String value) => Text(
    value,
    style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
  );

  Widget _metricTile(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _resultSummaryBox({
    required String grade,
    required String risk,
    required String confidence,
  }) {
    final summary =
        '${_result?['operator_summary'] ?? _result?['summary'] ?? ''}'.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Text(
        summary.isNotEmpty
            ? summary
            : _copy(
                'Grade $grade. Moisture risk: $risk. Confidence: $confidence.',
                'ग्रेड $grade। नमी जोखिम: $risk। भरोसा: $confidence।',
                'ग्रेड $grade. ओलावा धोका: $risk. विश्वास: $confidence.',
              ),
        style: const TextStyle(
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _aiSuggestionBox() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E7),
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      border: Border.all(color: const Color(0xFFF1D58A)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lightbulb_outline, size: 19, color: Color(0xFF9B6B00)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _copy('AI suggestion', 'AI सुझाव', 'AI सूचना'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF7D5700),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _farmerSuggestion(),
                style: const TextStyle(fontSize: 12.5, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    ),
  );

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
          Text(
            section.label,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(section.value, style: const TextStyle(height: 1.3)),
        ],
      ),
    ),
  );

  List<_ResultSection> _compactResultSections(Map<String, dynamic> result) {
    final quality = _map(result['quality']);
    final confidence = _map(result['confidence']);
    final reviewStatus =
        result['manual_review_required'] == true ||
            '${result['review_status'] ?? ''}'.toLowerCase() == 'pending'
        ? _copy('Needs FPC review', 'FPC जाँच जरूरी', 'FPC तपासणी आवश्यक')
        : _copy('Ready to use', 'उपयोग के लिए तैयार', 'वापरण्यास तयार');
    final analysisId = '${result['analysis_id'] ?? ''}'.trim();
    final overallConfidence = _displayValue(
      confidence['overall'] ?? result['confidence_score'],
    );
    final signal = '${result['signal_highlights'] ?? ''}'.trim();
    return [
      _ResultSection(_copy('Review', 'जाँच', 'तपासणी'), reviewStatus),
      if (overallConfidence != '—')
        _ResultSection(
          _copy('Confidence', 'भरोसा', 'विश्वास'),
          overallConfidence,
        ),
      if (analysisId.isNotEmpty)
        _ResultSection(
          _copy('Report ID', 'रिपोर्ट आईडी', 'अहवाल आयडी'),
          analysisId,
        ),
      if (signal.isNotEmpty)
        _ResultSection(_copy('Note', 'नोट', 'नोंद'), signal),
      if (quality.isEmpty && analysisId.isEmpty)
        _ResultSection(
          _copy('Status', 'स्थिति', 'स्थिती'),
          _copy(
            'Result saved successfully.',
            'परिणाम सफलतापूर्वक सेव हुआ।',
            'निकाल यशस्वीपणे सेव झाला.',
          ),
        ),
    ];
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
    if (value is Map) {
      return value.entries
          .map(
            (entry) =>
                '${_prettyKey(entry.key.toString())}: ${_displayValue(entry.value)}',
          )
          .join(', ');
    }
    if (value is List) return value.map(_displayValue).join(', ');
    if (value is bool) return value ? 'Yes' : 'No';
    return '$value';
  }

  String _cropLabel(CropOption crop) => crop.label;

  String _varietyLabel(CropVariety variety) => variety.label;

  String _resultCropLabel() {
    final selection = _map(_result?['selection']);
    return '${_selectedCrop?.label ?? selection['selected_crop'] ?? _farm['crop'] ?? '—'}';
  }

  String _resultVarietyLabel() {
    final selection = _map(_result?['selection']);
    return '${_selectedVariety?.label ?? selection['selected_variety'] ?? _farm['variety'] ?? '—'}';
  }

  String _farmerSuggestion() {
    final result = _result ?? const <String, dynamic>{};
    final quality = _map(result['quality']);
    final moisture = _map(result['moisture']);
    final grade =
        '${quality['grade'] ?? result['final_grade'] ?? result['grade'] ?? ''}'
            .toUpperCase();
    final risk = '${moisture['risk_level'] ?? result['moisture_risk'] ?? ''}'
        .toLowerCase();
    final manualReview =
        result['manual_review_required'] == true ||
        '${result['review_status'] ?? ''}'.toLowerCase() == 'pending';
    if (manualReview) {
      return _copy(
        'Keep this lot separate and ask your FPC or quality officer to review it before selling.',
        'इस लॉट को अलग रखें और बेचने से पहले FPC या गुणवत्ता अधिकारी से जाँच कराएँ।',
        'हा लॉट वेगळा ठेवा आणि विक्रीपूर्वी FPC किंवा गुणवत्ता अधिकाऱ्याकडून तपासून घ्या.',
      );
    }
    if (risk.contains('high') || risk.contains('medium')) {
      return _copy(
        'Dry the grain further, then store it in a clean, raised and moisture-free place.',
        'अनाज को और सुखाकर साफ, ऊँची और नमी से दूर जगह पर रखें।',
        'धान्य आणखी वाळवून स्वच्छ, उंच आणि ओलावामुक्त ठिकाणी साठवा.',
      );
    }
    if (grade == 'A') {
      return _copy(
        'Good quality detected. Keep the grain dry and protected from pests during storage.',
        'अच्छी गुणवत्ता मिली। भंडारण के दौरान अनाज को सूखा रखें और कीड़ों से बचाएँ।',
        'चांगली गुणवत्ता आढळली. साठवताना धान्य कोरडे ठेवा आणि किडींपासून जपा.',
      );
    }
    if (grade.isNotEmpty) {
      return _copy(
        'Clean and dry the grain before storage. Recheck the lot if you plan to sell it.',
        'भंडारण से पहले अनाज साफ और सूखा लें। बेचने से पहले लॉट की फिर जाँच करें।',
        'साठवण्यापूर्वी धान्य स्वच्छ आणि कोरडे करा. विक्रीपूर्वी लॉट पुन्हा तपासा.',
      );
    }
    return _copy(
      'Follow the result summary and keep the sample safe for any follow-up review.',
      'परिणाम के अनुसार काम करें और आगे की जाँच के लिए नमूना सुरक्षित रखें।',
      'निकालानुसार कृती करा आणि पुढील तपासणीसाठी नमुना सुरक्षित ठेवा.',
    );
  }

  Future<void> _downloadResult() async {
    final result = _result;
    if (result == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
          build: (context) {
            final quality = _map(result['quality']);
            final moisture = _map(result['moisture']);
            final grade =
                '${quality['grade'] ?? result['final_grade'] ?? result['grade'] ?? '—'}';
            final score = _displayValue(
              quality['score'] ?? result['score'] ?? result['quality_score'],
            );
            final moisturePercent = _displayValue(
              moisture['percent_estimate'] ?? result['moisture_percent'],
            );
            final risk =
                '${moisture['risk_level'] ?? result['moisture_risk'] ?? '—'}';
            final grainImage = _grainPhotoBytes == null
                ? null
                : pw.MemoryImage(_grainPhotoBytes!);
            final farmName = '${_farm['name'] ?? 'Selected farm'}';
            final location = '${_farm['location_label'] ?? ''}'.trim();
            final farmerName = '${_farmer['name'] ?? 'Farmer'}';
            final farmerId = '${_farmer['id'] ?? ''}'.trim();
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'GrainRight',
                            style: pw.TextStyle(
                              color: const PdfColor(0.08, 0.36, 0.18),
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Grain quality report',
                            style: pw.TextStyle(
                              color: const PdfColor(0.28, 0.34, 0.29),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Text(
                      DateTime.now().toLocal().toString().split(' ').first,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(11),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor(0.95, 0.98, 0.94),
                    borderRadius: pw.BorderRadius.circular(7),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        farmerName,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        [
                          'Farm: $farmName',
                          if (location.isNotEmpty) 'Location: $location',
                          if (farmerId.isNotEmpty) 'Farmer ID: $farmerId',
                        ].join('  |  '),
                        style: const pw.TextStyle(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (grainImage != null)
                      pw.Container(
                        width: 128,
                        height: 128,
                        margin: const pw.EdgeInsets.only(right: 14),
                        padding: const pw.EdgeInsets.all(4),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: const PdfColor(0.82, 0.88, 0.82),
                          ),
                          borderRadius: pw.BorderRadius.circular(7),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 5,
                          verticalRadius: 5,
                          child: pw.Image(grainImage, fit: pw.BoxFit.cover),
                        ),
                      ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Sample details',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor(0.08, 0.36, 0.18),
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text('Crop: ${_resultCropLabel()}'),
                          pw.Text('Variety: ${_resultVarietyLabel()}'),
                          pw.SizedBox(height: 9),
                          pw.Row(
                            children: [
                              _pdfMetric('Grade', grade),
                              pw.SizedBox(width: 12),
                              _pdfMetric('Score', score),
                              pw.SizedBox(width: 12),
                              _pdfMetric('Moisture', '$moisturePercent%'),
                            ],
                          ),
                          if (grainImage == null) ...[
                            pw.SizedBox(height: 7),
                            pw.Text(
                              'Grain photo is available in the GrainRight record.',
                              style: const pw.TextStyle(fontSize: 8.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 13),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(11),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor(1, 0.97, 0.86),
                    borderRadius: pw.BorderRadius.circular(7),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'What to do next',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor(0.45, 0.31, 0.02),
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(_farmerSuggestion()),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Moisture status: $risk',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Divider(color: const PdfColor(0.82, 0.88, 0.82)),
                pw.Text(
                  'Keep this report with the grain sample. Detailed analysis is saved in GrainRight.',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
              ],
            );
          },
        ),
      );
      final bytes = Uint8List.fromList(await document.save());
      await downloadWhatsappResult(bytes, 'grainright-grading-report.pdf');
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _copy(
            'The report could not be downloaded. Please try again.',
            'रिपोर्ट डाउनलोड नहीं हो सकी। फिर कोशिश करें।',
            'रिपोर्ट डाउनलोड होऊ शकली नाही. पुन्हा प्रयत्न करा.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  pw.Widget _pdfMetric(String label, String value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );

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
