import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:flutter/material.dart';

/// Inline warning rendered while the automated backup toggle is OFF. Reused by
/// the consent dialog and the Get Paid settings screen.
///
/// The copy (`getPaidAutomatedBackupOffWarning`) is a locked string — do not
/// reword it here.
class AutomatedBackupOffWarning extends StatelessWidget {
  const AutomatedBackupOffWarning({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          color: context.appColors.error,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: BBText(
            context.loc.getPaidAutomatedBackupOffWarning,
            style: context.font.bodySmall,
            color: context.appColors.error,
          ),
        ),
      ],
    );
  }
}
