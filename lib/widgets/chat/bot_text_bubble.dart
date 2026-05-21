import 'package:flutter/material.dart';
import '../../config/theme.dart';

class BotTextBubble extends StatelessWidget {
  final String text;
  final List<String>? quickReplies;
  final ValueChanged<String>? onQuickReply;

  const BotTextBubble({
    super.key,
    required this.text,
    this.quickReplies,
    this.onQuickReply,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.greenPale,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (quickReplies != null) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final reply in quickReplies!)
                        ActionChip(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          labelStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          label: Text(reply),
                          onPressed: () => onQuickReply?.call(reply),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
