import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/widgets/automated_backup_consent_dialog.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/widgets.dart';

/// Blocking consent gate for the first BIP85-derived wallet creation
/// (decisions [3]/[A]). Returns true when creation may proceed; no-ops to true
/// once the disclosure has been acknowledged.
///
/// Fail-closed toward consent: when the ack cannot be confirmed the dialog is
/// shown rather than silently proceeding, and a storage failure while
/// persisting the ack returns false so the consent is never lost (creation
/// proceeds only when the ack durably exists).
Future<bool> ensureAutomatedBackupConsent(BuildContext context) async {
  final facade = locator<GetPaidSettingsFacade>();
  try {
    final settings = await facade.getSettings();
    if (settings.backupDisclosureAcknowledged) return true;
  } catch (e, stack) {
    log.warning('AUTOBACKUP: consent lookup failed', error: e, trace: stack);
  }
  if (!context.mounted) return false;

  final result = await AutomatedBackupConsentDialog.show(context);
  if (!result.accepted) return false;

  try {
    await facade.acknowledgeBackupDisclosure(
      automatedBackupEnabled: result.automatedBackupEnabled,
    );
    return true;
  } catch (e, stack) {
    log.warning('AUTOBACKUP: consent persistence failed', error: e, trace: stack);
    return false;
  }
}
