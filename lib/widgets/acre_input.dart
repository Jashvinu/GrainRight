import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

class AcreInput extends StatefulWidget {
  final String label;
  final TextEditingController controller;

  const AcreInput({
    super.key,
    required this.label,
    required this.controller,
  });

  @override
  State<AcreInput> createState() => _AcreInputState();
}

class _AcreInputState extends State<AcreInput> {
  bool _useCents = false;
  final _acreCtrl = TextEditingController();
  final _centCtrl = TextEditingController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _syncFromDecimal();
    widget.controller.addListener(_onDecimalChanged);
    _acreCtrl.addListener(_onAcreCentChanged);
    _centCtrl.addListener(_onAcreCentChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onDecimalChanged);
    _acreCtrl.dispose();
    _centCtrl.dispose();
    super.dispose();
  }

  void _syncFromDecimal() {
    final val = double.tryParse(widget.controller.text);
    if (val != null) {
      final acres = val.truncate();
      final cents = ((val - acres) * 100).round();
      _acreCtrl.text = acres.toString();
      _centCtrl.text = cents > 0 ? cents.toString() : '';
    } else {
      _acreCtrl.text = '';
      _centCtrl.text = '';
    }
  }

  void _onDecimalChanged() {
    if (_syncing) return;
    _syncing = true;
    _syncFromDecimal();
    _syncing = false;
    setState(() {});
  }

  void _onAcreCentChanged() {
    if (_syncing || !_useCents) return;
    _syncing = true;
    final acres = int.tryParse(_acreCtrl.text) ?? 0;
    final cents = int.tryParse(_centCtrl.text) ?? 0;
    final total = acres + (cents / 100);
    widget.controller.text = total > 0 ? total.toStringAsFixed(2) : '';
    _syncing = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + toggle row
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _useCents = !_useCents);
                  if (_useCents) _syncFromDecimal();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _useCents ? AppTheme.greenPale : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _useCents ? AppTheme.greenLight : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _useCents ? Icons.grid_view_rounded : Icons.looks_one_outlined,
                        size: 14,
                        color: _useCents ? AppTheme.green : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _useCents ? 'Acre + Cents' : 'Decimal',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _useCents ? AppTheme.green : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Input area
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                _useCents ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: // Decimal mode
                TextFormField(
              controller: widget.controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: InputDecoration(
                hintText: '0.00',
                suffixText: 'acres',
                suffixStyle: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            secondChild: // Acre + Cents mode
                Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _acreCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: 'ac',
                      suffixStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _centCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: InputDecoration(
                      hintText: '00',
                      suffixText: 'cents',
                      suffixStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
