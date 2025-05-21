import 'package:bb_mobile/core/payjoin/domain/entity/payjoin.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/receive/presentation/bloc/receive_bloc.dart';
import 'package:bb_mobile/features/receive/ui/screens/receive_amount_screen.dart';
import 'package:bb_mobile/features/receive/ui/screens/receive_details_screen.dart';
import 'package:bb_mobile/features/receive/ui/screens/receive_payjoin_in_progress_screen.dart';
import 'package:bb_mobile/features/receive/ui/screens/receive_payment_in_progress_screen.dart';
import 'package:bb_mobile/features/receive/ui/screens/receive_payment_received_screen.dart';
import 'package:bb_mobile/features/receive/ui/screens/receive_qr_screen.dart';
import 'package:bb_mobile/features/receive/ui/screens/receive_scaffold.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum ReceiveRoute {
  receiveBitcoin('/receive-bitcoin'),
  receiveLightning('/receive-lightning'),
  receiveLiquid('/receive-liquid'),
  amount('amount'),
  qr('qr'),
  payjoinInProgress('payjoin-in-progress'),
  paymentInProgress('payment-in-progress'),
  paymentReceived('payment-received'),
  details('details');

  final String path;

  const ReceiveRoute(this.path);
}

class ReceiveRouter {
  static final GlobalKey<NavigatorState> _shellNavigatorKey =
      GlobalKey<NavigatorState>();

