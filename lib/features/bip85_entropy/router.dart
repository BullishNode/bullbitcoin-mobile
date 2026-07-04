import 'package:bb_mobile/features/bip85_entropy/bip85_home_page.dart';
import 'package:bb_mobile/features/bip85_entropy/presentation/cubit.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:bb_mobile/features/wallet/ui/wallet_router.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum Bip85EntropyRoute {
  bip85Home('/bip85-home');

  final String path;

  const Bip85EntropyRoute(this.path);
}

class Bip85EntropyRouter {
  static final route = ShellRoute(
    builder: (context, state, child) =>
        BlocProvider(create: (_) => locator<Bip85EntropyCubit>(), child: child),
    routes: [
      GoRoute(
        name: Bip85EntropyRoute.bip85Home.name,
        path: Bip85EntropyRoute.bip85Home.path,
        // Defense in depth: this dev-only screen re-derives and displays raw
        // BIP85 entropy, so guard the route itself, not just the settings entry
        // that links to it. Any other entry (deep link, programmatic push) when
        // superuser + dev mode are not both on is bounced to the wallet home.
        redirect: (context, state) {
          final settings = locator<SettingsCubit>().state;
          final allowed =
              (settings.isSuperuser ?? false) &&
              (settings.isDevModeEnabled ?? false);
          return allowed ? null : WalletRoute.walletHome.path;
        },
        builder: (context, state) => const Bip85HomePage(),
        routes: const [],
      ),
    ],
  );
}
