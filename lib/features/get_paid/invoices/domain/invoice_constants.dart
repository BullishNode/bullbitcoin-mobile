import 'dart:convert';

const invoicePublicDescriptionMaxBytes = 1000;
const invoiceRecipientNameMaxBytes = 100;
const invoiceNumberMaxBytes = 50;

final invoiceNymRegex = RegExp(r'^[a-z0-9][a-z0-9\-]{1,30}[a-z0-9]$');

// UTF-8 bytes, matching Rust String::len() on the bullnym server.
int invoiceUtf8ByteLength(String value) => utf8.encode(value).length;
