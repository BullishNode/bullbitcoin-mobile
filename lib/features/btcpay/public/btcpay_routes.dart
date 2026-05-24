import 'package:bb_mobile/features/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/btcpay/ui/screens/btcpay_settings_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum BtcpayRoute {
  settings('btcpay');

  final String path;

  const BtcpayRoute(this.path);
}

class BtcpayRoutes {
  const BtcpayRoutes._();

  static final route = GoRoute(
    name: BtcpayRoute.settings.name,
    path: BtcpayRoute.settings.path,
    builder: (context, state) => BlocProvider(
      create: (_) => locator<BtcpayPairingCubit>(),
      child: const BtcpaySettingsScreen(),
    ),
  );
}
