import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Bullet weight display and input widget.
///
/// Shows current weight in grains with grams conversion.
/// Tap to edit.
class WeightInput extends StatelessWidget {
  /// Weight in grains
  final double grains;

  /// Callback when weight is changed
  final ValueChanged<double> onChanged;

  const WeightInput({
    super.key,
    required this.grains,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final grams = grains * 0.0648;

    return GestureDetector(
      onTap: () => _showWeightDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fitness_center,
              size: 18,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              'Weight: ',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '${grains.toStringAsFixed(1)} gr',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              ' (${grams.toStringAsFixed(2)}g)',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.edit,
              size: 16,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _showWeightDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => WeightInputDialog(
        initialGrains: grains,
        onConfirm: onChanged,
      ),
    );
  }
}

/// Dialog for entering bullet weight with preset options.
class WeightInputDialog extends StatefulWidget {
  final double initialGrains;
  final ValueChanged<double> onConfirm;

  const WeightInputDialog({
    super.key,
    required this.initialGrains,
    required this.onConfirm,
  });

  @override
  State<WeightInputDialog> createState() => _WeightInputDialogState();
}

class _WeightInputDialogState extends State<WeightInputDialog> {
  late TextEditingController _controller;
  late double _currentGrains;

  @override
  void initState() {
    super.initState();
    _currentGrains = widget.initialGrains;
    _controller = TextEditingController(
      text: widget.initialGrains.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPreset(double grains) {
    setState(() {
      _currentGrains = grains;
      _controller.text = grains.toStringAsFixed(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final grams = _currentGrains * 0.0648;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text(
        'Bullet Weight',
        style: TextStyle(color: AppColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Weight (grains)',
              suffixText: 'gr',
            ),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            onChanged: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null) {
                setState(() {
                  _currentGrains = parsed;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          Text(
            '= ${grams.toStringAsFixed(2)} grams',
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Common weights:',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _WeightPresetChip(
                label: '7.9 gr',
                subtitle: '.177',
                grains: 7.9,
                onTap: (grains) => _selectPreset(grains),
              ),
              _WeightPresetChip(
                label: '14.3 gr',
                subtitle: '.22',
                grains: 14.3,
                onTap: (grains) => _selectPreset(grains),
              ),
              _WeightPresetChip(
                label: '18.1 gr',
                subtitle: '.22 hvy',
                grains: 18.1,
                onTap: (grains) => _selectPreset(grains),
              ),
              _WeightPresetChip(
                label: '25.4 gr',
                subtitle: '.25',
                grains: 25.4,
                onTap: (grains) => _selectPreset(grains),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final value = double.tryParse(_controller.text);
            if (value != null && value > 0 && value <= 1000) {
              widget.onConfirm(value);
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Tappable chip for selecting a preset weight.
class _WeightPresetChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final double grains;
  final ValueChanged<double> onTap;

  const _WeightPresetChip({
    required this.label,
    required this.subtitle,
    required this.grains,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onTap(grains),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
