import 'package:nostr/nostr.dart' as nostr;

String nostrEventId({
  required String pubkey,
  required int createdAt,
  required int kind,
  required List<List<String>> tags,
  required String content,
}) {
  return nostr.Event.partial(
    pubkey: pubkey,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
  ).getEventId();
}
