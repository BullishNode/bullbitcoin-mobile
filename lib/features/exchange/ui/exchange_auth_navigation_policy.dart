bool isAllowedExchangeAuthNavigation({
  required String requestUrl,
  required String authBaseUrl,
}) {
  final request = Uri.tryParse(requestUrl);
  if (request == null ||
      request.scheme != 'https' ||
      request.host.isEmpty ||
      request.userInfo.isNotEmpty) {
    return false;
  }

  final authOrigin = _httpsOrigin(authBaseUrl);
  if (authOrigin == null) return false;
  if (request.origin == authOrigin) return true;

  if (request.origin != 'https://www.bullbitcoin.com') {
    return false;
  }

  return request.path.contains('terms') || request.path.contains('privacy');
}

String? _httpsOrigin(String value) {
  if (value != value.trim()) return null;

  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }

  return uri.origin;
}
