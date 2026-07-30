import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_wallet_behavior.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_wallet_behaviors_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWallets extends Mock implements GetWalletsUsecase {}

class _MockManifest extends Mock implements KeychainManifestFacade {}

class _MockWallet extends Mock implements Wallet {}

const _parentFingerprint = 'abcd1234';
const _pageReservation = 'payment_page_wallet_seed';

Wallet _wallet({
  required String id,
  bool isDefault = false,
  String fingerprint = '',
  bool liquid = true,
  bool hideOnHome = false,
  bool autoSweep = false,
  String label = '',
}) {
  final wallet = _MockWallet();
  when(() => wallet.id).thenReturn(id);
  when(() => wallet.isDefault).thenReturn(isDefault);
  when(() => wallet.masterFingerprint).thenReturn(fingerprint);
  when(
    () => wallet.network,
  ).thenReturn(liquid ? Network.liquidMainnet : Network.bitcoinMainnet);
  when(() => wallet.hideOnHome).thenReturn(hideOnHome);
  when(() => wallet.autoSweepEnabled).thenReturn(autoSweep);
  when(() => wallet.label).thenReturn(label);
  return wallet;
}

Wallet _defaultWallet() => _wallet(
  id: 'default-btc',
  isDefault: true,
  fingerprint: _parentFingerprint,
  liquid: false,
);

void main() {
  late _MockGetWallets getWallets;
  late _MockManifest manifest;
  late GetGetPaidWalletBehaviorsUsecase usecase;

  setUp(() {
    getWallets = _MockGetWallets();
    manifest = _MockManifest();
    usecase = GetGetPaidWalletBehaviorsUsecase(
      getWallets: getWallets,
      manifest: manifest,
    );
    when(
      () => manifest.reservationWalletIds(
        parentFingerprint: any(named: 'parentFingerprint'),
        reservationId: any(named: 'reservationId'),
      ),
    ).thenAnswer((_) async => const []);
  });

  void stubWallets(List<Wallet> wallets) {
    when(
      () => getWallets.execute(
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyBitcoin: any(named: 'onlyBitcoin'),
        onlyLiquid: any(named: 'onlyLiquid'),
        sync: any(named: 'sync'),
      ),
    ).thenAnswer((_) async => wallets);
  }

  void stubReservation(String reservationId, List<String> walletIds) {
    when(
      () => manifest.reservationWalletIds(
        parentFingerprint: _parentFingerprint,
        reservationId: reservationId,
      ),
    ).thenAnswer((_) async => walletIds);
  }

  test('resolves the product wallet via the manifest reservation even when its '
      'label was renamed', () async {
    final page = _wallet(id: 'w-102', label: 'My Custom Donations');
    stubWallets([_defaultWallet(), page]);
    stubReservation(_pageReservation, const ['w-102']);

    final result = await usecase.execute(
      only: GetPaidWalletProduct.paymentPage,
    );

    expect(result, hasLength(1));
    expect(result.single.walletId, 'w-102');
  });

  test('a colliding label on another wallet never receives the product '
      "behavior — the manifest's wallet wins", () async {
    final realPage = _wallet(id: 'w-102', label: 'My Custom Donations');
    // An impostor carrying the OLD label the pre-manifest code matched on.
    final impostor = _wallet(id: 'w-evil', label: 'Payment Page Liquid');
    stubWallets([_defaultWallet(), impostor, realPage]);
    stubReservation(_pageReservation, const ['w-102']);

    final result = await usecase.execute(
      only: GetPaidWalletProduct.paymentPage,
    );

    expect(result.single.walletId, 'w-102');
    expect(result.single.walletId, isNot('w-evil'));
  });

  test('a missing manifest entry yields no behavior (controls absent, no '
      'guess)', () async {
    final page = _wallet(id: 'w-102', label: 'Payment Page Liquid');
    stubWallets([_defaultWallet(), page]);
    stubReservation(_pageReservation, const []); // nothing recorded

    final result = await usecase.execute(
      only: GetPaidWalletProduct.paymentPage,
    );

    expect(result, isEmpty);
  });

  test(
    'a manifest id whose wallet no longer exists yields no behavior',
    () async {
      stubWallets([_defaultWallet()]); // the recorded wallet is gone locally
      stubReservation(_pageReservation, const ['w-102']);

      final result = await usecase.execute(
        only: GetPaidWalletProduct.paymentPage,
      );

      expect(result, isEmpty);
    },
  );

  test(
    'no default wallet (no parent fingerprint) yields no behaviors',
    () async {
      stubWallets([_wallet(id: 'w-102', label: 'x')]); // none isDefault
      stubReservation(_pageReservation, const ['w-102']);

      final result = await usecase.execute();

      expect(result, isEmpty);
    },
  );

  test(
    'the reserved wallet id passed to the write is the manifest one',
    () async {
      final page = _wallet(
        id: 'w-102',
        hideOnHome: true,
        autoSweep: true,
        label: 'renamed',
      );
      stubWallets([_defaultWallet(), page]);
      stubReservation(_pageReservation, const ['w-102']);

      final result = await usecase.execute(
        only: GetPaidWalletProduct.paymentPage,
      );

      expect(result.single.walletId, 'w-102');
      expect(result.single.hideOnHome, isTrue);
      expect(result.single.autoSweepEnabled, isTrue);
    },
  );
}
