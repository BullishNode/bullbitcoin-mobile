import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip340/bip340.dart' as bip340;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:bip85_entropy/bip85_entropy.dart' as bip85;
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _facade = NostrIdentityFacade(
  DeriveNostrIdentityHandleUsecase(Bip85RegistryFacade()),
);

const _zeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _identity = 100;
const _account = 1;
const _expectedWalletBackupPublicKeyHex =
    '4fb85384f3a52baadbadc3f9bcb7fd59691e323293160b58959dadd6195c7981';
const _expectedBullnymAuthPublicKeyHex =
    '1d11451fdea6a9e291265e6ebf0eba04145f4bd2a15e7cea11978430f1011cf3';
const _pinnedMasterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';

void main() {
  test('BIP85 path derivation matches the bitcoin_base public key', () {
    final xprv = _zeroMnemonicXprv();
    final handle = NostrKeychainHandle.deriveFromBip85Path(
      xprvBase58: xprv,
      hardenedPath: _walletBackupPath,
    );

    expect(handle.publicKeyHex, _legacyPublicKeyHex(xprv));
  });

  test('Bull reserved Nostr roles produce stable golden public keys', () {
    final xprv = _zeroMnemonicXprv();
    const facade = _facade;

    expect(
      facade.deriveWalletBackupPublicKeyFromXprv(xprv),
      _expectedWalletBackupPublicKeyHex,
    );
    expect(
      facade.deriveBullnymServerAuthPublicKeyFromXprv(xprv),
      _expectedBullnymAuthPublicKeyHex,
    );
    expect(
      facade.deriveBullnymNip05VerificationPublicKeyFromXprv(xprv),
      NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: xprv,
        hardenedPath: "128002'/102'/1'",
      ).publicKeyHex,
    );
  });

  test('wallet backup facade uses the registry exact path', () {
    final xprv = _zeroMnemonicXprv();
    const registry = Bip85RegistryFacade();
    const facade = _facade;
    final reservation = registry.reservationById('nostr_wallet_backup_key');
    expect(reservation, isNotNull);
    final expected = NostrKeychainHandle.deriveFromBip85Path(
      xprvBase58: xprv,
      hardenedPath: reservation!.scope.exactPath,
    );

    expect(
      facade.deriveWalletBackupPublicKeyFromXprv(xprv),
      expected.publicKeyHex,
    );
  });

  test('exposed Nostr role public keys are distinct', () {
    final xprv = _zeroMnemonicXprv();
    const facade = _facade;
    final publicKeys = {
      facade.deriveWalletBackupPublicKeyFromXprv(xprv),
      facade.deriveBullnymServerAuthPublicKeyFromXprv(xprv),
      facade.deriveBullnymNip05VerificationPublicKeyFromXprv(xprv),
    };

    expect(publicKeys.length, 3);
  });

  test('handle debug output does not expose secret key material', () {
    final xprv = _zeroMnemonicXprv();
    final handle = NostrKeychainHandle.deriveFromBip85Path(
      xprvBase58: xprv,
      hardenedPath: _walletBackupPath,
    );

    expect(handle.toString(), isNot(contains(_secretKeyHex(xprv))));
  });

  test(
    'explicit secret materialization returns an Nsec without storing it',
    () {
      final xprv = _zeroMnemonicXprv();
      final nsec = NostrKeychainSecretMaterializer.deriveNsec(
        xprvBase58: xprv,
        hardenedPath: _walletBackupPath,
      );

      expect(nsec, startsWith('nsec1'));
      expect(nsec.length, greaterThan(60));
      expect(nsec, isNot(contains(_secretKeyHex(xprv))));
      expect(
        NostrKeychainSecretMaterializer.deriveNsec(
          xprvBase58: xprv,
          hardenedPath: _walletBackupPath,
        ),
        nsec,
      );
    },
  );

  test('signs an explicit hash with a signature bitcoin_base can verify', () {
    final xprv = _zeroMnemonicXprv();
    const facade = _facade;
    final digest = sha256.convert([1, 2, 3, 4]).bytes;
    final signatureHex = facade.signWalletBackupHashFromXprv(
      xprvBase58: xprv,
      messageHashHex: hex.encode(digest),
    );
    final pub = ECPublic.fromHex(
      '02${facade.deriveWalletBackupPublicKeyFromXprv(xprv)}',
    );

    expect(
      pub.verifyBip340Signature(
        digest: digest,
        signature: hex.decode(signatureHex),
        tweak: false,
      ),
      isTrue,
    );

    // Independent cross-check with the bip340 package (not bitcoin_base), so a
    // bitcoin_base sign/verify self-consistency bug alone cannot make this pass
    // (AD-6). After the pr20 backend swap, bitcoin_base above remains the
    // independent verifier for dart-nostr/bip340 signing - both directions
    // covered across the stack.
    expect(
      bip340.verify(
        facade.deriveWalletBackupPublicKeyFromXprv(xprv),
        hex.encode(digest),
        signatureHex,
      ),
      isTrue,
    );
  });

  test('rejects signing input that is not a 32-byte hash', () {
    final xprv = _zeroMnemonicXprv();
    const facade = _facade;

    expect(
      () => facade.signWalletBackupHashFromXprv(
        xprvBase58: xprv,
        messageHashHex: 'abcd',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects Nostr paths outside the final BIP85 namespace', () {
    final xprv = _zeroMnemonicXprv();

    expect(
      () => NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: xprv,
        hardenedPath: "9000'/100'/1'",
      ),
      throwsArgumentError,
    );
    expect(
      () => NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: xprv,
        hardenedPath: "128002'/0'/1'",
      ),
      throwsArgumentError,
    );
    expect(
      () => NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: xprv,
        hardenedPath: "128002'/100'/0'",
      ),
      throwsArgumentError,
    );
    expect(
      () => NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: xprv,
        hardenedPath: "2147483648'/100'/1'",
      ),
      throwsArgumentError,
    );
    expect(
      () => NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: xprv,
        hardenedPath: "128002'/2147483648'/1'",
      ),
      throwsArgumentError,
    );
    expect(
      () => NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: xprv,
        hardenedPath: "128002'/100'/2147483648'",
      ),
      throwsArgumentError,
    );
  });

  test('matches independent pinned BIP85 Nostr vectors', () {
    const vectors = [
      (
        100,
        'd3f7cbe5245ef79b9105b12b3492a03bc7709c82bb732e8daf912829c4cdc77a',
        '2dd5669c9e9dff487b377a12e2e9dda0a18861dcd85cd100c27aae5cd6a6b304',
        'nsec160muhefytmmehyg9ky4nfy4q80rhp8yzhdejard0jy5zn3xdcaaq9w56w8',
      ),
      (
        101,
        '9054c9cf5aef651b8a0334f385191cc64ad646468f050a670295183a0e1c78cf',
        '8e97ed35934195d54d86d3756c2a5e1fcd28a08a13e90313df4e2734f648470e',
        'nsec1jp2vnn66aaj3hzsrxnec2xguce9dv3jx3uzs5eczj5vr5rsu0r8swaa3mp',
      ),
    ];

    for (final vector in vectors) {
      final path = "128002'/${vector.$1}'/1'";
      final entropyHex = bip85.Bip85Entropy.deriveFromHardenedPath(
        xprvBase58: _pinnedMasterXprv,
        path: bip85.Bip85HardenedPath(path),
      );
      expect(entropyHex.substring(0, 64), vector.$2);
      expect(
        NostrKeychainHandle.deriveFromBip85Path(
          xprvBase58: _pinnedMasterXprv,
          hardenedPath: path,
        ).publicKeyHex,
        vector.$3,
      );
      expect(_encodeNsec(vector.$2), vector.$4);
    }
  });
}

