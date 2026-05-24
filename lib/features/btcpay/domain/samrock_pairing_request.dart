import 'package:bb_mobile/core/errors/bull_exception.dart';

class SamRockPairingRequest {
  final Uri protocolUri;
  final String storeId;
  final String otp;
  final Set<SamRockSetupCapability> setup;

  const SamRockPairingRequest._({
    required this.protocolUri,
    required this.storeId,
    required this.otp,
    required this.setup,
  });

  bool get supportsBitcoinChain =>
      setup.contains(SamRockSetupCapability.bitcoinChain);

  bool get supportsLiquidChain =>
      setup.contains(SamRockSetupCapability.liquidChain);

  bool get supportsLightning =>
      setup.contains(SamRockSetupCapability.bitcoinLightning);
}

enum SamRockSetupCapability {
  bitcoinChain('btc-chain'),
  liquidChain('liquid-chain'),
  bitcoinLightning('btc-ln');

  final String value;

  const SamRockSetupCapability(this.value);

  static SamRockSetupCapability? tryParse(String value) {
    return switch (value.trim().toLowerCase()) {
      'btc' || 'btc-chain' => SamRockSetupCapability.bitcoinChain,
      'lbtc' || 'liquid-chain' => SamRockSetupCapability.liquidChain,
      'btcln' || 'btc-ln' => SamRockSetupCapability.bitcoinLightning,
      _ => null,
    };
  }
}

class SamRockPairingRequestParser {
  const SamRockPairingRequestParser();

  SamRockPairingRequest parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasAbsolutePath) {
      throw SamRockPairingRequestException('Invalid SamRock pairing URL');
    }
    if (uri.scheme != 'https') {
      throw SamRockPairingRequestException(
        'SamRock pairing URL must use HTTPS',
      );
    }
    if (uri.host.trim().isEmpty) {
      throw SamRockPairingRequestException(
        'SamRock pairing URL is missing its server host',
      );
    }
    if (!uri.path.endsWith('/samrock/protocol')) {
      throw SamRockPairingRequestException(
        'SamRock pairing URL must point to /samrock/protocol',
      );
    }
    final storeId = _storeId(uri);
    if (storeId == null || storeId.isEmpty) {
      throw SamRockPairingRequestException(
        'SamRock pairing URL is missing its BTCPay store ID',
      );
    }

    final otp = uri.queryParameters['otp']?.trim();
    if (otp == null || otp.isEmpty) {
      throw SamRockPairingRequestException(
        'SamRock pairing URL is missing its OTP',
      );
    }

    final setup = _parseSetup(uri.queryParameters['setup']);
    if (!setup.contains(SamRockSetupCapability.bitcoinChain) &&
        !setup.contains(SamRockSetupCapability.liquidChain) &&
        !setup.contains(SamRockSetupCapability.bitcoinLightning)) {
      throw SamRockPairingRequestException(
        'SamRock pairing URL does not request a supported payment method',
      );
    }

    return SamRockPairingRequest._(
      protocolUri: uri,
      storeId: storeId,
      otp: otp,
      setup: setup,
    );
  }

  String? _storeId(Uri uri) {
    final segments = uri.pathSegments;
    final pluginsIndex = segments.indexOf('plugins');
    if (pluginsIndex < 0 || pluginsIndex + 3 >= segments.length) return null;
    if (segments[pluginsIndex + 2] != 'samrock') return null;
    if (segments[pluginsIndex + 3] != 'protocol') return null;
    return segments[pluginsIndex + 1].trim();
  }

  Set<SamRockSetupCapability> _parseSetup(String? value) {
    if (value == null || value.trim().isEmpty) {
      throw SamRockPairingRequestException(
        'SamRock pairing URL is missing setup capabilities',
      );
    }
    if (value.trim().toLowerCase() == 'all') {
      return SamRockSetupCapability.values.toSet();
    }

    final setup = <SamRockSetupCapability>{};
    for (final rawCapability in value.split(',')) {
      final capability = SamRockSetupCapability.tryParse(rawCapability);
      if (capability == null) {
        throw SamRockPairingRequestException(
          'SamRock pairing URL contains unsupported setup capabilities',
        );
      }
      setup.add(capability);
    }

    if (setup.isEmpty) {
      throw SamRockPairingRequestException(
        'SamRock pairing URL does not contain supported setup capabilities',
      );
    }
    return setup;
  }
}

class SamRockPairingRequestException extends BullException {
  SamRockPairingRequestException(super.message);
}
