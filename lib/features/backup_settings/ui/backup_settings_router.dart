import 'package:bb_mobile/features/backup_settings/ui/screens/backup_options_screen.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum BackupSettingsFlow { backup, test }

enum BackupSettingsSubroute {
  backupOptions('backup-options'),
  walletManifest('wallet-manifest');

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

  static final walletManifestRoute = walletManifestSettingsRoute(
    name: BackupSettingsSubroute.walletManifest.name,
    path: BackupSettingsSubroute.walletManifest.path,
    onWalletsRestored: _notifyWalletsRestored,
  );

  static void _notifyWalletsRestored(BuildContext context) {
    context.read<WalletBloc>().add(const WalletListChanged());
  }
}
