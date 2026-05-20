import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_page.dart';
import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_cubit.dart';
import 'package:bb_mobile/features/import_wallet/import_wallet_page.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum ImportWalletRoute {
  importWalletHome('/import-wallet-home'),
  createBip85Wallet('create-bip85-wallet');

  final String path;

  const ImportWalletRoute(this.path);
}

class ImportWalletRouter {
  static final route = GoRoute(
    name: ImportWalletRoute.importWalletHome.name,
    path: ImportWalletRoute.importWalletHome.path,
    builder: (context, state) => ImportWalletPage(
      onWalletsChanged: () =>
          context.read<WalletBloc>().add(const WalletStarted()),
    ),
    routes: [
      GoRoute(
        name: ImportWalletRoute.createBip85Wallet.name,
        path: ImportWalletRoute.createBip85Wallet.path,
        builder: (context, state) => BlocProvider(
          create: (_) => CreateBip85WalletCubit(
            walletManifest: locator<WalletManifestFacade>(),
          ),
          child: const CreateBip85WalletPage(),
        ),
      ),
    ],
  );
}