  static final route = ShellRoute(
    navigatorKey: _shellNavigatorKey,
    builder: (context, state, child) {
      // Pass a preselected wallet to the receive bloc if one is set in the URI
      //  of the incoming route
      final wallet = state.extra is Wallet ? state.extra! as Wallet : null;

      // Make sure the ReceiveScaffold with the network selection is not rebuild
      //  when switching networks, so keep it outside of the BlocProvider.
      return ReceiveScaffold(
        wallet: wallet,
        child: BlocProvider<ReceiveBloc>(
          create: (_) => locator<ReceiveBloc>(param1: wallet),
          child: MultiBlocListener(
            listeners: [
              BlocListener<ReceiveBloc, ReceiveState>(
                listenWhen:
                    (previous, current) =>
                        // makes sure it doesn't go from payment received to payment in progress again
                        previous.isPaymentReceived != true &&
                        previous.isPaymentInProgress != true &&
                        current.isPaymentInProgress == true,
                listener: (context, state) {
                  final bloc = context.read<ReceiveBloc>();
                  final type = state.type;
                  final location = GoRouter.of(context).state.matchedLocation;

                  // For a Payjoin or Lightning receive, show the payment in progress screen
                  //  when the payjoin is requested or swap is claimable.
                  // Since the payment in progress route is outside of the ShellRoute,
                  // it uses the root navigator and so doesn't have the ReceiveBloc
                  //  in the context. We need to pass it as an extra parameter.
                  if (type == ReceiveType.bitcoin &&
                      state.payjoin?.status == PayjoinStatus.requested) {
                    context.go(
                      '$location/${ReceiveRoute.payjoinInProgress.path}',
                      extra: bloc,
                    );
                  } else if (type == ReceiveType.lightning) {
                    context.go(
                      '$location/${ReceiveRoute.paymentInProgress.path}',
                      extra: bloc,
                    );
                  }
                },
              ),
              BlocListener<ReceiveBloc, ReceiveState>(
                listenWhen:
                    (previous, current) =>
                        previous.isPaymentReceived != true &&
                        current.isPaymentReceived == true,
                listener: (context, state) {
                  final bloc = context.read<ReceiveBloc>();
                  final matched = GoRouter.of(context).state.matchedLocation;
                  final type = state.type;

                  final path = switch (type) {
                    ReceiveType.lightning =>
                      '$matched/${ReceiveRoute.paymentReceived.path}',
                    _ => '$matched/${ReceiveRoute.details.path}',
                  };

                  context.go(path, extra: bloc);
                },
              ),
            ],
            child: child,
          ),
        ),
      );
    },
    routes: [
      // Bitcoin Receive
      GoRoute(
        path: ReceiveRoute.receiveBitcoin.path,
        pageBuilder: (context, state) {
          // This is the entry route for the bitcoin receive flow when coming from
          // another receive network (lightning or liquid) or from a different flow.
          // So we should start the bitcoin flow here if the state is not already
          //  in the bitcoin flow.
          final bloc = context.read<ReceiveBloc>();
          if (bloc.state.type != ReceiveType.bitcoin) {
            bloc.add(const ReceiveBitcoinStarted());
          }
          final wallet = state.extra is Wallet ? state.extra! as Wallet : null;
          return NoTransitionPage(child: ReceiveQrPage(wallet: wallet));
        },
        routes: [
          GoRoute(
            path: ReceiveRoute.amount.path,
            pageBuilder:
                (context, state) =>
                    const NoTransitionPage(child: ReceiveAmountScreen()),
          ),
          GoRoute(
            path: ReceiveRoute.payjoinInProgress.path,
            parentNavigatorKey: AppRouter.rootNavigatorKey,
            builder: (context, state) {
              final bloc = state.extra! as ReceiveBloc;

              return BlocProvider.value(
                value: bloc,
                child: const ReceivePayjoinInProgressScreen(),
              );
            },
            routes: [
              GoRoute(
                path: ReceiveRoute.details.path,
                parentNavigatorKey: AppRouter.rootNavigatorKey,
                builder: (context, state) {
                  final bloc = state.extra! as ReceiveBloc;

                  return BlocProvider.value(
                    value: bloc,
                    child: const ReceiveDetailsScreen(),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: ReceiveRoute.details.path,
            parentNavigatorKey: AppRouter.rootNavigatorKey,
            builder: (context, state) {
              final bloc = state.extra! as ReceiveBloc;

              return BlocProvider.value(
                value: bloc,
                child: const ReceiveDetailsScreen(),
              );
            },
          ),
        ],
      ),
      // Lightning receive
      GoRoute(
        path: ReceiveRoute.receiveLightning.path,
        pageBuilder: (context, state) {
          // This is the entry route for the lightning receive flow.
          // We need to check if the state is already in the lightning flow,
          //  otherwise, when coming from another receive network or flow,
          //  we need to start it here.
          final bloc = context.read<ReceiveBloc>();
          if (bloc.state.type != ReceiveType.lightning) {
            bloc.add(const ReceiveLightningStarted());
          }
          return NoTransitionPage(
            child: ReceiveAmountScreen(
              onContinueNavigation:
                  () => context.push(
                    '${state.matchedLocation}/${ReceiveRoute.qr.path}',
                    extra: state.extra,
                  ),
            ),
          );
        },
        routes: [
          GoRoute(
            path: ReceiveRoute.qr.path,
            pageBuilder: (context, state) {
              final wallet =
                  state.extra is Wallet ? state.extra! as Wallet : null;
              return NoTransitionPage(child: ReceiveQrPage(wallet: wallet));
            },
            routes: [
              GoRoute(
                path: ReceiveRoute.amount.path,
                pageBuilder:
                    (context, state) =>
                        const NoTransitionPage(child: ReceiveAmountScreen()),
              ),
              GoRoute(
                path: ReceiveRoute.paymentInProgress.path,
                parentNavigatorKey: AppRouter.rootNavigatorKey,
                builder: (context, state) {
                  final bloc = state.extra! as ReceiveBloc;

                  return BlocProvider.value(
                    value: bloc,
                    child: const ReceivePaymentInProgressScreen(),
                  );
                },
                routes: [
                  GoRoute(
                    path: ReceiveRoute.paymentReceived.path,
                    parentNavigatorKey: AppRouter.rootNavigatorKey,
                    builder: (context, state) {
                      final bloc = state.extra! as ReceiveBloc;

                      return BlocProvider.value(
                        value: bloc,
                        child: const ReceivePaymentReceivedScreen(),
                      );
                    },
                    routes: [
                      GoRoute(
                        path: ReceiveRoute.details.path,
                        parentNavigatorKey: AppRouter.rootNavigatorKey,
                        builder: (context, state) {
                          final bloc = state.extra! as ReceiveBloc;

                          return BlocProvider.value(
                            value: bloc,
                            child: const ReceiveDetailsScreen(),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Liquid receive
      GoRoute(
        path: ReceiveRoute.receiveLiquid.path,
        pageBuilder: (context, state) {
          // This is the entry route for the liquid receive flow when coming from
          // another receive network (lightning or bitcoin) or from a different flow.
          // So if the state is already in the liquid flow, we don't have to do
          //  anything, else we need to start it here.
          final bloc = context.read<ReceiveBloc>();
          if (bloc.state.type != ReceiveType.liquid) {
            bloc.add(const ReceiveLiquidStarted());
          }

          final wallet = state.extra is Wallet ? state.extra! as Wallet : null;
          return NoTransitionPage(child: ReceiveQrPage(wallet: wallet));
        },
        routes: [
          GoRoute(
            path: ReceiveRoute.amount.path,
            pageBuilder:
                (context, state) =>
                    const NoTransitionPage(child: ReceiveAmountScreen()),
          ),
          GoRoute(
            path: ReceiveRoute.details.path,
            parentNavigatorKey: AppRouter.rootNavigatorKey,
            builder: (context, state) {
              final bloc = state.extra! as ReceiveBloc;

              return BlocProvider.value(
                value: bloc,
                child: const ReceiveDetailsScreen(),
              );
            },
          ),
        ],
      ),
    ],
  );

  // Test example for stateful navigation with independent blocs as we should
  // have in the future for the receive flow.
  /*
  static final statefulTestRoute = StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => ScaffoldWithNavBar(shell: shell),
    branches: [
      // Branch A with Bloc scoped using ShellRoute
      StatefulShellBranch(
        initialLocation: '/a',
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              return BlocProvider(create: (_) => CounterBloc(), child: child);
            },
            routes: [
              GoRoute(
                path: '/a',
                builder: (context, state) => const TabAScreen(),
                routes: [
                  GoRoute(
                    path: 'details',
                    builder: (context, state) => const TabADetailsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Branch B with separate Bloc
      StatefulShellBranch(
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              return BlocProvider(create: (_) => CounterBloc(), child: child);
            },
            routes: [
              GoRoute(
                path: '/b',
                builder: (context, state) => const TabBScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );*/
}

/*
// Components for the stateful test route
class TabAScreen extends StatelessWidget {
  const TabAScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<CounterBloc>().state;

    return Scaffold(
      appBar: AppBar(title: const Text('Tab A')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Counter A: $count', style: const TextStyle(fontSize: 24)),
            ElevatedButton(
              onPressed: () => context.read<CounterBloc>().increment(),
              child: const Text('Increment A'),
            ),
            ElevatedButton(
              onPressed: () => context.push('/a/details'),
              child: const Text('Go to A Details'),
            ),
          ],
        ),
      ),
    );
  }
}

class TabADetailsScreen extends StatelessWidget {
  const TabADetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<CounterBloc>().state;
    return Scaffold(
      appBar: AppBar(title: const Text('A Details')),
      body: Center(child: Text('Counter A (in details): $count')),
    );
  }
}

class TabBScreen extends StatelessWidget {
  const TabBScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<CounterBloc>().state;

    return Scaffold(
      appBar: AppBar(title: const Text('Tab B')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Counter B: $count', style: const TextStyle(fontSize: 24)),
            ElevatedButton(
              onPressed: () => context.read<CounterBloc>().increment(),
              child: const Text('Increment B'),
            ),
          ],
        ),
      ),
    );
  }
}

class CounterBloc extends Cubit<int> {
  CounterBloc() : super(0);

  void increment() => emit(state + 1);
}

class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell shell;
  const ScaffoldWithNavBar({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shell Navigation Example'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_left),
          onPressed: () {
            GoRouter.of(context).state.matchedLocation == '/a' ||
                    GoRouter.of(context).state.matchedLocation == '/b'
                ? context.pop()
                : GoRouter.of(
                  shell.shellRouteContext.navigatorKey.currentContext!,
                ).pop();
          },
        ),
      ),
      body: shell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: shell.currentIndex,
        onTap: shell.goBranch,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.looks_one), label: 'Tab A'),
          BottomNavigationBarItem(icon: Icon(Icons.looks_two), label: 'Tab B'),
        ],
      ),
    );
  }
}
*/
