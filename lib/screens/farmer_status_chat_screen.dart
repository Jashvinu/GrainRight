import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../utils/harvest_machine_capture.dart';

class FarmStatusUpdateResult {
  final String message;
  final String question;
  final String stage;
  final DateTime updatedAt;
  final Uint8List? photoBytes;
  final String? photoName;

  const FarmStatusUpdateResult({
    required this.message,
    required this.question,
    required this.stage,
    required this.updatedAt,
    this.photoBytes,
    this.photoName,
  });
}

class FarmerStatusChatScreen extends StatefulWidget {
  final String farmName;
  final String crop;
  final String variety;
  final String location;
  final String stage;
  final int daysAfterSowing;
  final String stageQuestion;
  final String? priorStatus;
  final bool requiresPhoto;

  const FarmerStatusChatScreen({
    super.key,
    required this.farmName,
    required this.crop,
    required this.variety,
    required this.location,
    required this.stage,
    required this.daysAfterSowing,
    required this.stageQuestion,
    this.priorStatus,
    required this.requiresPhoto,
  });

  @override
  State<FarmerStatusChatScreen> createState() => _FarmerStatusChatScreenState();
}

class _FarmerStatusChatScreenState extends State<FarmerStatusChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_StatusMessage> _messages = [];
  String _draft = '';
  Uint8List? _photoBytes;
  String? _photoName;
  static const Map<String, List<String>> _stageQuickReplies = {
    'Sowing': [
      'Germination is healthy',
      'Some moisture stress',
      'Need irrigation today',
      'Need re-inspection support',
    ],
    'Establishment': [
      'Patchy stands in corner',
      'Good germination overall',
      'Need replanting help',
      'Irrigation done',
    ],
    'Vegetative': [
      'Growth is normal',
      'Some weeds observed',
      'Leaf colour looks pale',
      'Watering done',
    ],
    'Flowering': [
      'Flowering is good',
      'Pollen drop seen',
      'Need moisture top-up',
      'Any insect attack appears',
    ],
    'Grain filling': [
      'Grains are filling well',
      'Some flower drop seen',
      'Looks low moisture',
      'Need support and re-check',
    ],
    'Maturity': [
      'Panicles are fully developed',
      'Grain drying is normal',
      'Need harvesting support',
      'Check moisture content',
    ],
  };

  @override
  void initState() {
    super.initState();
    _messages
      ..add(
        _StatusMessage(
          isUser: false,
          text:
              'Farm context: ${widget.farmName} • ${widget.crop} • ${widget.variety}\n'
              'Location: ${widget.location}\n'
              'Stage: Day ${widget.daysAfterSowing} • ${widget.stage}',
        ),
      )
      ..add(
        _StatusMessage(
          isUser: false,
          text: widget.stageQuestion,
        ),
      );

    if (widget.priorStatus != null && widget.priorStatus!.trim().isNotEmpty) {
      _messages
        ..add(
          _StatusMessage(
            isUser: false,
            text: 'Previous status note: ${widget.priorStatus}',
          ),
        );
    }
    if (widget.requiresPhoto) {
      _messages.add(
        const _StatusMessage(
          isUser: false,
          text: 'Photo is required for this stage. Add one before Submit status.',
        ),
      );
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _appendMessage({required bool isUser, required String text}) {
    setState(() {
      _messages.add(_StatusMessage(isUser: isUser, text: text));
      if (isUser) {
        _draft = text;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      _showToast('Write your update before sending.');
      return;
    }
    _inputController.clear();
    _appendMessage(isUser: true, text: text);
    _appendMessage(
      isUser: false,
      text: 'Saved. You can send another note or tap “Submit status”.',
    );
  }

  void _applyQuickSuggestion(String suggestion) {
    _inputController.text = suggestion;
    _sendMessage();
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickPhoto() async {
    final result = await pickHarvestMachineImage();
    if (result == null) return;
    if (!mounted) return;

    setState(() {
      _photoBytes = result.bytes;
      _photoName = result.name;
    });
  }

  Future<void> _submitStatus() async {
    if (_draft.trim().isEmpty) {
      _showToast('Add a status note before submitting.');
      return;
    }
    if (widget.requiresPhoto && _photoBytes == null) {
      _showToast('Attach photo before submitting for this stage.');
      return;
    }

    Navigator.pop(
      context,
      FarmStatusUpdateResult(
        message: _draft.trim(),
        question: widget.stageQuestion,
        stage: widget.stage,
        updatedAt: DateTime.now(),
        photoBytes: _photoBytes,
        photoName: _photoName,
      ),
    );
  }

  List<String> get _quickSuggestions => [
        'Growth looks normal, no stress',
        'Irrigation done today',
        'Need re-inspection and support',
        'Unexpected yellowing seen',
      ];

  List<String> get _quickReplies {
    final fromStage = _stageQuickReplies[widget.stage];
    if (fromStage == null || fromStage.isEmpty) return _quickSuggestions;
    return fromStage;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Status Update • ${widget.farmName}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                itemCount: _messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _messages[index];
                  return Align(
                    alignment:
                        item.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: item.isUser
                            ? AppTheme.greenPale
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: item.isUser
                              ? const Color(0xFFB7D6BE)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Text(
                        item.text,
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_photoBytes != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.memory(_photoBytes!, fit: BoxFit.cover),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _quickReplies)
                    ActionChip(
                      label: Text(item),
                      onPressed: () => _applyQuickSuggestion(item),
                    ),
                ],
              ),
            ),
            if (_photoName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.photo_camera_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _photoName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Type a farm status note...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Attach photo',
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitStatus,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Submit status'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMessage {
  final bool isUser;
  final String text;

  const _StatusMessage({
    required this.isUser,
    required this.text,
  });
}
