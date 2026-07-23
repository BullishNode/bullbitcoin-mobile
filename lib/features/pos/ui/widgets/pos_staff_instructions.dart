import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

/// The POS "Instructions for staff" section: a button that expands the owner's
/// verbatim instructions BELOW it (the owner's requested presentation — not a
/// bottom sheet). The copy is owner-authored (report #16) and rendered exactly
/// as written, in order.
class PosStaffInstructions extends StatefulWidget {
  const PosStaffInstructions({super.key});

  @override
  State<PosStaffInstructions> createState() => _PosStaffInstructionsState();
}

class _PosStaffInstructionsState extends State<PosStaffInstructions> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final loc = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BullBorderedTile(
          onTap: () => setState(() => _expanded = !_expanded),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  loc.posStaffInstructionsButton,
                  style: context.font.bodyMedium,
                ),
              ),
              BullIcon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 22,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const Gap(12),
          Text(
            loc.posStaffInstructionsHeading,
            style: context.font.titleMedium,
          ),
          const Gap(12),
          // The tablet + print sentences are one grouped paragraph (two lines).
          Text(
            loc.posStaffInstructionsTabletLine,
            style: context.font.bodyMedium,
          ),
          const Gap(4),
          Text(
            loc.posStaffInstructionsPrintLine,
            style: context.font.bodyMedium,
          ),
          const Gap(12),
          Text(
            loc.posStaffInstructionsStaffSteps,
            style: context.font.bodyMedium,
          ),
          const Gap(12),
          Text(loc.posStaffInstructionsProTip, style: context.font.bodyMedium),
          const Gap(12),
          Text(
            loc.posStaffInstructionsOwnerCloser,
            style: context.font.bodyMedium,
          ),
        ],
      ],
    );
  }
}
