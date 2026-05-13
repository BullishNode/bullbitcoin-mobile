import 'dart:convert';

import 'package:flutter/services.dart';

class Utf8ByteLimitFormatter extends TextInputFormatter {
  final int maxBytes;

  Utf8ByteLimitFormatter(this.maxBytes) : assert(maxBytes > 0);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (utf8.encode(newValue.text).length <= maxBytes) {
      return newValue;
    }
    return oldValue;
  }
}
