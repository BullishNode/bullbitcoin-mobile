import 'package:bb_mobile/features/wallet_manifest/presentation/wallet_manifest_settings_cubit.dart';
import 'package:bb_mobile/features/wallet_manifest/ui/wallet_manifest_settings_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

GoRoute walletManifestSettingsRoute({
  required String name,
  required String path,
  void Function(BuildContext context)? onWalletsRestored,
}) {
  return GoRoute(
    name: name,
    path: path,
    builder: (context, state) => BlocProvider(
      create: (_) => locator<WalletManifestSettingsCubit>()..load(),
      child: WalletManifestSettingsScreen(
        onWalletsRestored: onWalletsRestored == null
            ? null
            : () => onWalletsRestored(context),
      ),
    ),
  );
}
