import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

/// Dialog for entering a numeric value directly.
class NumberInputDialog extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final String suffix;
  final double minValue;
  final double maxValue;
  final bool allowDecimal;

  const NumberInputDialog({
    super.key,
    required this.title,
    required this.controller,
    required this.suffix,
    required this.minValue,
    required this.maxValue,
    this.allowDecimal = true,
  });

  @override
  State<NumberInputDialog> createState() => _NumberInputDialogState();
}

class _NumberInputDialogState extends State<NumberInputDialog> {
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // Select all text when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  void _validate() {
    final text = widget.controller.text;
    if (text.isEmpty) {
      setState(() => _errorText = 'Enter a value');
      return;
    }
    final value = double.tryParse(text);
    if (value == null) {
      setState(() => _errorText = 'Invalid number');
      return;
    }
    if (value < widget.minValue || value > widget.maxValue) {
      setState(() =>
          _errorText = '${widget.minValue.toInt()} - ${widget.maxValue.toInt()}');
      return;
    }
    setState(() => _errorText = null);
  }

  void _submit() {
    _validate();
    if (_errorText != null) return;

    final value = double.tryParse(widget.controller.text);
    if (value != null) {
      Navigator.pop(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: widget.allowDecimal,
              signed: widget.minValue < 0,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.allowDecimal
                    ? RegExp(r'^-?[\d.]*$')
                    : RegExp(r'^-?[\d]*$'),
              ),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              suffixText: widget.suffix,
              suffixStyle: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              errorText: _errorText,
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
            onChanged: (_) => _validate(),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Range: ${widget.minValue.toInt()} - ${widget.maxValue.toInt()} ${widget.suffix}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'OK',
            style: TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