String _encodeNsec(String secretHex) {
  return bech32.encode(
    Bech32('nsec', _convertBits(hex.decode(secretHex), 8, 5, true)),
  );
}

List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  var accumulator = 0;
  var bits = 0;
  final result = <int>[];
  final maxValue = (1 << to) - 1;
  final maxAccumulator = (1 << (from + to - 1)) - 1;
  for (final value in data) {
    accumulator = ((accumulator << from) | value) & maxAccumulator;
    bits += from;
    while (bits >= to) {
      bits -= to;
      result.add((accumulator >> bits) & maxValue);
    }
  }
  if (pad && bits > 0) result.add((accumulator << (to - bits)) & maxValue);
  return result;
}

String _zeroMnemonicXprv() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    _zeroMnemonic,
    bip39.Language.english,
  );
  return bip32.Bip32Keys.fromSeed(Uint8List.fromList(mnemonic.seed)).toBase58();
}

String _legacyPublicKeyHex(String xprvBase58) {
  final secretKeyHex = _secretKeyHex(xprvBase58);
  return ECPrivate.fromHex(secretKeyHex).getPublic().toXOnlyHex();
}

String _secretKeyHex(String xprvBase58) {
  final path = bip85.Bip85HardenedPath(_walletBackupPath);
  final entropyHex = bip85.Bip85Entropy.deriveFromHardenedPath(
    xprvBase58: xprvBase58,
    path: path,
  );
  return entropyHex.substring(0, 64);
}

String get _walletBackupPath =>
    "$nostrBip85Application'/$_identity'/$_account'";
