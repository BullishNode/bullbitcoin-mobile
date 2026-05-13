import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/features/send/domain/errors/bullpay_proof_error.dart';
import 'package:bb_mobile/features/send/domain/ports/liquid_direct_pay_port.dart';
import 'package:bb_mobile/features/send/domain/usecases/build_bullpay_proof_usecase.dart';

class LiquidDirectPayment {
  final String address;
  final int amountSat;
  final String bip21;

  LiquidDirectPayment({
    required this.address,
    required this.amountSat,
    required this.bip21,
  });
}

// LUD-16 username: lowercase alnum + `._-`, max 64. Rejects path traversal,
// scheme bleed, whitespace, etc.
final _usernameRegex = RegExp(r'^[a-z0-9._-]{1,64}$');
// Strict hostname: dot-separated lowercase labels, max 253 chars, no `..`,
// no `/`, no `:` (port not allowed in metadata host).
// TLD must start with a letter — rejects IP literals (127.0.0.1) and bare
// hostnames; only DNS-resolved domains pass.
final _domainRegex = RegExp(
  r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]([a-z0-9-]{0,61}[a-z0-9])?$',
);

class TryLiquidDirectPayUsecase {
  final BuildBullpayProofUsecase _buildProof;
  final LiquidDirectPayPort _liquidDirectPay;

  TryLiquidDirectPayUsecase({
    required BuildBullpayProofUsecase buildProof,
    required LiquidDirectPayPort liquidDirectPay,
  }) : _buildProof = buildProof,
       _liquidDirectPay = liquidDirectPay;

  Future<LiquidDirectPayment> execute({
    required String lnAddress,
    required int amountSat,
    required String walletId,
  }) async {
    final parts = lnAddress.split('@');
    if (parts.length != 2) {
      throw const LiquidDirectPayUnavailable();
    }

    final username = parts[0].toLowerCase();
    final domain = parts[1].toLowerCase();
    if (!_usernameRegex.hasMatch(username) ||
        domain.length > 253 ||
        !_domainRegex.hasMatch(domain)) {
      throw const LiquidDirectPayUnavailable();
    }

    final metadataUrl = Uri.https(domain, '/.well-known/lnurlp/$username');

    final metadata = await _liquidDirectPay.fetchMetadata(metadataUrl);

    final hasLiquid = metadata.paymentMethods.contains('L-BTC');
    if (!hasLiquid) {
      throw const LiquidDirectPayUnavailable();
    }

    final callback = metadata.callback;
    // Pin to https + the same domain we just validated. Defeats a malicious
    // LNURLP responder redirecting the proof-of-funds POST to attacker hosts.
    if (callback.scheme != 'https' || callback.host != domain) {
      throw const LiquidDirectPayUnavailable();
    }

    final proof = await _buildProof.execute(walletId: walletId, nym: username);

    final msats = amountSat * 1000;
    final signedCallback = callback.replace(
      queryParameters: {
        ...callback.queryParameters,
        'amount': msats.toString(),
        'payment_method': 'L-BTC',
        'outpoint': proof.outpoint,
        'pubkey': proof.pubkeyHex,
        'sig': proof.sigDerHex,
      },
    );

    final data = await _liquidDirectPay.requestLiquidPayment(signedCallback);

    if (data.status == 'ERROR') {
      final code = data.code;
      if (code != null) {
        throw BullpayProofError.fromServerCode(code: code, reason: data.reason);
      }
      throw const BullpayProofInternal('UnknownServerError');
    }

    final address = data.liquidAddress;
    if (address == null) {
      throw const BullpayProofInternal('MalformedResponse');
    }
    final btcDecimal = (amountSat / 100000000).toStringAsFixed(8);
    final bip21 =
        'liquidnetwork:$address?amount=$btcDecimal&assetid=${AssetConstants.lbtcMainnet}';
    return LiquidDirectPayment(
      address: address,
      amountSat: amountSat,
      bip21: bip21,
    );
  }
}
