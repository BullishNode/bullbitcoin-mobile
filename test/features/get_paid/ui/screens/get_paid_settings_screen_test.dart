import 'dart:async';

import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_settings_cubit.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_settings_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockExternalReceiveWalletsFacade extends Mock
    implements ExternalReceiveWalletsFacade {}

void main() {
  late _MockGetSettingsUsecase getSettings;
  late _MockExternalReceiveWalletsFacade externalReceiveWallets;

  setUpAll(() {
    registerFallbackValue(ExternalReceiveWalletPurpose.paymentPage);
    registerFallbackValue(
      ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(isTestnet: false),
    );
  });

  setUp(() {
    getSettings = _MockGetSettingsUsecase();
    externalReceiveWallets = _MockExternalReceiveWalletsFacade();
    when(() => getSettings.execute()).thenAnswer((_) async => _settings());
    when(
      () => externalReceiveWallets.shouldAutoSweepForAccount(any()),
    ).thenAnswer((_) async => true);
    when(
      () => externalReceiveWallets.isHiddenOnHomeForAccount(any()),
    ).thenAnswer((_) async => true);
    when(
      () => externalReceiveWallets.setAutoSweepForAccount(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => externalReceiveWallets.setHiddenOnHomeForAccount(any(), any()),
    ).thenAnswer((_) async {});
  });

  testWidgets('does not restore wallets on load', (tester) async {
    await tester.pumpWidget(_harness(getSettings, externalReceiveWallets));
    await tester.pumpAndSettle();

    expect(find.text('Get Paid settings'), findsOneWidget);
    expect(find.text('Lightning Address'), findsOneWidget);
    expect(find.text('Payment Page'), findsOneWidget);
    expect(find.text('BTCPay Liquid'), findsOneWidget);
    expect(find.text('Auto-sweep to default wallet'), findsWidgets);
    expect(find.text('Hide wallet on Home'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('BTCPay Bitcoin'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BTCPay Bitcoin'), findsOneWidget);
    await _scrollToRecoverWallets(tester);
    expect(find.text('Recover Get Paid wallets'), findsOneWidget);
    expect(
      find.text(
        'Checks reserved Get Paid wallets for this seed and recreates missing local wallets. Empty recreated wallets may still be added to sync.',
      ),
      findsOneWidget,
    );
    verify(() => getSettings.execute()).called(1);
    verifyNever(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: Environment.mainnet,
      ),
    );
  });

  testWidgets('shows per-wallet restore result after explicit action', (
    tester,
  ) async {
    var refreshCount = 0;
    when(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: Environment.mainnet,
      ),
    ).thenAnswer((_) async => _result());

    await tester.pumpWidget(
      _harness(
        getSettings,
        externalReceiveWallets,
        onExternalReceiveWalletsCreated: () => refreshCount += 1,
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToRecoverWallets(tester);
    await tester.tap(find.text('Recover Get Paid wallets'));
    await tester.pumpAndSettle();

    expect(find.text('Recover Get Paid wallets?'), findsOneWidget);
    expect(
      find.text(
        'This checks Lightning Address, Payment Page, and BTCPay receive wallets for this seed and recreates missing local wallets. Recreated wallets are kept even if they are empty, which can make future wallet syncs slower. Recreated or repaired wallets may also update the encrypted wallet manifest on Nostr.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Recover wallets'));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Wallet recovery needs attention'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Wallet recovery needs attention'), findsOneWidget);
    expect(find.text('Lightning Address Liquid'), findsOneWidget);
    expect(find.text('Payment Page Liquid'), findsOneWidget);
    expect(find.text('BTCPay Bitcoin'), findsWidgets);
    expect(find.text('Default wallet is unavailable'), findsOneWidget);
    expect(refreshCount, 1);
  });

  testWidgets('blocks app bar and system back while recovery is running', (
    tester,
  ) async {
    final completer = Completer<List<ExternalReceiveWalletRestoreOutcome>>();
    when(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: Environment.mainnet,
      ),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_harness(getSettings, externalReceiveWallets));
    await tester.pumpAndSettle();
    await _scrollToRecoverWallets(tester);
    await tester.tap(find.text('Recover Get Paid wallets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recover wallets'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(find.text('Get Paid settings'), findsOneWidget);
    expect(
      find.text('Wait for Get Paid wallet recovery to finish before leaving.'),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Get Paid settings'), findsOneWidget);
    expect(
      find.text('Wait for Get Paid wallet recovery to finish before leaving.'),
      findsOneWidget,
    );

    completer.complete(_result());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('does not restore wallets when confirmation is cancelled', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(getSettings, externalReceiveWallets));
    await tester.pumpAndSettle();
    await _scrollToRecoverWallets(tester);
    await tester.tap(find.text('Recover Get Paid wallets'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: Environment.mainnet,
      ),
    );
  });

  testWidgets('updates Lightning Address wallet settings', (tester) async {
    await tester.pumpWidget(_harness(getSettings, externalReceiveWallets));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    verify(
      () => externalReceiveWallets.setAutoSweepForAccount(
        ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
          isTestnet: false,
        ),
        false,
      ),
    ).called(1);
  });

  testWidgets(
    'hide setting refreshes external receive wallet visibility only',
    (tester) async {
      var refreshCount = 0;
      await tester.pumpWidget(
        _harness(
          getSettings,
          externalReceiveWallets,
          onExternalReceiveSettingsChanged: () => refreshCount += 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).at(1));
      await tester.pump();

      verify(
        () => externalReceiveWallets.setHiddenOnHomeForAccount(
          ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
            isTestnet: false,
          ),
          false,
        ),
      ).called(1);
      expect(refreshCount, 1);
    },
  );

  testWidgets('does not refresh wallet visibility when hide save fails', (
    tester,
  ) async {
    when(
      () => externalReceiveWallets.setHiddenOnHomeForAccount(
        ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
          isTestnet: false,
        ),
        false,
      ),
    ).thenThrow(Exception('storage locked'));

    var refreshCount = 0;
    await tester.pumpWidget(
      _harness(
        getSettings,
        externalReceiveWallets,
        onExternalReceiveSettingsChanged: () => refreshCount += 1,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Could not update Get Paid settings. Please try again.'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.text('Could not update Get Paid settings. Please try again.'),
      findsOneWidget,
    );
    expect(refreshCount, 0);
  });
}

Future<void> _scrollToRecoverWallets(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Recover Get Paid wallets'),
    220,
    scrollable: find.byType(Scrollable).first,
  );
}

Widget _harness(
  GetSettingsUsecase getSettings,
  ExternalReceiveWalletsFacade externalReceiveWallets, {
  VoidCallback? onExternalReceiveSettingsChanged,
  VoidCallback? onExternalReceiveWalletsCreated,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider(
      create: (_) => GetPaidSettingsCubit(
        getSettings: getSettings,
        externalReceiveWallets: externalReceiveWallets,
      )..load(),
      child: GetPaidSettingsScreen(
        onExternalReceiveSettingsChanged: onExternalReceiveSettingsChanged,
        onExternalReceiveWalletsCreated: onExternalReceiveWalletsCreated,
      ),
    ),
  );
}

SettingsEntity _settings() {
  return const SettingsEntity(
    environment: Environment.mainnet,
    bitcoinUnit: BitcoinUnit.sats,
    currencyCode: 'CAD',
  );
}

List<ExternalReceiveWalletRestoreOutcome> _result() {
  return [
    ExternalReceiveWalletRestoreOutcome(
      accountKey: ExternalReceiveWalletPurpose.lightningAddress
          .liquidAccountKey(isTestnet: false),
      status: ExternalReceiveWalletRestoreOutcomeStatus.existing,
    ),
    ExternalReceiveWalletRestoreOutcome(
      accountKey: ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: false,
      ),
      status: ExternalReceiveWalletRestoreOutcomeStatus.created,
    ),
    ExternalReceiveWalletRestoreOutcome(
      accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      ),
      status: ExternalReceiveWalletRestoreOutcomeStatus.failed,
      failureReason: ExternalReceiveWalletRestoreFailureReason.noDefaultWallet,
    ),
  ];
}
