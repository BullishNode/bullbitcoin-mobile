import 'package:bb_mobile/_core/domain/entities/wallet_metadata.dart';
import 'package:bdk_flutter/bdk_flutter.dart' as bdk;
import 'package:lwk/lwk.dart' as lwk;

abstract class DescriptorDataSource {
  Future<String> derivePublicBitcoinDescriptorFromXpriv(
    String xprv, {
    required ScriptType scriptType,
    required bool isTestnet,
    bool isInternalKeychain = false,
  });
  Future<String> deriveBitcoinDescriptorFromXpub(
    String xpub, {
    required String fingerprint,
    required ScriptType scriptType,
    required bool isTestnet,
    bool isInternalKeychain = false,
  });
  Future<String> derivePublicLiquidDescriptorFromMnemonic(
    String mnemonic, {
    required ScriptType scriptType,
    required bool isTestnet,
  });
}

class DescriptorDataSourceImpl implements DescriptorDataSource {
  const DescriptorDataSourceImpl();

  @override
  Future<String> derivePublicBitcoinDescriptorFromXpriv(
    String xprv, {
    required ScriptType scriptType,
    required bool isTestnet,
    bool isInternalKeychain = false,
  }) async {
    final secretKey = await bdk.DescriptorSecretKey.fromString(xprv);
    final network = isTestnet ? bdk.Network.testnet : bdk.Network.bitcoin;
    final keychain = isInternalKeychain
        ? bdk.KeychainKind.internalChain
        : bdk.KeychainKind.externalChain;
    bdk.Descriptor descriptor;

    switch (scriptType) {
      case ScriptType.bip84:
        descriptor = await bdk.Descriptor.newBip84(
          secretKey: secretKey,
          network: network,
          keychain: keychain,
        );
      case ScriptType.bip49:
        descriptor = await bdk.Descriptor.newBip49(
          secretKey: secretKey,
          network: network,
          keychain: keychain,
        );
      case ScriptType.bip44:
        descriptor = await bdk.Descriptor.newBip44(
          secretKey: secretKey,
          network: network,
          keychain: keychain,
        );
    }

    // `asString` returns the public descriptor.
    return descriptor.asString();
  }

  @override
  Future<String> derivePublicLiquidDescriptorFromMnemonic(
    String mnemonic, {
    required ScriptType scriptType,
    required bool isTestnet,
  }) async {
    final lwk.Descriptor confidentialDescriptor =
        await lwk.Descriptor.newConfidential(
      network: isTestnet ? lwk.Network.testnet : lwk.Network.mainnet,
      mnemonic: mnemonic,
    );

    return confidentialDescriptor.ctDescriptor;
  }

  @override
  Future<String> deriveBitcoinDescriptorFromXpub(
    String xpub, {
    required String fingerprint,
    required ScriptType scriptType,
    required bool isTestnet,
    bool isInternalKeychain = false,
  }) async {
    final publicKey = await bdk.DescriptorPublicKey.fromString(xpub);
    final network = isTestnet ? bdk.Network.testnet : bdk.Network.bitcoin;
    final keychain = isInternalKeychain
        ? bdk.KeychainKind.internalChain
        : bdk.KeychainKind.externalChain;

    bdk.Descriptor.newBip84Public(
      publicKey: publicKey,
      fingerPrint: fingerprint,
      network: network,
      keychain: keychain,
    );
    bdk.Descriptor descriptor;

    switch (scriptType) {
      case ScriptType.bip84:
        descriptor = await bdk.Descriptor.newBip84Public(
          publicKey: publicKey,
          fingerPrint: fingerprint,
          network: network,
          keychain: keychain,
        );
      case ScriptType.bip49:
        descriptor = await bdk.Descriptor.newBip49Public(
          publicKey: publicKey,
          fingerPrint: fingerprint,
          network: network,
          keychain: keychain,
        );
      case ScriptType.bip44:
        descriptor = await bdk.Descriptor.newBip44Public(
          publicKey: publicKey,
          fingerPrint: fingerprint,
          network: network,
          keychain: keychain,
        );
    }

    return descriptor.asString();
  }
}
