import 'package:bb_mobile/features/backup_settings/ui/backup_settings_router.dart';
import 'package:bb_mobile/features/backup_settings/ui/screens/backup_settings_screen.dart';
import 'package:bb_mobile/features/backup_wallet/ui/backup_wallet_router.dart';
import 'package:bb_mobile/features/experimental/experimental_router.dart';
import 'package:bb_mobile/features/legacy_seed_view/presentation/legacy_seed_view_cubit.dart';
import 'package:bb_mobile/features/legacy_seed_view/ui/legacy_seed_view_screen.dart';
import 'package:bb_mobile/features/pin_code/ui/pin_code_setting_flow.dart';
import 'package:bb_mobile/features/settings/ui/screens/currency_settings_screen.dart';
import 'package:bb_mobile/features/settings/ui/screens/experimental_settings_screen.dart';
import 'package:bb_mobile/features/settings/ui/screens/language_settings_screen.dart';
import 'package:bb_mobile/features/settings/ui/screens/log_settings_screen.dart';
import 'package:bb_mobile/features/settings/ui/screens/settings_screen.dart';
import 'package:bb_mobile/features/settings/ui/screens/wallet_details_screen.dart';
import 'package:bb_mobile/features/settings/ui/screens/wallets_list_screen.dart';
import 'package:bb_mobile/features/test_wallet_backup/ui/test_wallet_backup_router.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum SettingsRoute {
  settings('/settings'),
  pinCode('pin-code'),
  language('language'),
  currency('currency'),
  backupSettings('backup-settings'),
  walletDetailsWalletList('wallet-details'),
  walletDetailsSelectedWallet(':walletId'),
  logs('logs'),
  legacySeeds('legacy-seeds'),
  experimental('experimental-settings');

  final String path;

  const SettingsRoute(this.path);
}

class SettingsRouter {
  static final route = GoRoute(
    name: SettingsRoute.settings.name,
    path: SettingsRoute.settings.path,
    builder: (context, state) => const SettingsScreen(),
    routes: [
      GoRoute(
        name: SettingsRoute.language.name,
        path: SettingsRoute.language.path,
        builder: (context, state) => const LanguageSettingsScreen(),
      ),
      GoRoute(
        path: SettingsRoute.pinCode.path,
        name: SettingsRoute.pinCode.name,
        builder: (context, state) => const PinCodeSettingFlow(),
      ),
      GoRoute(
        path: SettingsRoute.backupSettings.path,
        name: SettingsRoute.backupSettings.name,
        builder: (context, state) => const BackupSettingsScreen(),
        routes: [
          ...BackupSettingsSettingsRouter.routes,
          ...BackupWalletRouter.routes,
          ...TestWalletBackupRouter.routes,
        ],
      ),
      GoRoute(
        path: SettingsRoute.walletDetailsWalletList.path,
        name: SettingsRoute.walletDetailsWalletList.name,
        builder: (context, state) => const WalletsListScreen(),
      ),
      GoRoute(
        path: SettingsRoute.walletDetailsSelectedWallet.path,
        name: SettingsRoute.walletDetailsSelectedWallet.name,
        builder: (context, state) {
          final walletId = state.pathParameters['walletId']!;
          return WalletDetailsScreen(walletId: walletId);
        },
      ),
      GoRoute(
        path: SettingsRoute.logs.path,
        name: SettingsRoute.logs.name,
        builder: (context, state) => const LogSettingsScreen(),
      ),
      GoRoute(
        path: SettingsRoute.legacySeeds.path,
        name: SettingsRoute.legacySeeds.name,
        builder:
            (context, state) => BlocProvider(
              create: (_) => locator<LegacySeedViewCubit>(),
              child: const LegacySeedViewScreen(),
            ),
      ),
      GoRoute(
        path: SettingsRoute.currency.path,
        name: SettingsRoute.currency.name,
        builder: (context, state) => const CurrencySettingsScreen(),
      ),
      GoRoute(
        path: SettingsRoute.experimental.path,
        name: SettingsRoute.experimental.name,
        builder: (context, state) => const ExperimentalSettingsScreen(),
        routes: [ExperimentalRouterConfig.route],
      ),
    ],
  );
}
