import 'dart:async';

import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_cubit.dart';
import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_page.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletManifestFacade extends Mock implements WalletManifestFacade {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const CreateManualBip85WalletsCommand(
        networkSelection: ManualBip85WalletNetworkSelection.liquid,
        liquidLabel: 'Liquid',
      ),
    );
  });

  testWidgets('pops true after successful wallet creation', (tester) async {
    final walletManifest = _MockWalletManifestFacade();
    when(
      () => walletManifest.createManualBip85Wallets(any()),
    ).thenAnswer((_) async => _result());

    await tester.pumpWidget(_harness(walletManifest));
    await tester.tap(find.text('Open create'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Savings');

    await tester.tap(find.text('Create wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Create returned true'), findsOneWidget);
  });

  testWidgets('blocks back while wallet creation is in flight', (tester) async {
    final walletManifest = _MockWalletManifestFacade();
    final completer = Completer<CreateManualBip85WalletsResult>();
    when(
      () => walletManifest.createManualBip85Wallets(any()),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_harness(walletManifest));
    await tester.tap(find.text('Open create'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Savings');
    await tester.tap(find.text('Create wallet'));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Create new wallet'), findsOneWidget);
    expect(
      find.text('Wait for wallet creation to finish before leaving.'),
      findsOneWidget,
    );

    completer.complete(_result());
    await tester.pumpAndSettle();
  });

  testWidgets('keeps manifest publish warnings visible before popping', (
    tester,
  ) async {
    final walletManifest = _MockWalletManifestFacade();
    when(() => walletManifest.createManualBip85Wallets(any())).thenAnswer(
      (_) async => const CreateManualBip85WalletsResult(
        index: 3,
        wallets: [
          CreateManualBip85WalletResult(
            network: WalletManifestNetwork.liquid,
            walletId: 'wallet-id',
            label: 'Savings',
          ),
        ],
        manifestPublishFailed: true,
      ),
    );

    await tester.pumpWidget(_harness(walletManifest));
    await tester.tap(find.text('Open create'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Savings');

    await tester.tap(find.text('Create wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Create new wallet'), findsWidgets);
    expect(find.textContaining('Manifest update failed'), findsOneWidget);
    expect(find.text('Create returned true'), findsNothing);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Create returned true'), findsOneWidget);
  });

  testWidgets('validates manual recovery index', (tester) async {
    final walletManifest = _MockWalletManifestFacade();
    await tester.pumpWidget(_harness(walletManifest));
    await tester.tap(find.text('Open create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select recovery index manually'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create wallet'));
    await tester.pump();

    expect(find.text('Enter a valid index'), findsOneWidget);
    verifyNever(() => walletManifest.createManualBip85Wallets(any()));
  });
}

Widget _harness(WalletManifestFacade walletManifest) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _ParentPage(),
        routes: [
          GoRoute(
            name: 'create',
            path: 'create',
            builder: (context, state) => BlocProvider(
              create: (_) =>
                  CreateBip85WalletCubit(walletManifest: walletManifest),
              child: const CreateBip85WalletPage(),
            ),
          ),
        ],
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

class _ParentPage extends StatefulWidget {
  const _ParentPage();

  @override
  State<_ParentPage> createState() => _ParentPageState();
}

class _ParentPageState extends State<_ParentPage> {
  bool? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () async {
              result = await context.pushNamed<bool>('create');
              setState(() {});
            },
            child: const Text('Open create'),
          ),
          if (result == true) const Text('Create returned true'),
        ],
      ),
    );
  }
}

CreateManualBip85WalletsResult _result() {
  return const CreateManualBip85WalletsResult(
    index: 3,
    wallets: [
      CreateManualBip85WalletResult(
        network: WalletManifestNetwork.liquid,
        walletId: 'wallet-id',
        label: 'Savings',
      ),
    ],
    manifestPublishFailed: false,
  );
}
