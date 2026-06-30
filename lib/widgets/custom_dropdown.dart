import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';

class CustomDropdown extends StatefulWidget {
  final String label;
  final List<String> items;
  final Rxn<String> selected;
  final String? optionKey;

  const CustomDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.selected,
    this.optionKey,
  });

  @override
  State<CustomDropdown> createState() => _CustomDropdownState();
}

class _CustomDropdownState extends State<CustomDropdown> {
  static const _itemHeight = 48.0;
  static const _menuGap = 6.0;
  static const _maxMenuHeight = 288.0;

  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _toggleMenu() {
    if (_overlayEntry == null) {
      _openMenu();
    } else {
      _closeMenu();
    }
  }

  void _openMenu() {
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (fieldBox == null || overlayBox == null || widget.items.isEmpty) return;

    final fieldSize = fieldBox.size;
    final fieldOffset = fieldBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final availableAbove = math.max(0.0, fieldOffset.dy - _menuGap);
    final desiredHeight = math.min(
      _maxMenuHeight,
      widget.items.length * _itemHeight + 8,
    );
    final opensAbove = availableAbove >= 96;
    final menuHeight = opensAbove
        ? math.min(desiredHeight, availableAbove)
        : desiredHeight;
    final verticalOffset = opensAbove
        ? -menuHeight - _menuGap
        : fieldSize.height + _menuGap;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeMenu,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, verticalOffset),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: menuHeight,
                    minWidth: fieldSize.width,
                    maxWidth: fieldSize.width,
                  ),
                  child: _DropdownMenu(
                    items: widget.items,
                    selected: widget.selected,
                    optionKey: widget.optionKey,
                    onSelected: (value) {
                      widget.selected.value = value;
                      Get.find<FormController>().saveDraft();
                      _closeMenu();
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlayEntry!);
    if (mounted) setState(() {});
  }

  void _closeMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lang = Get.find<LanguageController>();
    final formController = Get.find<FormController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Obx(() {
          final _ = lang.language.value;
          final current = widget.items.contains(widget.selected.value)
              ? widget.selected.value
              : null;
          final displayText = current == null
              ? ''
              : formController.localizedOptionLabel(widget.optionKey, current);
          return InkWell(
            key: _fieldKey,
            borderRadius: BorderRadius.circular(10),
            onTap: _toggleMenu,
            child: InputDecorator(
              isEmpty: current == null,
              decoration: InputDecoration(
                labelText: widget.label,
                suffixIcon: Icon(
                  _overlayEntry == null
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                ),
              ),
              child: Text(
                displayText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: current == null ? Colors.grey[500] : AppTheme.textDark,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DropdownMenu extends StatelessWidget {
  final List<String> items;
  final Rxn<String> selected;
  final String? optionKey;
  final ValueChanged<String> onSelected;

  const _DropdownMenu({
    required this.items,
    required this.selected,
    required this.optionKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Get.find<LanguageController>();
    final formController = Get.find<FormController>();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Obx(() {
          final _ = lang.language.value;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
            itemBuilder: (context, index) {
              final value = items[index];
              final isSelected = selected.value == value;
              final label = formController.localizedOptionLabel(
                optionKey,
                value,
              );
              return InkWell(
                onTap: () => onSelected(value),
                child: Container(
                  height: _CustomDropdownState._itemHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  color: isSelected ? AppTheme.greenPale : Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected
                                ? AppTheme.greenDark
                                : AppTheme.textDark,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          Icons.check_rounded,
                          color: AppTheme.green,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
