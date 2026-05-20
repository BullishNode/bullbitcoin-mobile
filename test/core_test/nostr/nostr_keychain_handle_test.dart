import 'dart:typed_data';

import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:bip85_entropy/bip85_entropy.dart' as bip85;
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _zeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _identity = 1;
const _account = 1;
const _expectedWalletManifestPublicKeyHex =
    'feae6420b59badf72d7e85436ced2b0c3b9bcf4e46f05d901bf448f698f0ab52';
const _expectedBullnymAuthPublicKeyHex =
    '23a772c17ca7b9eba8c9442c4378c063d791967e35fbaed98a51d65243c03cd4';
const _expectedNip05PublicKeyHex =
    'bb2823fcf6f9187227c5ed4f89730228e32412ca89e9b96a2c190bddb9e525ea';

void main() {
  test('BIP85 derivation matches the bitcoin_base public key', () {
    final xprv = _zeroMnemonicXprv();
    final handle = NostrKeychainHandle.deriveFromBip85(
      xprvBase58: xprv,
      identity: _identity,
      account: _account,
    );

    expect(handle.publicKeyHex, _legacyPublicKeyHex(xprv));
  });

  test('reserved Nostr roles use fixed BIP85 app 9000 vectors', () {
    final xprv = _zeroMnemonicXprv();

    expect(
      deriveWalletManifestHandleFromXprv(xprv).publicKeyHex,
      _expectedWalletManifestPublicKeyHex,
    );
    expect(
      deriveBullnymServerAuthHandleFromXprv(xprv).publicKeyHex,
      _expectedBullnymAuthPublicKeyHex,
    );
    expect(
      deriveNip05VerificationHandleFromXprv(xprv).publicKeyHex,
      _expectedNip05PublicKeyHex,
    );
  });

  test('reserved Nostr role npubs are distinct', () {
    final xprv = _zeroMnemonicXprv();
    final npubs = {
      for (final role in NostrIdentityRole.values)
        deriveNostrHandleForRoleFromXprv(
          xprvBase58: xprv,
          role: role,
        ).publicKeyHex,
    };

    expect(npubs.length, NostrIdentityRole.values.length);
  });

  test(
    'NostrIdentity remains a compatibility wrapper over the core handle',
    () {
      final xprv = _zeroMnemonicXprv();
      final handle = NostrKeychainHandle.deriveFromBip85(
        xprvBase58: xprv,
        identity: _identity,
        account: _account,
      );
      final identity = NostrIdentity.derive(
        xprvBase58: xprv,
        identity: _identity,
        account: _account,
      );

      expect(identity.npubHex, handle.publicKeyHex);
      expect(identity.toString(), isNot(contains(_secretKeyHex(xprv))));
    },
  );

  test('signs SHA256(message) with a signature bitcoin_base can verify', () {
    final xprv = _zeroMnemonicXprv();
    final handle = NostrKeychainHandle.deriveFromBip85(
      xprvBase58: xprv,
      identity: _identity,
      account: _account,
    );
    final message = Uint8List.fromList([1, 2, 3, 4]);
    final signatureHex = handle.signMessage(message);
    final digest = sha256.convert(message).bytes;
    final pub = ECPublic.fromHex('02${handle.publicKeyHex}');

    expect(
      pub.verifyBip340Signature(
        digest: digest,
        signature: hex.decode(signatureHex),
        tweak: false,
      ),
      isTrue,
    );
  });

  test('supports deterministic hash signing when aux is supplied', () {
    final xprv = _zeroMnemonicXprv();
    final handle = NostrKeychainHandle.deriveFromBip85(
      xprvBase58: xprv,
      identity: _identity,
      account: _account,
    );
    final messageHashHex = hex.encode(sha256.convert([1, 2, 3, 4]).bytes);
    final auxHex = '00' * 32;

    expect(
      handle.signHashHex(messageHashHex, auxHex: auxHex),
      handle.signHashHex(messageHashHex, auxHex: auxHex),
    );
  });
}

String _zeroMnemonicXprv() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    _zeroMnemonic,
    bip39.Language.english,
  );
  return Bip32Derivation.getXprvFromSeed(
    Uint8List.fromList(mnemonic.seed),
    Network.bitcoinMainnet,
  );
}

String _legacyPublicKeyHex(String xprvBase58) {
  final secretKeyHex = _secretKeyHex(xprvBase58);
  return ECPrivate.fromHex(secretKeyHex).getPublic().toXOnlyHex();
}

String _secretKeyHex(String xprvBase58) {
  final path = bip85.Bip85HardenedPath(
    "$nostrBip85Application'/$_identity'/$_account'",
  );
  final entropyHex = bip85.Bip85Entropy.deriveFromHardenedPath(
    xprvBase58: xprvBase58,
    path: path,
  );
  return entropyHex.substring(0, 64);
}
