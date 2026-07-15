import 'dart:convert';

import 'package:characters/characters.dart';

/// Private payer-supplied context for one evidenced Lightning Address payment.
/// The exact text is deliberately immutable and has no status or money effect.
class LightningAddressPaymentComment {
  static const maxGraphemes = 120;
  static const maxUtf8Bytes = 512;

  final String intentId;
  final String nym;
  final int amountMsat;
  final String comment;
  final DateTime receivedAt;

  LightningAddressPaymentComment({
    required this.intentId,
    required this.nym,
    required this.amountMsat,
    required this.comment,
    required DateTime receivedAt,
  }) : receivedAt = receivedAt.toUtc() {
    if (intentId.isEmpty || nym.isEmpty || amountMsat <= 0) {
      throw ArgumentError('Invalid Lightning payment comment evidence');
    }
    final graphemes = comment.characters.length;
    if (graphemes < 1 ||
        graphemes > maxGraphemes ||
        utf8.encode(comment).length > maxUtf8Bytes) {
      throw ArgumentError('Invalid Lightning payment comment text');
    }
  }
}

class LightningAddressPaymentCommentPage {
  static const maxPage = 1000;
  static const maxPageSize = 100;

  final List<LightningAddressPaymentComment> comments;
  final int page;
  final int pageSize;
  final bool hasMore;

  LightningAddressPaymentCommentPage({
    required List<LightningAddressPaymentComment> comments,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  }) : comments = List.unmodifiable(comments) {
    if (page < 1 ||
        page > maxPage ||
        pageSize < 1 ||
        pageSize > maxPageSize ||
        comments.length > pageSize) {
      throw ArgumentError('Invalid Lightning payment comment page');
    }
  }
}
