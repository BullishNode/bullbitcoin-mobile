import 'dart:convert';

final bullnymNymRegex = RegExp(r'^[a-z0-9][a-z0-9\-]{1,30}[a-z0-9]$');

// UTF-8 bytes, matching Rust String::len() on the bullnym server.
int bullnymUtf8ByteLength(String value) => utf8.encode(value).length;
