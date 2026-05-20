import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/lightning_address/ui/lightning_address_settings_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class LightningAddressRoutes {
  static GoRoute get manageRoute => GoRoute(
    name: LightningAddressFacade.manageRouteName,
    path: 'lightning-address',
    builder: (context, state) => BlocProvider(
      create: (_) => locator<LightningAddressCubit>(),
      child: const LightningAddressSettingsScreen(),
    ),
  );
}
