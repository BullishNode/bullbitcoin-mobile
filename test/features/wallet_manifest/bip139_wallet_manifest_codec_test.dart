import 'dart:convert';

import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_reserved_identities.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_wallet_type.dart';
import 'package:bb_mobile/features/wallet_manifest/application/services/bip139_wallet_manifest_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = Bip139WalletManifestCodec();

  group('Bip85DerivationPath', () {
    test('parses 12-word English BIP85 mnemonic paths', () {
      final path = Bip85DerivationPath.tryParse("m/83696968'/39'/0'/12'/077'");

      expect(path?.index, 77);
      expect(path?.value, "m/83696968'/39'/0'/12'/77'");
    });

    test('rejects unsupported BIP85 applications', () {
      expect(Bip85DerivationPath.tryParse("m/83696968'/2'/0'"), isNull);
    });

    test('rejects BIP85 indexes outside the hardened child range', () {
      expect(
        Bip85DerivationPath.tryParse("m/83696968'/39'/0'/12'/2147483648'"),
        isNull,
      );
      expect(
        () => Bip85DerivationPath.mnemonic12(index: 2147483648),
        throwsArgumentError,
      );
    });
  });

  group('reserved identity classification', () {
    test('classifies by index and network family', () {
      expect(
        classifyWalletManifestIdentity(
          bip85Index: 75,
          network: WalletManifestNetwork.liquid,
        ),
        WalletManifestWalletType.lightningAddress,
      );
      expect(
        classifyWalletManifestIdentity(
          bip85Index: 75,
          network: WalletManifestNetwork.bitcoin,
        ),
        WalletManifestWalletType.manual,
      );
      expect(
        classifyWalletManifestIdentity(
          bip85Index: 77,
          network: WalletManifestNetwork.bitcoin,
        ),
        WalletManifestWalletType.btcpay,
      );
      expect(
        classifyWalletManifestIdentity(
          bip85Index: 12,
          network: WalletManifestNetwork.liquid,
        ),
        WalletManifestWalletType.manual,
      );
    });
  });

  group('codec', () {
    test('round-trips BIP139-shaped account entries', () {
      final snapshot = WalletManifestSnapshot(
        createdAt: 1710000002,
        accounts: [
          WalletManifestAccount(
            rootFingerprint: 'abcd1234',
            bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 0),
            network: WalletManifestNetwork.bitcoin,
            name: 'Savings-BTC',
            descriptor: 'wpkh(xpub/0/*)',
            changeDescriptor: 'wpkh(xpub/1/*)',
            timestamp: 1710000001,
          ),
          WalletManifestAccount(
            rootFingerprint: 'abcd1234',
            bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 77),
            network: WalletManifestNetwork.liquid,
            name: 'ignored for classification',
            descriptor: 'ct(slip77(...),elwpkh(xpub/0/*))',
          ),
        ],
      );

      final decoded = codec.decode(codec.encode(snapshot));

      expect(decoded.createdAt, 1710000002);
      expect(decoded.accounts, hasLength(2));
      expect(decoded.accounts.first.name, 'Savings-BTC');
      expect(decoded.accounts.first.network, WalletManifestNetwork.bitcoin);
      expect(
        decoded.accounts.first.bip85DerivationPath.value,
        "m/83696968'/39'/0'/12'/0'",
      );
      expect(decoded.accounts.last.walletType, WalletManifestWalletType.btcpay);
    });

    test('requires BIP139 marker and supported version', () {
      expect(
        () => codec.fromJson({
          'version': 1,
          'created_at': 1,
          'accounts': const [],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 2,
          'created_at': 1,
          'accounts': const [],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': '1',
          'created_at': 1,
          'accounts': const [],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('wraps invalid JSON as a codec exception', () {
      expect(
        () => codec.decode('{not json'),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test(
      'stores network per account and Bull metadata privately in account',
      () {
        final snapshot = WalletManifestSnapshot(
          createdAt: 1,
          accounts: [
            WalletManifestAccount(
              rootFingerprint: 'abcd1234',
              bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 4),
              network: WalletManifestNetwork.liquidTestnet,
            ),
          ],
        );

        final json = jsonDecode(codec.encode(snapshot)) as Map<String, dynamic>;
        final account =
            (json['accounts'] as List).single as Map<String, dynamic>;
        final bullbitcoin =
            (account['proprietary'] as Map<String, dynamic>)['bullbitcoin']
                as Map<String, dynamic>;

        expect(json.containsKey('network'), isFalse);
        expect(account['network'], 'liquid_testnet');
        expect(bullbitcoin['wallet_type'], 'manual');
        expect(bullbitcoin['bip85_index'], 4);
      },
    );

    test('publishes and parses testnet_3', () {
      final snapshot = WalletManifestSnapshot(
        createdAt: 1,
        accounts: [
          WalletManifestAccount(
            rootFingerprint: 'abcd1234',
            bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 4),
            network: WalletManifestNetwork.testnet3,
          ),
        ],
      );

      final json = jsonDecode(codec.encode(snapshot)) as Map<String, dynamic>;
      final account = (json['accounts'] as List).single as Map<String, dynamic>;
      expect(account['network'], 'testnet_3');

      final decoded = codec.fromJson(json);
      expect(decoded.accounts.single.network, WalletManifestNetwork.testnet3);
    });

    test('rejects pre-release testnet3 spelling', () {
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': 1,
          'accounts': [
            {
              'network': 'testnet3',
              'keys': {
                'abcd1234': {
                  'origin': "m/83696968'/39'/0'/12'/4'",
                  'key': 'xprv',
                },
              },
            },
          ],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('rejects accounts without a restorable BIP85 key', () {
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': 1,
          'accounts': [
            {
              'network': 'liquid',
              'keys': {
                'abcd1234': {'key': 'abcd1234'},
              },
            },
          ],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('uses caller fallback created_at when manifest omits it', () {
      final decoded = codec.fromJson({
        'bip': 139,
        'version': 1,
        'accounts': [
          _accountJson(name: 'Recovered without created_at', timestamp: 10),
        ],
      }, fallbackCreatedAt: 100);

      expect(decoded.createdAt, 100);
      expect(decoded.accounts.single.name, 'Recovered without created_at');
    });

    test('rejects malformed restore-critical account fields', () {
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': 1,
          'accounts': [
            {
              'network': 1,
              'keys': {
                'abcd1234': {
                  'key': 'abcd1234',
                  'bip85_derivation_path': "m/83696968'/39'/0'/12'/0'",
                },
              },
            },
          ],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('ignores malformed optional account metadata fields', () {
      final decoded = codec.fromJson({
        'bip': 139,
        'version': 1,
        'created_at': 1,
        'accounts': [
          {
            'name': 1,
            'network': 'bitcoin',
            'descriptor': 1,
            'change_descriptor': 1,
            'keys': {
              'abcd1234': {
                'key': 'ABCD1234',
                'bip85_derivation_path': "m/83696968'/39'/0'/12'/1'",
              },
            },
          },
        ],
      });

      expect(decoded.accounts, hasLength(1));
      expect(decoded.accounts.single.name, isNull);
      expect(decoded.accounts.single.descriptor, isNull);
      expect(decoded.accounts.single.changeDescriptor, isNull);
      expect(decoded.accounts.single.rootFingerprint, 'abcd1234');
    });

    test('rejects accounts without a valid root fingerprint', () {
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': 1,
          'accounts': [
            {
              'network': 'bitcoin',
              'keys': {
                'not-a-fingerprint': {
                  'key': 'also-bad',
                  'bip85_derivation_path': "m/83696968'/39'/0'/12'/1'",
                },
              },
            },
          ],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('uses key map entry as fingerprint when key value is absent', () {
      final decoded = codec.fromJson({
        'bip': 139,
        'version': 1,
        'created_at': 1,
        'accounts': [
          {
            'network': 'bitcoin',
            'keys': {
              'ABCD1234': {
                'bip85_derivation_path': "m/83696968'/39'/0'/12'/2'",
              },
            },
          },
        ],
      });
      expect(decoded.accounts, hasLength(1));
      expect(decoded.accounts.single.rootFingerprint, 'abcd1234');
      expect(decoded.accounts.single.bip85Index, 2);
    });

    test('rejects non-integer manifest metadata integers', () {
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1.5,
          'created_at': 1,
          'accounts': const [],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': 1.5,
          'accounts': const [],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': '1',
          'accounts': const [],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('uses a later key when the first key has no BIP85 path', () {
      final decoded = codec.fromJson({
        'bip': 139,
        'version': 1,
        'created_at': 1,
        'accounts': [
          {
            'network': 'bitcoin',
            'keys': {
              'first': {'key': '11111111'},
              'abcd1234': {
                'key': 'ABCD1234',
                'bip85_derivation_path': "m/83696968'/39'/0'/12'/3'",
              },
            },
          },
        ],
      });

      expect(decoded.accounts, hasLength(1));
      expect(decoded.accounts.single.rootFingerprint, 'abcd1234');
      expect(decoded.accounts.single.bip85Index, 3);
    });

    test('rejects accounts with ambiguous restorable keys', () {
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': 1,
          'accounts': [
            {
              'network': 'bitcoin',
              'keys': {
                'abcd1234': {
                  'key': 'abcd1234',
                  'bip85_derivation_path': "m/83696968'/39'/0'/12'/3'",
                },
                'abcd1235': {
                  'key': 'abcd1235',
                  'bip85_derivation_path': "m/83696968'/39'/0'/12'/4'",
                },
              },
            },
          ],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('collapses duplicate identities and latest metadata wins', () {
      final decoded = codec.fromJson({
        'bip': 139,
        'version': 1,
        'created_at': 100,
        'accounts': [
          _accountJson(name: 'Old', timestamp: 10),
          _accountJson(name: 'New', timestamp: 11),
        ],
      });

      expect(decoded.accounts, hasLength(1));
      expect(decoded.accounts.single.name, 'New');
    });

    test('rejects invalid account timestamps', () {
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': 100,
          'accounts': [_accountJson(name: 'Future', timestamp: 999999)],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('rejects string account timestamps', () {
      expect(
        () => codec.fromJson({
          'bip': 139,
          'version': 1,
          'created_at': 100,
          'accounts': [
            _accountJson(name: 'String timestamp', timestampValue: '999999'),
          ],
        }),
        throwsA(isA<WalletManifestCodecException>()),
      );
    });

    test('snapshot accounts are immutable', () {
      final accounts = [
        WalletManifestAccount(
          rootFingerprint: 'abcd1234',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 1),
          network: WalletManifestNetwork.bitcoin,
        ),
      ];
      final snapshot = WalletManifestSnapshot(
        createdAt: 100,
        accounts: accounts,
      );

      accounts.clear();

      expect(snapshot.accounts, hasLength(1));
      expect(() => snapshot.accounts.clear(), throwsUnsupportedError);
    });

    test('collapses duplicate identities with mixed-case fingerprints', () {
      final decoded = codec.fromJson({
        'bip': 139,
        'version': 1,
        'created_at': 100,
        'accounts': [
          _accountJson(name: 'Old', timestamp: 10, key: 'ABCD1234'),
          _accountJson(name: 'New', timestamp: 11, key: 'abcd1234'),
        ],
      });

      expect(decoded.accounts, hasLength(1));
      expect(decoded.accounts.single.rootFingerprint, 'abcd1234');
      expect(decoded.accounts.single.name, 'New');
    });

    test('normalizes nonreserved declared product types to manual', () {
      final decoded = codec.fromJson({
        'bip': 139,
        'version': 1,
        'created_at': 100,
        'accounts': [
          _accountJson(
            name: 'Wrong product metadata',
            timestamp: 10,
            walletType: 'btcpay',
            index: 12,
          ),
        ],
      });

      expect(
        decoded.accounts.single.walletType,
        WalletManifestWalletType.manual,
      );
    });
  });
}

Map<String, dynamic> _accountJson({
  required String name,
  int timestamp = 10,
  Object? timestampValue,
  String walletType = 'manual',
  int index = 0,
  String key = 'abcd1234',
}) {
  return {
    'name': name,
    'network': 'bitcoin',
    'timestamp': timestampValue ?? timestamp,
    'keys': {
      'abcd1234': {
        'key': key,
        'bip85_derivation_path': "m/83696968'/39'/0'/12'/$index'",
      },
    },
    'proprietary': {
      'bullbitcoin': {'wallet_type': walletType, 'bip85_index': index},
    },
  };
}
