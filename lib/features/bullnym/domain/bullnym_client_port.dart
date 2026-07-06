import 'package:bb_mobile/features/bullnym/domain/bullnym_donation_page.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_registration.dart';

abstract interface class BullnymClientPort {
  Future<BullnymRegisterResult> register(BullnymRegisterRequest request);

  Future<void> deleteRegistration(BullnymDeleteRegistrationRequest request);

  Future<BullnymLookupResult> lookupRegistration({required String npubHex});

  /// Public read of the current donation-page row for `nym`/`kind`. Throws a
  /// `serverRejectedRequest` with code `DonationPageNotFound` when absent.
  Future<BullnymDonationPage> getDonationPage({
    required String nym,
    required String kind,
  });

  Future<BullnymDonationPage> saveDonationPage(
    BullnymSaveDonationPageRequest request,
  );

  Future<BullnymDonationPage> archiveDonationPage(
    BullnymArchiveDonationPageRequest request,
  );

  Future<BullnymSupportedCurrencies> getSupportedCurrencies();
}

class BullnymRegisterRequest {
  final String nym;
  final String ctDescriptor;
  final String npubHex;
  final String signatureHex;
  final int timestamp;

  const BullnymRegisterRequest({
    required this.nym,
    required this.ctDescriptor,
    required this.npubHex,
    required this.signatureHex,
    required this.timestamp,
  });
}

class BullnymDeleteRegistrationRequest {
  final String nym;
  final String npubHex;
  final String signatureHex;
  final int timestamp;

  const BullnymDeleteRegistrationRequest({
    required this.nym,
    required this.npubHex,
    required this.signatureHex,
    required this.timestamp,
  });
}
