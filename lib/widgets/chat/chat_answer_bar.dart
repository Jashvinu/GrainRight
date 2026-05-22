import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../controllers/form_controller.dart';
import '../../models/form_config.dart';

class ChatAnswerBar extends StatefulWidget {
  final FormFieldConfig field;
  final FormController formController;
  final VoidCallback onSubmit;
  final VoidCallback? onSkip;

  const ChatAnswerBar({
    super.key,
    required this.field,
    required this.formController,
    required this.onSubmit,
    this.onSkip,
  });

  @override
  State<ChatAnswerBar> createState() => _ChatAnswerBarState();
}

class _ChatAnswerBarState extends State<ChatAnswerBar> {
  final _focusNode = FocusNode();

  bool get _usesKeyboard => switch (widget.field.inputType) {
    'text' ||
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
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, -4),
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
            maxLines: field.inputType == 'text' ? 4 : 1,
            keyboardType: _keyboardType,
            textInputAction: field.inputType == 'text'
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
        if (onSkip != null) ...[
          const SizedBox(width: 8),
          TextButton(onPressed: onSkip, child: const Text('Skip')),
        ],
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send',
          iconSize: 28,
          padding: const EdgeInsets.all(14),
          onPressed: onSubmit,
          icon: const Icon(Icons.arrow_upward_rounded),
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
    if (field.inputType != 'text') return TextCapitalization.none;
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
    return _ChipRow(
      children: [
        ActionChip(
          avatar: const Icon(Icons.check_rounded, size: 22),
          label: const Text('Yes'),
          labelStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onPressed: () {
            formController.setBool(field.fieldKey, true);
            onSubmit();
          },
        ),
        ActionChip(
          avatar: const Icon(Icons.close_rounded, size: 22),
          label: const Text('No'),
          labelStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onPressed: () {
            formController.setBool(field.fieldKey, false);
            onSubmit();
          },
        ),
        if (onSkip != null)
          TextButton(
            onPressed: onSkip,
            child: const Text('Skip', style: TextStyle(fontSize: 17)),
          ),
      ],
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
    return _ChipRow(
      children: [
        for (final option in options)
          ActionChip(
            label: Text(
              formController.localizedOptionLabel(
                field.dropdownOptionsKey,
                option,
              ),
            ),
            labelStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            onPressed: () {
              formController.setDropdown(field.fieldKey, option);
              onSubmit();
            },
          ),
        if (onSkip != null)
          TextButton(
            onPressed: onSkip,
            child: const Text('Skip', style: TextStyle(fontSize: 17)),
          ),
      ],
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
      () => Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final option in options)
                    FilterChip(
                      label: Text(
                        formController.localizedOptionLabel(
                          field.dropdownOptionsKey,
                          option,
                        ),
                      ),
                      selected: selected.contains(option),
                      onSelected: (isSelected) {
                        if (isSelected) {
                          selected.add(option);
                        } else {
                          selected.remove(option);
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
          if (onSkip != null)
            TextButton(onPressed: onSkip, child: const Text('Skip')),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Done',
            onPressed: onSubmit,
            icon: const Icon(Icons.check_rounded),
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
              onPressed: () => _pickDate(context),
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(
                rxDate.value == null
                    ? 'Select date'
                    : DateFormat('dd MMM yyyy').format(rxDate.value!),
              ),
            ),
          ),
          if (onSkip != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onSkip, child: const Text('Skip')),
          ],
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: onSubmit,
            icon: const Icon(Icons.arrow_upward_rounded),
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
            child: Text(
              'Rs ${value.value.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton.filled(
            tooltip: 'Continue',
            onPressed: onSubmit,
            icon: const Icon(Icons.arrow_forward_rounded),
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
      child: FilledButton(onPressed: onSubmit, child: const Text('Continue')),
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<Widget> children;

  const _ChipRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: _withSpacing(children)),
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
