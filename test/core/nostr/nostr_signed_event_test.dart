import 'package:bb_mobile/core/nostr/nostr_signed_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;

void main() {
  test('serializes the frozen NIP-01 EVENT frame exactly', () {
    const codec = NostrSignedEventCodec();
    final draft = NostrEventDraft(
      authorPublicKeyHex: _authorPublicKey,
      createdAt: 123,
      kind: 30078,
      tags: const [
        ['d', 'manifest'],
      ],
      content: _content,
    );
    final event = NostrSignedEvent.fromDraft(
      draft: draft,
      signatureHex: _signature,
    );

    expect(event.id, _eventId);
    expect(codec.serialize(event), _eventFrame);
  });

  test('deep freezes signed event tags', () {
    final event = NostrSignedEvent.fromDraft(
      draft: NostrEventDraft(
        authorPublicKeyHex: _authorPublicKey,
        createdAt: 123,
        kind: 30078,
        tags: const [
          ['d', 'manifest'],
        ],
        content: _content,
      ),
      signatureHex: _signature,
    );

    expect(() => event.tags.add(['p', 'x']), throwsUnsupportedError);
    expect(() => event.tags.single.add('x'), throwsUnsupportedError);
  });

  test('verifies relay event ids and signatures', () {
    const codec = NostrSignedEventCodec();
    final packageEvent = nostr.Event.from(
      kind: 30078,
      content: 'genuine',
      secretKey: _secretKey,
      createdAt: 123,
      tags: const [
        ['d', 'opaque'],
      ],
    );

    final verified = codec.fromNostrEvent(packageEvent);

    expect(verified.id, packageEvent.id);
    expect(verified.content, 'genuine');
    expect(
      () => codec.fromNostrEvent(
        nostr.Event(
          packageEvent.id,
          packageEvent.pubkey,
          packageEvent.createdAt,
          packageEvent.kind,
          packageEvent.tags,
          'tampered',
          packageEvent.sig,
          verify: false,
        ),
      ),
      throwsA(isA<NostrEventException>()),
    );
  });

  test('rejects a relay id that does not match the signed fields', () {
    expect(
      () => NostrSignedEvent.fromRelayFields(
        id: 'f' * 64,
        authorPublicKeyHex: _authorPublicKey,
        createdAt: 123,
        kind: 30078,
        tags: const [
          ['d', 'manifest'],
        ],
        content: _content,
        signatureHex: _signature,
      ),
      throwsA(isA<NostrEventException>()),
    );
  });
}

const _authorPublicKey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _secretKey =
    '0000000000000000000000000000000000000000000000000000000000000001';
const _content =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAA==';
const _signature =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _eventId =
    '8924c440aec6da3657dba376305c10231cb0809384cd0c206877f6debc952b91';
const _eventFrame =
    '["EVENT",{"id":"8924c440aec6da3657dba376305c10231cb0809384cd0c206877f6debc952b91",'
    '"pubkey":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
    '"created_at":123,"kind":30078,"tags":[["d","manifest"]],'
    '"content":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAA==","sig":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbb"}]';
