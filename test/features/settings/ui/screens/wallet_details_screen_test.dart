import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/settings/ui/screens/bitcoin/wallet_details_screen.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletBloc extends Mock implements WalletBloc {}

void main() {
  testWidgets('hides delete action for external receive wallets', (
    tester,
  ) async {
    final wallet = _wallet(id: 'payment-page', label: 'Payment Page-LBTC');
    await tester.pumpWidget(
      _harness(
        wallet: wallet,
        externalReceiveWalletIds: ExternalReceiveWalletIds(
          purposeByWalletId: {
            wallet.id: ExternalReceiveWalletPurpose.paymentPage,
          },
        ),
      ),
    );

    expect(find.byIcon(CupertinoIcons.delete), findsNothing);
  });

  testWidgets('keeps delete action for ordinary non-default wallets', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        wallet: _wallet(id: 'manual-wallet', label: 'Savings'),
      ),
    );

    expect(find.byIcon(CupertinoIcons.delete), findsOneWidget);
  });
}

Widget _harness({
  required Wallet wallet,
  ExternalReceiveWalletIds externalReceiveWalletIds =
      ExternalReceiveWalletIds.empty,
}) {
  final walletBloc = _MockWalletBloc();
  when(() => walletBloc.state).thenReturn(
    WalletState(
      status: WalletStatus.success,
      wallets: [wallet],
      externalReceiveWalletIds: externalReceiveWalletIds,
    ),
  );
  when(() => walletBloc.stream).thenAnswer((_) => const Stream.empty());

  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider<WalletBloc>.value(
      value: walletBloc,
      child: WalletDetailsScreen(walletId: wallet.id),
    ),
  );
}

Wallet _wallet({
  required String id,
  required String label,
  bool isDefault = false,
}) {
  return Wallet(
    origin: id,
    label: label,
    network: Network.liquidMainnet,
    isDefault: isDefault,
    xpubFingerprint: '',
    scriptType: ScriptType.bip84,
    xpub: '',
    externalPublicDescriptor: '',
    internalPublicDescriptor: '',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}
