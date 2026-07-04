import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/ui/screens/remote_keychain_recovery_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum RemoteKeychainRecoveryRoute {
  getPaidRecovery('/get-paid-recovery');

  final String path;

  const RemoteKeychainRecoveryRoute(this.path);
}

class RemoteKeychainRecoveryRoutes {
  const RemoteKeychainRecoveryRoutes._();

  static final route = GoRoute(
    name: RemoteKeychainRecoveryRoute.getPaidRecovery.name,
    path: RemoteKeychainRecoveryRoute.getPaidRecovery.path,
    builder: (context, state) => BlocProvider(
      create: (_) => locator<RemoteKeychainRecoveryCubit>(),
      child: RemoteKeychainRecoveryScreen(
        fromOnboarding: state.uri.queryParameters['from'] == 'onboarding',
      ),
    ),
  );
}
