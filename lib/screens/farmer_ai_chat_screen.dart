import 'package:flutter/material.dart';
import '../config/theme.dart';

class FarmerAiChatScreen extends StatefulWidget {
  final String? farmName;
  final String? crop;
  final String? variety;
  final String? location;

  const FarmerAiChatScreen({
    super.key,
    this.farmName,
    this.crop,
    this.variety,
    this.location,
  });

  @override
  State<FarmerAiChatScreen> createState() => _FarmerAiChatScreenState();
}

class _FarmerAiChatScreenState extends State<FarmerAiChatScreen> {
  final _promptController = TextEditingController();
  final _messages = <_ChatMessage>[];

  @override
  void initState() {
    super.initState();
    _messages.addAll([
      _ChatMessage(
        isUser: false,
        text:
            _welcomeText(
              farmName: widget.farmName,
              crop: widget.crop,
              variety: widget.variety,
            ),
      ),
    ]);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _sendPrompt() {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: prompt));
      _messages.add(
        _ChatMessage(
          isUser: false,
          text: _assistantReply(prompt),
        ),
      );
      _promptController.clear();
    });
  }

  static String _welcomeText({
    String? farmName,
    String? crop,
    String? variety,
  }) {
    final parts = [
      if (farmName != null) farmName,
      if (crop != null) '$crop${variety != null ? ' • $variety' : ''}',
    ];
    final subject = parts.isEmpty
        ? 'your active farm'
        : '${parts.join(' • ')}';

    return 'Hi! I am the Crop Intelligence Assistant for $subject. Ask me about crop health, irrigation timing, market trend, or what data to capture before inspection.';
  }

  String _assistantReply(String prompt) {
    final clean = prompt.toLowerCase();
    if (clean.contains('disease') || clean.contains('leaf')) {
      return 'Capture a clear leaf image and check for yellowing, spots, or lesions. I can help you decide if it needs inspection.';
    }
    if (clean.contains('irrig') || clean.contains('water')) {
      return 'Track last irrigation time and moisture status; avoid overwatering before rain. A short dry spell of 2-3 days can support root oxygenation.';
    }
    if (clean.contains('market') || clean.contains('price')) {
      return 'Current millet prices vary by lot quality. Keep grain moisture <12% and track moisture tests daily to negotiate better rates.';
    }
    return 'I can help with farming guidance, crop risk checks, and next best action for this farm. Ask a specific question and I will help.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('AI Farm Assistant'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                itemCount: _messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = _messages[index];
                  return Align(
                    alignment: item.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
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
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendPrompt(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about your farm...',
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _sendPrompt,
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.green,
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

class _ChatMessage {
  final bool isUser;
  final String text;

  const _ChatMessage({required this.isUser, required this.text});
}
