import 'dart:convert';
import 'dart:typed_data';

// Wire format pinned by bullnym `auth.rs::build_la_v1_message`:
// `<domain>\x00<action>\x00<npub_hex>\x00(<field>\x00)*<timestamp>`.
// Bumping the tag invalidates all prior sigs.
const String _laV1DomainTag = 'bullpay-la-v1';

Uint8List buildLaV1Message({
  required String action,
  required String npubHex,
  required List<String> payloadFields,
  required int timestampSecs,
}) {
  final builder = BytesBuilder();
  builder.add(utf8.encode(_laV1DomainTag));
  builder.addByte(0);
  builder.add(utf8.encode(action));
  builder.addByte(0);
  builder.add(utf8.encode(npubHex));
  builder.addByte(0);
  for (final field in payloadFields) {
    builder.add(utf8.encode(field));
    builder.addByte(0);
  }
  builder.add(utf8.encode(timestampSecs.toString()));
  return builder.toBytes();
}

int currentUnixTimestampSecs() =>
    DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
