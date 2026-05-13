import 'package:bb_mobile/features/import_mnemonic/presentation/cubit.dart';
import 'package:bb_mobile/features/import_mnemonic/presentation/state.dart';
import 'package:bb_mobile/features/import_mnemonic/ui/mnemonic_page.dart';
import 'package:bb_mobile/features/import_mnemonic/ui/select_purpose_page.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:bb_mobile/features/wallet/ui/wallet_router.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum ImportMnemonicRoute {
  importMnemonicHome('/import-mnemonic-home'),
  selectScriptType('/select-script-type');

  final String path;

  const ImportMnemonicRoute(this.path);
}

class ImportMnemonicRouter {
  static final route = ShellRoute(
    builder:
        (context, state, child) => BlocProvider<ImportMnemonicCubit>(
          create: (_) => locator<ImportMnemonicCubit>(),
          child: child,
        ),
    routes: [
      GoRoute(
        name: ImportMnemonicRoute.importMnemonicHome.name,
        path: ImportMnemonicRoute.importMnemonicHome.path,
        builder:
            (context, state) =>
                BlocListener<ImportMnemonicCubit, ImportMnemonicState>(
                  listenWhen:
                      (previous, current) =>
                          previous.mnemonic == null && current.mnemonic != null,
                  listener: (context, state) {
                    context.goNamed(ImportMnemonicRoute.selectScriptType.name);
                  },
                  child: const MnemonicPage(),
                ),
      ),

      GoRoute(
        name: ImportMnemonicRoute.selectScriptType.name,
        path: ImportMnemonicRoute.selectScriptType.path,
        builder: (context, state) {
          return BlocListener<ImportMnemonicCubit, ImportMnemonicState>(
            listenWhen:
                (previous, current) =>
                    previous.wallet == null && current.wallet != null,
            listener: (context, state) {
              // Trigger wallet refresh before navigating to home
              context.read<WalletBloc>().add(const WalletStarted());
              context.goNamed(WalletRoute.walletHome.name);

              // After recovery, check if user had a Lightning Address (non-blocking)
              final env = context.read<SettingsCubit>().state.environment ??
                  Environment.mainnet;
              _tryRecoverLightningAddress(env);
            },
            child: const SelectScriptTypePage(),
          );
        },
      ),
    ],
  );
}

void _tryRecoverLightningAddress(Environment environment) async {
  try {
    final facade = locator<LightningAddressFacade>();
    final address = await facade.recoverIfNeeded(
      environment: environment,
    );
    if (address != null) {
      debugPrint('Lightning Address recovered after import: $address');
    }
  } catch (e) {
    debugPrint('Lightning Address recovery after import failed: $e');
  }
}
