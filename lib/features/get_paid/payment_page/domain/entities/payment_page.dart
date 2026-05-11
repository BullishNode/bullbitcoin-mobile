class PaymentPage {
  final String nym;
  final String header;
  final String description;
  final String displayCurrency;
  final String? website;
  final String? twitter;
  final String? instagram;
  final bool enabled;
  final bool isArchived;
  final String? avatarSha256;
  final String? ogSha256;
  final String publicUrl;

  const PaymentPage({
    required this.nym,
    required this.header,
    required this.description,
    required this.displayCurrency,
    required this.website,
    required this.twitter,
    required this.instagram,
    required this.enabled,
    required this.isArchived,
    required this.avatarSha256,
    required this.ogSha256,
    required this.publicUrl,
  });

  bool get isActive => enabled && !isArchived;
}
