import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/whatsapp_service_handoff.dart';

class WhatsappServiceScreen extends StatefulWidget {
  final String? token;

  const WhatsappServiceScreen({super.key, this.token});

  @override
  State<WhatsappServiceScreen> createState() => _WhatsappServiceScreenState();
}

class _WhatsappServiceScreenState extends State<WhatsappServiceScreen> {
  final _question = TextEditingController();
  final _picker = ImagePicker();
  bool _loading = true;
  bool _submitting = false;
  String _service = '';
  String _language = 'en';
  Map<String, dynamic> _farm = const {};
  Map<String, dynamic>? _result;
  XFile? _grainPhoto;
  XFile? _moisturePhoto;
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
        final result = data['result'];
        _result = result is Map ? _map(result) : null;
      });
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
        (_grainPhoto == null || _moisturePhoto == null)) {
      setState(
        () => _error = _copy(
          'Upload both photos before submitting.',
          'भेजने से पहले दोनों फोटो अपलोड करें।',
          'पाठवण्यापूर्वी दोन्ही फोटो अपलोड करा.',
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
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  _farm['name']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_farm['crop'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${_farm['crop']}'),
                  ),
                const SizedBox(height: 24),
                if (_error != null) _errorBox(_error!),
                if (_result != null) ...[
                  _resultCard(),
                  const SizedBox(height: 20),
                ],
                if (_result == null && _service == 'ai') _aiForm(),
                if (_result == null && _service == 'grading') _gradingForm(),
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
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
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

  Widget _resultCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: SelectableText(_resultText),
    ),
  );

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
