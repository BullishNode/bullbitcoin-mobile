import 'dart:async';

import 'package:bb_mobile/features/get_paid/btcpay/application/btcpay_pairing_exception.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/get_paid/btcpay/ui/btcpay_pairing_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCompleteBtcpaySamRockPairingUsecase extends Mock
    implements CompleteBtcpaySamRockPairingUsecase {}

void main() {
  testWidgets('shows BTCPay status and parsed pairing details', (tester) async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(_harness(completePairing));

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(
      find.text(
        'Paste a SamRock pairing URL from BTCPay Server. Pairing creates dedicated BTCPay wallets and shares public wallet details with that server.',
      ),
      findsOneWidget,
    );
    expect(find.text('BTCPay Server'), findsNothing);

    await tester.enterText(
      find.byType(TextFormField),
      'https://btcpay.example:8443/plugins/samrock/protocol?setup=btc-chain%2Cliquid-chain%2Cbtc-ln&otp=123',
    );
    await tester.pump();

    expect(find.text('BTCPay Server'), findsOneWidget);
    expect(find.text('https://btcpay.example:8443'), findsOneWidget);
    expect(find.text('Wallets'), findsOneWidget);
    expect(find.text('Bitcoin wallet, Liquid wallet'), findsOneWidget);
  });

  testWidgets('blocks duplicate submit and back while pairing is in flight', (
    tester,
  ) async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    final completer = Completer<void>();
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
        'You are about to create or use dedicated Bitcoin wallet and share public wallet details with a BTCPay Server at https://btcpay.example.',
      ),
      findsOneWidget,
    );
    expect(find.text('Requested rails: Bitcoin'), findsOneWidget);
    await tester.tap(find.text('Proceed'));
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
    final completer = Completer<void>();
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
    await tester.tap(find.text('Proceed'));
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
    final completer = Completer<void>();
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
    await tester.tap(find.text('Proceed'));
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
    ).thenAnswer((_) async {});

    await tester.pumpWidget(_harness(completePairing));

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.keyboardType, TextInputType.url);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });
}

Widget _harness(CompleteBtcpaySamRockPairingUsecase completePairing) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider(
      create: (_) => BtcpayPairingCubit(completePairing: completePairing),
      child: const BtcpayPairingScreen(),
    ),
  );
}
