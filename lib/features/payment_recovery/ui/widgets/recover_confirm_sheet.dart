import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

/// Confirm sheet for one-tap recovery. States the amount and the destination
/// (the merchant's default Bitcoin wallet), and requires the merchant to tick
/// the out-of-band acknowledgement before the Confirm button enables — recovery
/// moves coins to the merchant, it does NOT refund the customer. (Copy inline
/// pending l10n.)
///
/// Returns `true` when the merchant confirms, `null`/`false` otherwise.
Future<bool?> showRecoverConfirmSheet(
  BuildContext context, {
  required String amountLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RecoverConfirmSheet(amountLabel: amountLabel),
  );
}

class _RecoverConfirmSheet extends StatefulWidget {
  final String amountLabel;
  const _RecoverConfirmSheet({required this.amountLabel});

  @override
  State<_RecoverConfirmSheet> createState() => _RecoverConfirmSheetState();
}

class _RecoverConfirmSheetState extends State<_RecoverConfirmSheet> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.loc.recoverConfirmTitle(widget.amountLabel),
            style: context.bullText.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          const Gap(8),
          Text(
            context.loc.recoverConfirmBody,
            style: context.bullText.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          const Gap(16),
          InkWell(
            onTap: () => setState(() => _acknowledged = !_acknowledged),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _acknowledged,
                  onChanged: (v) => setState(() => _acknowledged = v ?? false),
                ),
                const Gap(4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      context.loc.recoverConfirmCheckbox,
                      style: context.bullText.bodySmall?.copyWith(
                        color: colors.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(16),
          BullButton.big(
            label: context.loc.recoverConfirmButton,
            onPressed: () {
              if (_acknowledged) Navigator.of(context).pop(true);
            },
            bgColor: colors.primary,
            textColor: colors.onPrimary,
            disabled: !_acknowledged,
          ),
        ],
      ),
    );
  }
}
