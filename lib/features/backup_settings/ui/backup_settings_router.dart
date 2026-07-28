import 'package:bb_mobile/features/backup_settings/ui/screens/backup_options_screen.dart';
import 'package:bb_mobile/features/backup_settings/ui/screens/metadata_backup_options_screen.dart';
import 'package:go_router/go_router.dart';

enum BackupSettingsFlow { backup, test }

enum BackupSettingsSubroute {
  backupOptions('backup-options'),
  metadataBackupOptions('metadata-backup');

  final String path;

  const BackupSettingsSubroute(this.path);
}

class BackupSettingsSettingsRouter {
  static final route = GoRoute(
    name: BackupSettingsSubroute.backupOptions.name,
    path: BackupSettingsSubroute.backupOptions.path,
    builder: (context, state) {
      final flow =
          state.extra as BackupSettingsFlow? ?? BackupSettingsFlow.backup;
      return BackupOptionsScreen(flow: flow);
    },
  );

  static final metadataBackupRoute = GoRoute(
    name: BackupSettingsSubroute.metadataBackupOptions.name,
    path: BackupSettingsSubroute.metadataBackupOptions.path,
    builder: (context, state) => const MetadataBackupOptionsScreen(),
  );
}
