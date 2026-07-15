/// Deployed identity-wide action for merchant-private, payment-evidenced LNURL
/// payer comments. The signed nym slot is empty and the two decimal pagination
/// fields are ordered exactly as `[page, pageSize]`.
const String bullpayActionLnurlCommentHistory = 'lnurl-comment-history';

List<String> buildLnurlCommentHistoryPayloadFields({
  required int page,
  required int pageSize,
}) {
  return [page.toString(), pageSize.toString()];
}
