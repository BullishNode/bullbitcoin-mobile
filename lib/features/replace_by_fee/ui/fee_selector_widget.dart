import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/inputs/text_input.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/features/replace_by_fee/domain/fee_entity.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class BumpFeeSelectorWidget extends StatefulWidget {
  const BumpFeeSelectorWidget({
    super.key,
    required this.fastestFeeRate,
    required this.selected,
    required this.txSize,
    required this.onChanged,
  });

  final FeeEntity fastestFeeRate;
  final FeeEntity selected;
  final int txSize;
  final void Function(FeeEntity fee) onChanged;

  @override
  State<BumpFeeSelectorWidget> createState() => _FeeSelectorWidgetState();
}

class _FeeSelectorWidgetState extends State<BumpFeeSelectorWidget> {
  final _controller = TextEditingController();

  double _customFeeRate = 0;
  String get _customFeeRateString => _customFeeRate.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _customFeeRate = widget.selected.feeRate;
    _controller.text = _customFeeRateString;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onCustomChanged(String text) {
    final parsed = num.tryParse(text);
    if (parsed != null) {
      _customFeeRate = parsed.toDouble();
      widget.onChanged(
        FeeEntity(type: FeeType.custom, feeRate: _customFeeRate),
      );
    } else {
      _customFeeRate = 0;
      _controller.text = '';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(16),
            _buildFastestSection(widget.selected.type == FeeType.fastest),
            const Gap(16),
            _buildCustomFeeSection(widget.selected.type == FeeType.custom),
          ],
        ),
      ),
    );
  }

  Widget _buildFastestSection(bool isSelected) {
    return InkWell(
      radius: 2,
      onTap: () => widget.onChanged(widget.fastestFeeRate),
      child: Material(
        elevation: isSelected ? 4 : 1,
        borderRadius: BorderRadius.circular(2),
        clipBehavior: Clip.hardEdge,
        color: context.colour.onSecondary,
        shadowColor: context.colour.secondary,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BBText('Fastest', style: context.font.headlineLarge),
                    const Gap(4),
                    BBText(
                      'Estimated delivery ~ 10 minutes',
                      style: context.font.labelMedium,
                    ),
                    const Gap(2),
                    BBText(
                      'Fee Rate: ${widget.fastestFeeRate.feeRate.toStringAsFixed(1)} sat/vbyte',
                      style: context.font.labelMedium,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.radio_button_checked_outlined,
                color:
                    isSelected
                        ? context.colour.primary
                        : context.colour.surface,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomFeeSection(bool isSelected) {
    return InkWell(
      radius: 2,
      onTap:
          () => widget.onChanged(
            FeeEntity(type: FeeType.custom, feeRate: _customFeeRate),
          ),
      child: Material(
        elevation: isSelected ? 4 : 1,
        borderRadius: BorderRadius.circular(2),
        clipBehavior: Clip.hardEdge,
        color: context.colour.onSecondary,
        shadowColor: context.colour.secondary,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BBText('Custom Fee', style: context.font.headlineLarge),
                  Icon(
                    Icons.radio_button_checked_outlined,
                    color:
                        isSelected
                            ? context.colour.primary
                            : context.colour.surface,
                  ),
                ],
              ),
              const Gap(8),
              BBInputText(
                controller: _controller,
                value: _controller.text,
                onChanged: _onCustomChanged,
                onlyNumbers: true,
                rightIcon: Text('sats/vB', style: context.font.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
