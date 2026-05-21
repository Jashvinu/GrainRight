import 'package:flutter/material.dart';

class UserTextBubble extends StatelessWidget {
  final String text;

  const UserTextBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              text,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}
