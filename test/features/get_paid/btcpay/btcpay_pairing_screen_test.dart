import 'dart:async';

import 'package:bb_mobile/features/get_paid/btcpay/application/btcpay_pairing_exception.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/get_paid/btcpay/ui/btcpay_pairing_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCompleteBtcpaySamRockPairingUsecase extends Mock
    implements CompleteBtcpaySamRockPairingUsecase {}

class _MockGetBtcpayConnectionUsecase extends Mock
    implements GetBtcpayConnectionUsecase {}

void main() {
  testWidgets('blocks duplicate submit and back while pairing is in flight', (
    tester,
  ) async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    final completer = Completer<BtcpayConnection>();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_harness(completePairing));
    await tester.enterText(
      find.byType(TextFormField),
      'https://btcpay.example/plugins/samrock/protocol?setup=btc-chain&otp=123',
    );

    await tester.tap(find.text('Pair BTCPay'));
    await tester.pumpAndSettle();
    expect(find.text('Create BTCPay wallets?'), findsOneWidget);
    expect(
      find.textContaining(
        'You are about to create or use dedicated Bitcoin wallet and share watch-only wallet descriptors with a BTCPay Server at https://btcpay.example.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'That server can monitor payments received by these dedicated wallets. No private keys are shared.',
      ),
      findsOneWidget,
    );
    expect(find.text('Requested rails: Bitcoin'), findsOneWidget);
    await tester.tap(find.text('Create wallets and share details'));
    await tester.pump();
    await tester.tap(find.text('Pairing...'), warnIfMissed: false);
    await tester.pump();

    verify(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).called(1);
    expect(find.text('Pairing...'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('BTCPay'), findsOneWidget);
    expect(
      find.text('Wait for BTCPay pairing to finish before leaving.'),
      findsOneWidget,
    );
  });

  testWidgets('trims pairing URL before submitting', (tester) async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    final completer = Completer<BtcpayConnection>();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_harness(completePairing));
    await tester.enterText(
      find.byType(TextFormField),
      '  https://btcpay.example/plugins/samrock/protocol?setup=btc-chain&otp=123  ',
    );

    await tester.tap(find.text('Pair BTCPay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create wallets and share details'));
    await tester.pump();

    verify(
      () => completePairing.execute(
        pairingUrl:
            'https://btcpay.example/plugins/samrock/protocol?setup=btc-chain&otp=123',
      ),
    ).called(1);
  });

  testWidgets('shows BTCPay rejection details when available', (tester) async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenThrow(BtcpayPairingException.rejected('OTP expired'));

    await tester.pumpWidget(_harness(completePairing));
    await tester.enterText(
      find.byType(TextFormField),
      'https://btcpay.example/plugins/samrock/protocol?otp=123',
    );

    await tester.tap(find.text('Pair BTCPay'));
    await tester.pump();

    expect(find.text('OTP expired'), findsOneWidget);
  });

  testWidgets('submits from the keyboard done action', (tester) async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    final completer = Completer<BtcpayConnection>();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_harness(completePairing));
    await tester.enterText(
      find.byType(TextFormField),
      'https://btcpay.example/plugins/samrock/protocol?setup=btc-chain&otp=123',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create wallets and share details'));
    await tester.pump();

    verify(
      () => completePairing.execute(
        pairingUrl:
            'https://btcpay.example/plugins/samrock/protocol?setup=btc-chain&otp=123',
      ),
    ).called(1);
  });

  testWidgets('uses URL entry keyboard behavior', (tester) async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenAnswer((_) async => _connection());

    await tester.pumpWidget(_harness(completePairing));

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.keyboardType, TextInputType.url);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(find.text('Scan pairing QR'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
  });

  testWidgets('shows paired BTCPay details before the pairing form', (
    tester,
  ) async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    final getConnection = _MockGetBtcpayConnectionUsecase();
    when(() => getConnection.execute()).thenAnswer((_) async => _connection());

    await tester.pumpWidget(
      _harness(completePairing, getConnection: getConnection, load: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connected BTCPay Server'), findsOneWidget);
    expect(find.text('https://btcpay.example'), findsOneWidget);
    expect(find.text('Pair new BTCPay'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.text('Pair new BTCPay'));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Pair BTCPay'), findsOneWidget);
  });
}

Widget _harness(
  CompleteBtcpaySamRockPairingUsecase completePairing, {
  GetBtcpayConnectionUsecase? getConnection,
  bool load = false,
}) {
  final connectionUsecase = getConnection ?? _MockGetBtcpayConnectionUsecase();
  if (getConnection == null) {
    when(
      () => (connectionUsecase as _MockGetBtcpayConnectionUsecase).execute(),
    ).thenAnswer((_) async => null);
  }
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider(
      create: (_) {
        final cubit = BtcpayPairingCubit(
          completePairing: completePairing,
          getConnection: connectionUsecase,
        );
        if (load) cubit.load();
        return cubit;
      },
      child: const BtcpayPairingScreen(),
    ),
  );
}

BtcpayConnection _connection() {
  return BtcpayConnection(
    serverUrl: 'https://btcpay.example',
    capabilities: const [
      SamRockSetupCapability.bitcoinChain,
      SamRockSetupCapability.liquidChain,
      SamRockSetupCapability.bitcoinLightning,
    ],
    walletNetworks: const [
      BtcpayPairingWalletNetwork.bitcoin,
      BtcpayPairingWalletNetwork.liquid,
    ],
    pairedAt: DateTime.utc(2026, 5, 20, 12),
  );
}
