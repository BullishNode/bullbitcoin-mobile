import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/widgets/automated_backup_off_warning.dart';
import 'package:flutter/material.dart';

/// Result of the automated-backup consent dialog. [accepted] is true only when
/// the user tapped Continue; [automatedBackupEnabled] carries the toggle value
/// chosen in the dialog.
typedef AutomatedBackupConsentResult = ({
  bool accepted,
  bool automatedBackupEnabled,
});

/// Blocking consent dialog shown once before the first BIP85-derived wallet
/// creation (decisions [3]/[A]). The dialog is "dumb": it collects the toggle
/// value and returns a result; persistence happens in the public gate. The
/// body copy and the OFF warning are locked strings.
class AutomatedBackupConsentDialog extends StatefulWidget {
  const AutomatedBackupConsentDialog({super.key});

  static Future<AutomatedBackupConsentResult> show(BuildContext context) async {
    final result = await showDialog<AutomatedBackupConsentResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AutomatedBackupConsentDialog(),
    );
    // Barrier is non-dismissible; a system-back pop returns null and is treated
    // as declined — the ack is persisted only on Continue.
    return result ?? (accepted: false, automatedBackupEnabled: true);
  }

  @override
  State<AutomatedBackupConsentDialog> createState() =>
      _AutomatedBackupConsentDialogState();
}

class _AutomatedBackupConsentDialogState
    extends State<AutomatedBackupConsentDialog> {
  bool _automatedBackupEnabled = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.getPaidAutomatedBackupConsentTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.loc.getPaidAutomatedBackupConsentBody),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.loc.getPaidAutomatedBackupToggleLabel),
            value: _automatedBackupEnabled,
            onChanged: (value) =>
                setState(() => _automatedBackupEnabled = value),
          ),
          if (!_automatedBackupEnabled) ...[
            const SizedBox(height: 8),
            const AutomatedBackupOffWarning(),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop((
            accepted: true,
            automatedBackupEnabled: _automatedBackupEnabled,
          )),
          child: Text(context.loc.getPaidAutomatedBackupConsentContinue),
        ),
      ],
    );
  }
}
