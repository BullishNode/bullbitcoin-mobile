import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_auth_signer.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_failure.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_registration.dart';
import 'package:bb_mobile/features/bullnym/domain/bullpay_signing.dart';
import 'package:meta/meta.dart';

import 'register_bullnym_usecase.dart';

class LookupBullnymRegistrationUsecase {
  final BullnymClientPort _client;
  final BullnymNowSecs _nowSecs;

  const LookupBullnymRegistrationUsecase(
    this._client, [
    this._nowSecs = currentBullpayTimestampSecs,
  ]);

  /// The lookup response links a public key to a permanent nym, Lightning
  /// Address, alias, and online status. The server requires proof of key
  /// possession for that linkage (`bullpay-la-v2` `register-lookup`, empty
  /// nym slot, zero payload fields), so the caller must supply the signer —
  /// which it already holds for every other registration action.
  @useResult
  Future<Result<BullnymLookupResult, BullnymFailure>> execute({
    required BullnymAuthSigner signer,
  }) async {
    final timestamp = _nowSecs();
    final signatureResult = await signBullpayAction(
      signer: signer,
      action: bullpayActionRegisterLookup,
      nymOrEmpty: '',
      payloadFields: const [],
      timestampSecs: timestamp,
    );
    final String signatureHex;
    switch (signatureResult) {
      case Ok(:final value):
        signatureHex = value;
      case Err(:final failure):
        return Err(failure);
    }
    return _client.lookupRegistration(
      npubHex: signer.npubHex,
      timestamp: timestamp,
      signatureHex: signatureHex,
    );
  }
}
