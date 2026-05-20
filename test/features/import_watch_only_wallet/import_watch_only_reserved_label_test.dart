import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/import_watch_only_descriptor_usecase.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/import_watch_only_xpub_usecase.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/watch_only_wallet_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockWatchOnlyDescriptorEntity extends Mock
    implements WatchOnlyDescriptorEntity {}

class _MockWatchOnlyXpubEntity extends Mock implements WatchOnlyXpubEntity {}

void main() {
  test('watch-only descriptor import rejects reserved wallet labels', () async {
    final repository = _MockWalletRepository();
    final entity = _MockWatchOnlyDescriptorEntity();
    when(
      () => entity.label,
    ).thenReturn(ReservedExternalReceiveWalletLabel.btcpayBitcoin);

    final usecase = ImportWatchOnlyDescriptorUsecase(
      walletRepository: repository,
      walletLabelReservationPolicy: const WalletLabelReservationPolicy(
        reservedLabels: ReservedExternalReceiveWalletLabel.userReserved,
      ),
    );

    await expectLater(
      usecase(watchOnlyDescriptor: entity),
      throwsA(isA<ReservedWalletLabelException>()),
    );
    verifyZeroInteractions(repository);
  });

  test('watch-only xpub import rejects reserved wallet labels', () async {
    final repository = _MockWalletRepository();
    final entity = _MockWatchOnlyXpubEntity();
    when(
      () => entity.label,
    ).thenReturn(ReservedExternalReceiveWalletLabel.paymentPageLiquid);

    final usecase = ImportWatchOnlyXpubUsecase(
      walletRepository: repository,
      walletLabelReservationPolicy: const WalletLabelReservationPolicy(
        reservedLabels: ReservedExternalReceiveWalletLabel.userReserved,
      ),
    );

    await expectLater(
      usecase(watchOnlyXpub: entity),
      throwsA(isA<ReservedWalletLabelException>()),
    );
    verifyZeroInteractions(repository);
  });

  test('watch-only xpub import allows non-reserved wallet labels', () async {
    final repository = _MockWalletRepository();
    final entity = _MockWatchOnlyXpubEntity();
    final wallet = Wallet(
      origin: 'watch-only',
      label: 'BTCPay Savings',
      network: Network.bitcoinMainnet,
      xpubFingerprint: 'fingerprint',
      scriptType: ScriptType.bip84,
      xpub: 'xpub',
      externalPublicDescriptor: 'wpkh(xpub/0/*)',
      internalPublicDescriptor: 'wpkh(xpub/1/*)',
      signer: SignerEntity.none,
      signerDevice: null,
      balanceSat: BigInt.zero,
    );

    when(() => entity.label).thenReturn('BTCPay Savings');
    when(() => entity.pubkey).thenReturn('xpub');
    when(() => entity.network).thenReturn(Network.bitcoinMainnet);
    when(() => entity.scriptType).thenReturn(ScriptType.bip84);
    when(
      () => repository.importWatchOnlyXpub(
        xpub: 'xpub',
        network: Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
        label: 'BTCPay Savings',
      ),
    ).thenAnswer((_) async => wallet);

    final usecase = ImportWatchOnlyXpubUsecase(
      walletRepository: repository,
      walletLabelReservationPolicy: const WalletLabelReservationPolicy(
        reservedLabels: ReservedExternalReceiveWalletLabel.userReserved,
      ),
    );
    final result = await usecase(watchOnlyXpub: entity);

    expect(result, wallet);
    verify(
      () => repository.importWatchOnlyXpub(
        xpub: 'xpub',
        network: Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
        label: 'BTCPay Savings',
      ),
    ).called(1);
  });
}
