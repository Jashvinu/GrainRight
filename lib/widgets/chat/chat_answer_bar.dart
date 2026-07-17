import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../../controllers/form_controller.dart';
import '../../models/form_config.dart';

class ChatAnswerBar extends StatefulWidget {
  final FormFieldConfig field;
  final FormController formController;
  final VoidCallback onSubmit;
  final VoidCallback? onSkip;
  final bool floating;

  const ChatAnswerBar({
    super.key,
    required this.field,
    required this.formController,
    required this.onSubmit,
    this.onSkip,
    this.floating = false,
  });

  @override
  State<ChatAnswerBar> createState() => _ChatAnswerBarState();
}

class _ChatAnswerBarState extends State<ChatAnswerBar> {
  final _focusNode = FocusNode();

  bool get _usesKeyboard => switch (widget.field.inputType) {
    'text' ||
    'textarea' ||
    'numeric' ||
    'currency' ||
    'acre' ||
    'mobile' ||
    'aadhar' ||
    'millet_land_picker' => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _requestKeyboard();
  }

  @override
  void didUpdateWidget(covariant ChatAnswerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.field.fieldKey != widget.field.fieldKey) {
      _requestKeyboard();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _requestKeyboard() {
    if (!_usesKeyboard) {
      _focusNode.unfocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(widget.floating ? 18 : 0),
          border: widget.floating
              ? Border.all(color: Colors.grey.shade200)
              : Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: widget.floating ? 0.14 : 0.05,
              ),
              blurRadius: widget.floating ? 22 : 14,
              offset: Offset(0, widget.floating ? 8 : -4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: _buildInput(context),
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return switch (widget.field.inputType) {
      'text' ||
      'textarea' ||
      'numeric' ||
      'currency' ||
      'acre' ||
      'mobile' ||
      'aadhar' ||
      'millet_land_picker' => _TextAnswerInput(
        field: widget.field,
        controller: widget.formController.textController(widget.field.fieldKey),
        focusNode: _focusNode,
        onSubmit: widget.onSubmit,
        onSkip: widget.onSkip,
      ),
      'boolean' => _BooleanAnswerInput(
        field: widget.field,
        formController: widget.formController,
        onSubmit: widget.onSubmit,
        onSkip: widget.onSkip,
      ),
      'dropdown' => _ChoiceAnswerInput(
        field: widget.field,
        formController: widget.formController,
        onSubmit: widget.onSubmit,
        onSkip: widget.onSkip,
      ),
      'multiselect' => _MultiChoiceAnswerInput(
        field: widget.field,
        formController: widget.formController,
        onSubmit: widget.onSubmit,
        onSkip: widget.onSkip,
      ),
      'date' => _DateAnswerInput(
        field: widget.field,
        formController: widget.formController,
        onSubmit: widget.onSubmit,
        onSkip: widget.onSkip,
      ),
      'auto_calc' => _AutoCalcAnswerInput(
        field: widget.field,
        formController: widget.formController,
        onSubmit: widget.onSubmit,
      ),
      _ => _UnsupportedAnswerInput(onSubmit: widget.onSubmit),
    };
  }
}

class _TextAnswerInput extends StatelessWidget {
  final FormFieldConfig field;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback? onSkip;

  const _TextAnswerInput({
    required this.field,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            minLines: 1,
            maxLines: field.inputType == 'text' || field.inputType == 'textarea'
                ? 4
                : 1,
            keyboardType: _keyboardType,
            textInputAction:
                field.inputType == 'text' || field.inputType == 'textarea'
                ? TextInputAction.newline
                : TextInputAction.send,
            textCapitalization: _textCapitalization,
            autocorrect: !_isNumericField,
            enableSuggestions: !_isNumericField,
            inputFormatters: _inputFormatters,
            style: const TextStyle(fontSize: 19),
            decoration: InputDecoration(
              hintText: field.localizedHint(context) ?? 'Type answer',
              hintStyle: const TextStyle(fontSize: 17),
              prefixText: field.inputType == 'currency' ? 'Rs  ' : null,
              prefixStyle: const TextStyle(fontSize: 18),
              suffixText: field.suffixText,
              suffixStyle: const TextStyle(fontSize: 16),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        if (onSkip != null) ...[const SizedBox(width: 8), _SkipButton(onSkip!)],
        const SizedBox(width: 8),
        _AnswerIconButton(
          tooltip: 'Send',
          onPressed: onSubmit,
          icon: Icons.arrow_upward_rounded,
        ),
      ],
    );
  }

  bool get _isNumericField => switch (field.inputType) {
    'numeric' ||
    'currency' ||
    'acre' ||
    'mobile' ||
    'aadhar' ||
    'millet_land_picker' => true,
    _ => false,
  };

  TextCapitalization get _textCapitalization {
    if (field.inputType != 'text' && field.inputType != 'textarea') {
      return TextCapitalization.none;
    }
    final key = field.fieldKey.toLowerCase();
    if (key.contains('name') ||
        key.contains('village') ||
        key.contains('taluka') ||
        key.contains('district') ||
        key.contains('panchayat')) {
      return TextCapitalization.words;
    }
    return TextCapitalization.sentences;
  }

  TextInputType get _keyboardType {
    return switch (field.inputType) {
      'text' => TextInputType.multiline,
      'textarea' => TextInputType.multiline,
      'mobile' => TextInputType.phone,
      'aadhar' => TextInputType.number,
      'numeric' || 'millet_land_picker' => TextInputType.number,
      'currency' ||
      'acre' => const TextInputType.numberWithOptions(decimal: true),
      _ => TextInputType.text,
    };
  }

  List<TextInputFormatter> get _inputFormatters {
    return switch (field.inputType) {
      'mobile' => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      'aadhar' => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(12),
      ],
      'numeric' || 'currency' || 'acre' || 'millet_land_picker' => [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
      ],
      _ => const <TextInputFormatter>[],
    };
  }
}

class _BooleanAnswerInput extends StatelessWidget {
  final FormFieldConfig field;
  final FormController formController;
  final VoidCallback onSubmit;
  final VoidCallback? onSkip;

