import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart' show Icons;

/// Warning-tinted attention banner shown on the Get Paid hub when one or more
/// payments need recovery. Tapping it opens the stuck-payments list.
///
/// Copy is intentionally reassuring: the funds are safe on the server; the
/// merchant just needs to recover them. (l10n keys land in Phase 3.)
class StuckPaymentBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const StuckPaymentBanner({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final label = context.loc.stuckPaymentsBannerLabel(count);
    return BullBorderedTile(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      backgroundColor: colors.warningContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BullIcon(Icons.warning_amber_rounded, size: 24, color: colors.warning),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.bullText.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const Gap(4),
                Text(
                  context.loc.stuckPaymentsBannerBody,
                  style: context.bullText.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          BullIcon(Icons.chevron_right, size: 20, color: colors.textMuted),
        ],
      ),
    );
  }
}
