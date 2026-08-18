import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/bottom_sheet/instructions_bottom_sheet.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:flutter/material.dart';

/// The POS "Instructions for staff" button: opens the owner's verbatim
/// instructions in the shared hardware-wallet instructions bottom sheet
/// (owner ruling 2026-07-24, superseding the earlier inline-expander
/// presentation — the expander rendered the copy below the fold near the
/// bottom of the scroll view, so tapping read as a dead button).
/// The copy is owner-authored (report #16), rendered exactly as written,
/// in order.
class PosStaffInstructions extends StatelessWidget {
  const PosStaffInstructions({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return BBButton.small(
      label: loc.posStaffInstructionsButton,
      onPressed: () => InstructionsBottomSheet.show(
        context,
        title: loc.posStaffInstructionsHeading,
        instructions: [
          loc.posStaffInstructionsTabletLine,
          loc.posStaffInstructionsPrintLine,
          loc.posStaffInstructionsStaffSteps,
          loc.posStaffInstructionsProTip,
          loc.posStaffInstructionsOwnerCloser,
        ],
      ),
      bgColor: context.appColors.surface,
      textColor: context.appColors.text,
      outlined: true,
    );
  }
}
