# Get Paid

The Get Paid hub composes product-safe public facades. It never receives wallet
keys, descriptors, signing handles, or raw Bullnym protocol responses.

## Private Lightning payment comments

The Lightning Address facade owns the wallet-derived merchant authentication
for the identity-wide `lnurl-comment-history` read. Bullnym returns only
payment-evidenced comments; no anonymous status or public Page/POS response is
consulted. Get Paid holds the resulting immutable evidence in memory for the
history session and renders the payer text only after the merchant opens a
specific row's detail sheet.

History rows show amount, permanent nym, and evidence time without comment
text. The detail uses Flutter `Text` directly: it does not parse HTML, Markdown,
links, mentions, or executable markup. Comments never affect amounts, payment
status, settlement, fallback, or invoice attribution, and this client does not
log them. Pagination preserves the server's newest-first evidence order and
deduplicates immutable intent IDs if new payments shift a page boundary.
