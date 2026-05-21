import 'package:bb_mobile/features/get_paid/btcpay/ui/btcpay_pairing_screen.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/invoices_router.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/payment_page_router.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_settings_cubit.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_dashboard_screen.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_settings_screen.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_routes.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum GetPaidRoute {
  dashboard('/get-paid'),
  getPaidSettings('settings'),
  btcpayPairing('btcpay');

  final String path;

  const GetPaidRoute(this.path);
}

class GetPaidRouter {
  static final settingsRoute = GoRoute(
    name: GetPaidRoute.getPaidSettings.name,
    path: '/get-paid/${GetPaidRoute.getPaidSettings.path}',
    builder: (context, state) => BlocProvider(
      create: (_) => locator<GetPaidSettingsCubit>()..load(),
      child: GetPaidSettingsScreen(
        onExternalReceiveSettingsChanged: () =>
            _notifyExternalReceiveSettingsChanged(context),
        onExternalReceiveWalletsCreated: () =>
            _notifyExternalReceiveWalletsCreated(context),
      ),
    ),
  );

  static final route = GoRoute(
    name: GetPaidRoute.dashboard.name,
    path: GetPaidRoute.dashboard.path,
    builder: (context, state) => BlocProvider(
      create: (_) => locator<GetPaidDashboardCubit>(),
      child: GetPaidDashboardScreen(
        onExternalReceiveWalletsCreated: () =>
            _notifyExternalReceiveWalletsCreated(context),
      ),
    ),
    routes: [
      LightningAddressRoutes.manageRoute,
      GoRoute(
        name: GetPaidRoute.btcpayPairing.name,
        path: GetPaidRoute.btcpayPairing.path,
        builder: (context, state) => BlocProvider(
          create: (_) => locator<BtcpayPairingCubit>()..load(),
          child: const BtcpayPairingScreen(),
        ),
      ),
      PaymentPageRouter.createRoute,
      PaymentPageRouter.editorRoute,
      ...InvoicesRouter.routes,
    ],
  );

  static void _notifyExternalReceiveSettingsChanged(BuildContext context) {
    context.read<WalletBloc>().add(
      const WalletExternalReceiveSettingsChanged(),
    );
  }

  static void _notifyExternalReceiveWalletsCreated(BuildContext context) {
    context.read<WalletBloc>().add(const WalletListChanged());
  }
}
