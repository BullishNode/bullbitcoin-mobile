import 'dart:convert';

import 'package:characters/characters.dart';

const int bullnymLnurlCommentMaxGraphemes = 120;
const int bullnymLnurlCommentMaxUtf8Bytes = 512;
const int bullnymLnurlCommentMaxHistoryPage = 1000;
const int bullnymLnurlCommentMaxHistoryPageSize = 100;

/// One payment-evidenced row from Bullnym's merchant-authenticated LNURL
/// comment history. The exact payer text is private and must never be logged or
/// projected into a public status model.
class BullnymLnurlCommentHistoryItem {
  final String intentId;
  final String nym;
  final int amountMsat;
  final String comment;
  final int receivedAtUnix;

  const BullnymLnurlCommentHistoryItem({
    required this.intentId,
    required this.nym,
    required this.amountMsat,
    required this.comment,
    required this.receivedAtUnix,
  });
}

class BullnymLnurlCommentHistoryResponse {
  final List<BullnymLnurlCommentHistoryItem> comments;
  final int page;
  final int pageSize;
  final bool hasMore;

  const BullnymLnurlCommentHistoryResponse({
    required this.comments,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });
}

bool isValidBullnymLnurlComment(String value) {
  final graphemes = value.characters.length;
  return graphemes > 0 &&
      graphemes <= bullnymLnurlCommentMaxGraphemes &&
      utf8.encode(value).length <= bullnymLnurlCommentMaxUtf8Bytes;
}
