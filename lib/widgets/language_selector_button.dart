import 'package:flutter/material.dart';

import '../config/theme.dart';

class LanguageOption {
  final String code;
  final String label;

  const LanguageOption(this.code, this.label);
}

class LanguageSelectorButton extends StatelessWidget {
  static const options = [
    LanguageOption('en', 'English'),
    LanguageOption('hi', 'हिन्दी'),
    LanguageOption('mr', 'मराठी'),
  ];

  final String code;
  final ValueChanged<String> onChanged;

  const LanguageSelectorButton({
    super.key,
    required this.code,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: code,
      tooltip: 'Change language',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 10,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option.code,
            child: _LanguageMenuRow(
              label: option.label,
              selected: option.code == code,
            ),
          ),
      ],
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: _LanguageButtonFace(
          key: ValueKey(code),
          label: labelFor(code),
        ),
      ),
    );
  }

  static String labelFor(String code) {
    return switch (code) {
      'hi' => 'हिन्दी',
      'mr' => 'मराठी',
      _ => 'English',
    };
  }
}

class _LanguageButtonFace extends StatelessWidget {
  final String label;

  const _LanguageButtonFace({
    super.key,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44, maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFDDE8D8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.translate_rounded,
            color: AppTheme.green,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppTheme.textMuted,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _LanguageMenuRow extends StatelessWidget {
  final String label;
  final bool selected;

  const _LanguageMenuRow({
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppTheme.green : AppTheme.textMuted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.greenDark : AppTheme.textDark,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
