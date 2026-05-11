import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';

const String bullpayWireDomain = 'bullpay-la-v2';

const String bullpayActionRegister = 'register';
const String bullpayActionDelete = 'delete';
const String bullpayActionDonationPageSave = 'donation-page-save';
const String bullpayActionDonationPageArchive = 'donation-page-archive';

Uint8List buildBullpaySchnorrMessage({
  required String action,
  required String npubHex,
  required String nymOrEmpty,
  required List<String> payloadFields,
  required int timestampSecs,
}) {
  final builder = BytesBuilder();
  void addField(String value) {
    builder.add(utf8.encode(value));
    builder.addByte(0);
  }

  addField(bullpayWireDomain);
  addField(action);
  addField(npubHex);
  addField(nymOrEmpty);
  for (final field in payloadFields) {
    addField(field);
  }
  builder.add(utf8.encode(timestampSecs.toString()));
  return builder.toBytes();
}

String signBullpayAction({
  required NostrKeychainHandle handle,
  required String action,
  required String nymOrEmpty,
  required List<String> payloadFields,
  required int timestampSecs,
}) {
  final message = buildBullpaySchnorrMessage(
    action: action,
    npubHex: handle.publicKeyHex,
    nymOrEmpty: nymOrEmpty,
    payloadFields: payloadFields,
    timestampSecs: timestampSecs,
  );
  return handle.signMessage(message);
}

int currentBullpayTimestampSecs() {
  return DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
}
