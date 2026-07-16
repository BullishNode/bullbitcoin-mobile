import 'dart:typed_data';

import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/get_paid_settings/data/get_paid_settings_default_wallet_xprv_adapter.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/data/default_wallet_xprv_adapter.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/local_wallet_metadata_backup_root_adapter.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockSettingsEntity extends Mock implements SettingsEntity {}

class _MockWallet extends Mock implements Wallet {}

void main() {
  final seedBytes = Uint8List.fromList(
    List<int>.generate(64, (index) => index + 1),
  );
  final fingerprint = bip32.Bip32Keys.fromBase58(
    Bip32Derivation.getXprvFromSeed(seedBytes, Network.bitcoinMainnet),
  ).fingerprintHex;

  late _MockGetSettingsUsecase getSettings;
  late _MockWalletRepository walletRepository;
  late _MockSeedRepository seedRepository;

  setUp(() {
    getSettings = _MockGetSettingsUsecase();
    walletRepository = _MockWalletRepository();
    seedRepository = _MockSeedRepository();

    final settings = _MockSettingsEntity();
    when(() => settings.environment).thenReturn(Environment.mainnet);
    when(() => getSettings.execute()).thenAnswer((_) async => settings);

    final wallet = _MockWallet();
    when(() => wallet.masterFingerprint).thenReturn(fingerprint);
    when(() => wallet.network).thenReturn(Network.bitcoinMainnet);
    when(
      () => walletRepository.getWallets(
        environment: Environment.mainnet,
        onlyDefaults: true,
        onlyBitcoin: true,
      ),
    ).thenAnswer((_) async => [wallet]);

    when(() => seedRepository.get(fingerprint)).thenAnswer(
      (_) async => Seed.bytes(bytes: seedBytes, masterFingerprint: fingerprint),
    );
  });

  test(
    'derives the identical xprv and parent fingerprint as the recovery adapter',
    () async {
      final publishAdapter = GetPaidSettingsDefaultWalletXprvAdapter(
        getSettings: getSettings,
        walletRepository: walletRepository,
        seedRepository: seedRepository,
      );
      final recoveryAdapter = RemoteKeychainRecoveryDefaultWalletXprvAdapter(
        getSettings: getSettings,
        walletRepository: walletRepository,
        seedRepository: seedRepository,
      );
      final metadataAdapter = LocalWalletMetadataBackupRootAdapter(
        getSettings: getSettings,
        walletRepository: walletRepository,
        seedRepository: seedRepository,
      );

      final publish = await publishAdapter.deriveDefaultWalletXprv();
      final recovery = await recoveryAdapter.deriveDefaultWalletXprv();
      final metadataResult = await metadataAdapter.deriveLocalRoot();
      final metadata = switch (metadataResult) {
        Ok(:final value) => value,
        Err(:final failure) => throw TestFailure(
          'metadata root failed: ${failure.runtimeType}',
        ),
      };

      expect(publish.xprvBase58, recovery.xprvBase58);
      expect(metadata.xprvBase58, recovery.xprvBase58);
      expect(publish.parentFingerprint, recovery.parentFingerprint);
      expect(metadata.parentFingerprint, recovery.parentFingerprint);
      expect(publish.parentFingerprint, fingerprint);
    },
  );
}
