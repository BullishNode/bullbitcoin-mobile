import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/invoices/presentation/invoice_create_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

/// The Buy-style amount card for New Invoice. The entry denomination fixes the
/// invoice pricing (fiat → fiat-fixed, bitcoin → sat-fixed); this widget is
/// pure presentation on top of that — a big amount field with the active
/// denomination, a toggle to the other denomination, and a live approximate
/// equivalent line. There is deliberately NO Max button (no balance caps an
/// invoice).
class InvoiceAmountCard extends StatelessWidget {
  const InvoiceAmountCard({
    super.key,
    required this.controller,
    required this.mode,
    required this.bitcoinUnit,
    required this.fiatCurrency,
    required this.decimals,
    required this.equivalentLabel,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onToggleMode,
  });

  final TextEditingController controller;
  final InvoiceAmountMode mode;
  final BitcoinUnit bitcoinUnit;
  final String fiatCurrency;

  /// Fractional digits allowed for the active denomination (fiat precision, or
  /// the bitcoin unit's decimals). Zero means an integer-only field.
  final int decimals;
  final String? equivalentLabel;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleMode;

  String get _activeDenomination =>
      mode == InvoiceAmountMode.fiat ? _fiatLabel : bitcoinUnit.code;

  String get _otherDenomination =>
      mode == InvoiceAmountMode.fiat ? bitcoinUnit.code : _fiatLabel;

  String get _fiatLabel =>
      fiatCurrency.isEmpty ? '' : fiatCurrency.toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.loc.invoiceAmountLabel, style: context.font.bodyMedium),
        const Gap(4),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('invoice_amount_field'),
                        controller: controller,
                        enabled: enabled,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: decimals > 0,
                        ),
                        inputFormatters: decimals > 0
                            ? [
                                FilteringTextInputFormatter.allow(
                                  RegExp(
                                    r'^\d*\.?\d{0,'
                                    '$decimals'
                                    r'}',
                                  ),
                                ),
                              ]
                            : [FilteringTextInputFormatter.digitsOnly],
                        onChanged: onChanged,
                        style: context.font.displaySmall?.copyWith(
                          color: context.appColors.primary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: NumberFormat.decimalPatternDigits(
                            decimalDigits: decimals,
                          ).format(0),
                          hintStyle: context.font.displaySmall?.copyWith(
                            color: context.appColors.onSurfaceVariant,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const Gap(8),
                    Text(
                      _activeDenomination,
                      style: context.font.displaySmall?.copyWith(
                        color: context.appColors.primary,
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Row(
                  children: [
                    InkWell(
                      key: const Key('invoice_amount_toggle'),
                      onTap: enabled ? onToggleMode : null,
                      child: Icon(
                        Icons.swap_vert,
                        color: context.appColors.outline,
                      ),
                    ),
                    const Gap(8),
                    // The approximate equivalent when available, otherwise the
                    // denomination the toggle switches to.
                    Expanded(
                      child: Text(
                        equivalentLabel ?? _otherDenomination,
                        style: context.font.bodyMedium?.copyWith(
                          color: context.appColors.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const Gap(8),
          Text(
            context.loc.invoiceAmountError,
            style: context.font.labelLarge?.copyWith(
              color: context.appColors.error,
            ),
          ),
        ],
      ],
    );
  }
}
