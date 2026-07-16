import 'package:bb_mobile/core/nostr/nostr_event_id.dart';
import 'package:nostr/nostr.dart' as nostr;

final class NostrEventException implements Exception {
  final String message;
  final Object? cause;

  const NostrEventException(this.message, {this.cause});

  @override
  String toString() => 'NostrEventException: $message';
}

final class NostrEventDraft {
  static final _xOnlyPublicKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  final String authorPublicKeyHex;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;

  NostrEventDraft({
    required String authorPublicKeyHex,
    required this.createdAt,
    required this.kind,
    required List<List<String>> tags,
    required this.content,
  }) : authorPublicKeyHex = authorPublicKeyHex.trim().toLowerCase(),
       tags = _freezeTags(tags) {
    if (!_xOnlyPublicKeyPattern.hasMatch(this.authorPublicKeyHex)) {
      throw const NostrEventException(
        'event author must be a 32-byte x-only hex key',
      );
    }
    if (createdAt < 0) {
      throw const NostrEventException('event timestamp must be non-negative');
    }
    if (kind < 0) {
      throw const NostrEventException('event kind must be non-negative');
    }
  }

  String get id => nostrEventId(
    pubkey: authorPublicKeyHex,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
  );
}

final class NostrSignedEvent {
  static final _eventIdPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final _xOnlyPublicKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final _signaturePattern = RegExp(r'^[0-9a-fA-F]{128}$');

  final String id;
  final String authorPublicKeyHex;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String signatureHex;

  factory NostrSignedEvent.fromDraft({
    required NostrEventDraft draft,
    required String signatureHex,
  }) {
    return NostrSignedEvent._(
      id: draft.id,
      authorPublicKeyHex: draft.authorPublicKeyHex,
      createdAt: draft.createdAt,
      kind: draft.kind,
      tags: draft.tags,
      content: draft.content,
      signatureHex: signatureHex,
    );
  }

  factory NostrSignedEvent.fromRelayFields({
    required String id,
    required String authorPublicKeyHex,
    required int createdAt,
    required int kind,
    required List<List<String>> tags,
    required String content,
    required String signatureHex,
  }) {
    final event = NostrSignedEvent._(
      id: id,
      authorPublicKeyHex: authorPublicKeyHex,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      signatureHex: signatureHex,
    );
    final expectedId = nostrEventId(
      pubkey: event.authorPublicKeyHex,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
    );
    if (event.id != expectedId) {
      throw const NostrEventException('event id does not match its payload');
    }
    return event;
  }

  NostrSignedEvent._({
    required String id,
    required String authorPublicKeyHex,
    required this.createdAt,
    required this.kind,
    required List<List<String>> tags,
    required this.content,
    required String signatureHex,
  }) : id = id.trim().toLowerCase(),
       authorPublicKeyHex = authorPublicKeyHex.trim().toLowerCase(),
       tags = _freezeTags(tags),
       signatureHex = signatureHex.trim().toLowerCase() {
    if (!_eventIdPattern.hasMatch(this.id)) {
      throw const NostrEventException('event id must be a 32-byte hex value');
    }
    if (!_xOnlyPublicKeyPattern.hasMatch(this.authorPublicKeyHex)) {
      throw const NostrEventException(
        'event author must be a 32-byte x-only hex key',
      );
    }
    if (createdAt < 0) {
      throw const NostrEventException('event timestamp must be non-negative');
    }
    if (kind < 0) {
      throw const NostrEventException('event kind must be non-negative');
    }
    if (!_signaturePattern.hasMatch(this.signatureHex)) {
      throw const NostrEventException(
        'event signature must be a 64-byte hex value',
      );
    }
  }
}

final class NostrSignedEventCodec {
  const NostrSignedEventCodec();

  String serialize(NostrSignedEvent event) => _toNostrEvent(event).serialize();

  NostrSignedEvent fromNostrEvent(nostr.Event event) {
    try {
      if (!event.isValid()) {
        throw const NostrEventException(
          'event failed authenticity verification',
        );
      }
      return NostrSignedEvent.fromRelayFields(
        id: event.id,
        authorPublicKeyHex: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
        signatureHex: event.sig,
      );
    } on NostrEventException {
      rethrow;
    } catch (e) {
      throw NostrEventException(
        'event failed authenticity verification',
        cause: e,
      );
    }
  }

  nostr.Event _toNostrEvent(NostrSignedEvent event) {
    return nostr.Event(
      event.id,
      event.authorPublicKeyHex,
      event.createdAt,
      event.kind,
      event.tags,
      event.content,
      event.signatureHex,
      verify: false,
    );
  }
}

List<List<String>> _freezeTags(List<List<String>> tags) {
  return List<List<String>>.unmodifiable(tags.map(List<String>.unmodifiable));
}
