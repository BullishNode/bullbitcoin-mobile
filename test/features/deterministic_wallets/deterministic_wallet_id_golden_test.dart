import 'dart:typed_data';

import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/wallet_metadata_service.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';

// Golden cross-version contract for the deterministic-wallet id.
//
// A materialized reserved wallet is addressed by wallet.id, which is
// WalletMetadataService.encodeOrigin(masterFingerprint, network, scriptType)
// over the fingerprint of the BIP85-derived child seed. Recovery matches
// wallets by that id, so an unpinned id derivation is a silent cross-version
// hazard: a bip39_mnemonic / bip32_keys bump that changed the fingerprint, or
// an origin-encoding change, would remap every id and make recovery report a
// conflict on every wallet, with all other tests still green.
//
// These literals pin the whole child-mnemonic -> fingerprint -> id chain
// against a fixed, valueless test mnemonic. They are APPEND-ONLY: never edit an
// existing vector (an intentional format change adds a new one and freezes the
// old); a decode/derivation drift breaking any vector must fail CI. Same rule
// as the index-100 BIP85 vector at
// test/features/bip85_registry/data/bip85_registry_facade_test.dart.
void main() {
  // All-ones entropy BIP39 mnemonic ("zoo" x11 + "wrong"), the repo's standard
  // valueless test vector. Holds no funds on any network.
  final mnemonic = bip39.Mnemonic.fromWords(
    words: List.generate(11, (_) => 'zoo') + ['wrong'],
  );

  String masterFingerprint(bip39.Mnemonic m) {
    final seedBytes = Uint8List.fromList(m.seed);
    return bip32.Bip32Keys.fromSeed(seedBytes).fingerprint.toHexString();
  }

  group('deterministic wallet id golden vectors', () {
    test('the fixed test mnemonic derives the pinned master fingerprint', () {
      expect(masterFingerprint(mnemonic), '3f635a63');
    });

    test('network + script type map to the pinned wallet id string', () {
      final fingerprint = masterFingerprint(mnemonic);

      String id(Network network, ScriptType scriptType) =>
          WalletMetadataService.encodeOrigin(
            fingerprint: fingerprint,
            network: network,
            scriptType: scriptType,
          );

      // Bitcoin mainnet (Get Paid wallets materialize here).
      expect(
        id(Network.bitcoinMainnet, ScriptType.bip84),
        'wpkh([3f635a63/84h/0h/0h])',
      );
      expect(
        id(Network.bitcoinMainnet, ScriptType.bip49),
        'sh(wpkh([3f635a63/49h/0h/0h]))',
      );
      expect(
        id(Network.bitcoinMainnet, ScriptType.bip44),
        'pkh([3f635a63/44h/0h/0h])',
      );

      // Bitcoin testnet.
      expect(
        id(Network.bitcoinTestnet, ScriptType.bip84),
        'wpkh([3f635a63/84h/1h/0h])',
      );

      // Liquid mainnet (el-prefixed descriptors).
      expect(
        id(Network.liquidMainnet, ScriptType.bip84),
        'elwpkh([3f635a63/84h/1776h/0h])',
      );
    });
  });
}