  const _BooleanAnswerInput({
    required this.field,
    required this.formController,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return _AnswerScrollRow(
      choices: [
        _AnswerChoiceChip(
          label: 'Yes',
          icon: Icons.check_rounded,
          onPressed: () {
            formController.setBool(field.fieldKey, true);
            onSubmit();
          },
        ),
        _AnswerChoiceChip(
          label: 'No',
          icon: Icons.close_rounded,
          onPressed: () {
            formController.setBool(field.fieldKey, false);
            onSubmit();
          },
        ),
      ],
      trailing: [if (onSkip != null) _SkipButton(onSkip!)],
    );
  }
}

class _ChoiceAnswerInput extends StatelessWidget {
  final FormFieldConfig field;
  final FormController formController;
  final VoidCallback onSubmit;
  final VoidCallback? onSkip;

  const _ChoiceAnswerInput({
    required this.field,
    required this.formController,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final options =
        formController.dropdownOptions[field.dropdownOptionsKey] ??
        const <String>[];
    return _AnswerScrollRow(
      choices: [
        for (final option in options)
          _AnswerChoiceChip(
            label: formController.localizedOptionLabel(
              field.dropdownOptionsKey,
              option,
            ),
            onPressed: () {
              formController.setDropdown(field.fieldKey, option);
              onSubmit();
            },
          ),
      ],
      trailing: [if (onSkip != null) _SkipButton(onSkip!)],
    );
  }
}

class _MultiChoiceAnswerInput extends StatelessWidget {
  final FormFieldConfig field;
  final FormController formController;
  final VoidCallback onSubmit;
  final VoidCallback? onSkip;

  const _MultiChoiceAnswerInput({
    required this.field,
    required this.formController,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final options =
        formController.dropdownOptions[field.dropdownOptionsKey] ??
        const <String>[];
    final selected = formController.multiSelectValue(field.fieldKey);
    return Obx(
      () => _AnswerScrollRow(
        choices: [
          for (final option in options)
            _AnswerChoiceChip(
              label: formController.localizedOptionLabel(
                field.dropdownOptionsKey,
                option,
              ),
              selected: selected.contains(option),
              selectedIcon: Icons.check_rounded,
              onPressed: () {
                if (selected.contains(option)) {
                  selected.remove(option);
                } else {
                  selected.add(option);
                }
              },
            ),
        ],
        trailing: [
          if (onSkip != null) _SkipButton(onSkip!),
          _AnswerIconButton(
            tooltip: 'Done',
            onPressed: onSubmit,
            icon: Icons.check_rounded,
          ),
        ],
      ),
    );
  }
}

class _DateAnswerInput extends StatelessWidget {
  final FormFieldConfig field;
  final FormController formController;
  final VoidCallback onSubmit;
  final VoidCallback? onSkip;

  const _DateAnswerInput({
    required this.field,
    required this.formController,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final rxDate = formController.dateValue(field.fieldKey);
    return Obx(
      () => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: _answerOutlinedButtonStyle,
              onPressed: () => _pickDate(context),
              icon: const Icon(Icons.calendar_today_rounded, size: 20),
              label: Text(
                rxDate.value == null
                    ? 'Select date'
                    : DateFormat('dd MMM yyyy').format(rxDate.value!),
              ),
            ),
          ),
          if (onSkip != null) ...[
            const SizedBox(width: 8),
            _SkipButton(onSkip!),
          ],
          const SizedBox(width: 8),
          _AnswerIconButton(
            tooltip: 'Send',
            onPressed: onSubmit,
            icon: Icons.arrow_upward_rounded,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final rxDate = formController.dateValue(field.fieldKey);
    var firstDate = DateTime(1930);
    var lastDate = DateTime.now();

    final validation = field.validation;
    if (validation.containsKey('date_min')) {
      firstDate =
          DateTime.tryParse(validation['date_min'].toString()) ?? firstDate;
    }
    if (validation.containsKey('date_max')) {
      final raw = validation['date_max'].toString();
      lastDate = raw == 'today'
          ? DateTime.now()
          : DateTime.tryParse(raw) ?? lastDate;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: rxDate.value ?? lastDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) {
      formController.setDate(field.fieldKey, picked);
    }
  }
}

class _AutoCalcAnswerInput extends StatelessWidget {
  final FormFieldConfig field;
  final FormController formController;
  final VoidCallback onSubmit;

  const _AutoCalcAnswerInput({
    required this.field,
    required this.formController,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final value = formController.autoCalcValue(field.fieldKey);
    return Obx(
      () => Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                'Rs ${value.value.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AnswerIconButton(
            tooltip: 'Continue',
            onPressed: onSubmit,
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}

class _UnsupportedAnswerInput extends StatelessWidget {
  final VoidCallback onSubmit;

  const _UnsupportedAnswerInput({required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onSubmit,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text('Continue'),
      ),
    );
  }
}

class _AnswerScrollRow extends StatelessWidget {
  final List<Widget> choices;
  final List<Widget> trailing;

  const _AnswerScrollRow({required this.choices, this.trailing = const []});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: _withSpacing(choices)),
          ),
        ),
        for (final action in trailing) ...[const SizedBox(width: 8), action],
      ],
    );
  }

  List<Widget> _withSpacing(List<Widget> widgets) {
    final spaced = <Widget>[];
    for (final widget in widgets) {
      if (spaced.isNotEmpty) spaced.add(const SizedBox(width: 8));
      spaced.add(widget);
    }
    return spaced;
  }
}

class _AnswerChoiceChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? selectedIcon;
  final bool selected;
  final VoidCallback onPressed;

  const _AnswerChoiceChip({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selectedIcon,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? Colors.white : AppTheme.greenDark;
    final borderColor = selected ? AppTheme.green : Colors.grey.shade300;
    final backgroundColor = selected ? AppTheme.green : AppTheme.surface;
    final displayIcon = selected ? selectedIcon ?? icon : icon;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (displayIcon != null) ...[
                  Icon(displayIcon, size: 20, color: foregroundColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SkipButton(this.onPressed);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      child: const Text('Skip'),
    );
  }
}

class _AnswerIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _AnswerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.green,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        fixedSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      iconSize: 24,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

ButtonStyle get _answerOutlinedButtonStyle {
  return OutlinedButton.styleFrom(
    foregroundColor: AppTheme.greenDark,
    backgroundColor: AppTheme.surface,
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    side: BorderSide(color: Colors.grey.shade300),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  );
}
