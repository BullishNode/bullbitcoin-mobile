class BullnymQuotaDto {
  final int used;
  final int cap;
  final int remaining;

  const BullnymQuotaDto({
    required this.used,
    required this.cap,
    required this.remaining,
  });

  factory BullnymQuotaDto.fromJson(Object? json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final used = (map['used'] as num?)?.toInt() ?? 0;
    final cap = (map['cap'] as num?)?.toInt() ?? 0;
    return BullnymQuotaDto(
      used: used,
      cap: cap,
      remaining:
          (map['remaining'] as num?)?.toInt() ??
          ((cap - used).clamp(0, cap) as num).toInt(),
    );
  }
}

class BullnymPreviousNymDto {
  final String nym;
  final DateTime createdAt;

  const BullnymPreviousNymDto({required this.nym, required this.createdAt});

  factory BullnymPreviousNymDto.fromJson(Map<String, dynamic> json) {
    return BullnymPreviousNymDto(
      nym: json['nym'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class BullnymRegisterResponseDto {
  final String nym;
  final String lightningAddress;
  final String nip05;
  final BullnymQuotaDto quota;

  const BullnymRegisterResponseDto({
    required this.nym,
    required this.lightningAddress,
    required this.nip05,
    required this.quota,
  });

  factory BullnymRegisterResponseDto.fromJson(Map<String, dynamic> json) {
    return BullnymRegisterResponseDto(
      nym: json['nym'] as String,
      lightningAddress: json['lightning_address'] as String,
      nip05: json['nip05'] as String,
      quota: BullnymQuotaDto.fromJson(json['quota']),
    );
  }
}

class BullnymDeleteResponseDto {
  final BullnymQuotaDto quota;

  const BullnymDeleteResponseDto({required this.quota});

  factory BullnymDeleteResponseDto.fromJson(Map<String, dynamic> json) {
    return BullnymDeleteResponseDto(
      quota: BullnymQuotaDto.fromJson(json['quota']),
    );
  }
}

class BullnymLookupResponseDto {
  final String nym;
  final bool active;
  final BullnymQuotaDto quota;
  final List<BullnymPreviousNymDto> previousNyms;

  const BullnymLookupResponseDto({
    required this.nym,
    required this.active,
    required this.quota,
    required this.previousNyms,
  });

  factory BullnymLookupResponseDto.fromJson(Map<String, dynamic> json) {
    final rawPrevious = json['previous_nyms'];
    return BullnymLookupResponseDto(
      nym: json['nym'] as String,
      active: json['active'] as bool,
      quota: BullnymQuotaDto.fromJson(json['quota']),
      previousNyms: rawPrevious is List
          ? [
              for (final item in rawPrevious)
                BullnymPreviousNymDto.fromJson(item as Map<String, dynamic>),
            ]
          : const [],
    );
  }
}

class BullnymDonationPageDto {
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

  const BullnymDonationPageDto({
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

  factory BullnymDonationPageDto.fromJson(Map<String, dynamic> json) {
    return BullnymDonationPageDto(
      nym: json['nym'] as String,
      header: json['header'] as String,
      description: json['description'] as String,
      displayCurrency: json['display_currency'] as String,
      website: json['website'] as String?,
      twitter: json['twitter'] as String?,
      instagram: json['instagram'] as String?,
      enabled: json['enabled'] as bool,
      isArchived: json['is_archived'] as bool,
      avatarSha256: json['avatar_sha256'] as String?,
      ogSha256: json['og_sha256'] as String?,
      publicUrl: json['public_url'] as String,
    );
  }
}

class BullnymCreateInvoiceResponseDto {
  final String invoiceId;
  final String shareUrl;

  const BullnymCreateInvoiceResponseDto({
    required this.invoiceId,
    required this.shareUrl,
  });

  factory BullnymCreateInvoiceResponseDto.fromJson(Map<String, dynamic> json) {
    return BullnymCreateInvoiceResponseDto(
      invoiceId: json['invoice_id'] as String,
      shareUrl: json['share_url'] as String,
    );
  }
}

class BullnymCancelInvoiceResponseDto {
  final String invoiceId;
  final String status;

  const BullnymCancelInvoiceResponseDto({
    required this.invoiceId,
    required this.status,
  });

  factory BullnymCancelInvoiceResponseDto.fromJson(Map<String, dynamic> json) {
    return BullnymCancelInvoiceResponseDto(
      invoiceId: json['invoice_id'] as String,
      status: json['status'] as String,
    );
  }
}

class BullnymInvoiceListItemDto {
  final String id;
  final String? nymOwner;
  final String origin;
  final String status;
  final int amountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final String? publicDescription;
  final String? recipientName;
  final String? invoiceNumber;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final String? bitcoinAddress;
  final String? liquidAddress;
  final int createdAtUnix;
  final int expiresAtUnix;
  final String? paidVia;
  final int? paidAtUnix;
  final int? paidAmountSat;

  const BullnymInvoiceListItemDto({
    required this.id,
    required this.nymOwner,
    required this.origin,
    required this.status,
    required this.amountSat,
    required this.fiatAmountMinor,
    required this.fiatCurrency,
    required this.publicDescription,
    required this.recipientName,
    required this.invoiceNumber,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    required this.bitcoinAddress,
    required this.liquidAddress,
    required this.createdAtUnix,
    required this.expiresAtUnix,
    required this.paidVia,
    required this.paidAtUnix,
    required this.paidAmountSat,
  });

  factory BullnymInvoiceListItemDto.fromJson(Map<String, dynamic> json) {
    return BullnymInvoiceListItemDto(
      id: json['id'] as String,
      nymOwner: json['nym_owner'] as String?,
      origin: json['origin'] as String,
      status: json['status'] as String,
      amountSat: (json['amount_sat'] as num).toInt(),
      fiatAmountMinor: (json['fiat_amount_minor'] as num?)?.toInt(),
      fiatCurrency: json['fiat_currency'] as String?,
      publicDescription: json['public_description'] as String?,
      recipientName: json['recipient_name'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      acceptBtc: json['accept_btc'] as bool,
      acceptLn: json['accept_ln'] as bool,
      acceptLiquid: json['accept_liquid'] as bool,
      bitcoinAddress: json['bitcoin_address'] as String?,
      liquidAddress: json['liquid_address'] as String?,
      createdAtUnix: (json['created_at_unix'] as num).toInt(),
      expiresAtUnix: (json['expires_at_unix'] as num).toInt(),
      paidVia: json['paid_via'] as String?,
      paidAtUnix: (json['paid_at_unix'] as num?)?.toInt(),
      paidAmountSat: (json['paid_amount_sat'] as num?)?.toInt(),
    );
  }
}

class BullnymListInvoicesResponseDto {
  final List<BullnymInvoiceListItemDto> invoices;
  final int page;
  final int pageSize;
  final bool hasMore;

  const BullnymListInvoicesResponseDto({
    required this.invoices,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  factory BullnymListInvoicesResponseDto.fromJson(Map<String, dynamic> json) {
    final rawInvoices = json['invoices'] as List? ?? const [];
    return BullnymListInvoicesResponseDto(
      invoices: [
        for (final item in rawInvoices)
          BullnymInvoiceListItemDto.fromJson(item as Map<String, dynamic>),
      ],
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? rawInvoices.length,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

class BullnymInvoiceStatusDto {
  final String status;
  final int amountSat;
  final int? rateMinorPerBtc;
  final int rateLocksUntilUnix;
  final int expiresAtUnix;
  final String? paidVia;
  final int? paidAtUnix;
  final int? paidAmountSat;
  final String? lightningPr;
  final String? liquidAddress;
  final String? bitcoinAddress;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final bool rateStale;

  const BullnymInvoiceStatusDto({
    required this.status,
    required this.amountSat,
    required this.rateMinorPerBtc,
    required this.rateLocksUntilUnix,
    required this.expiresAtUnix,
    required this.paidVia,
    required this.paidAtUnix,
    required this.paidAmountSat,
    required this.lightningPr,
    required this.liquidAddress,
    required this.bitcoinAddress,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    required this.rateStale,
  });

  factory BullnymInvoiceStatusDto.fromJson(Map<String, dynamic> json) {
    return BullnymInvoiceStatusDto(
      status: json['status'] as String,
      amountSat: (json['amount_sat'] as num).toInt(),
      rateMinorPerBtc: (json['rate_minor_per_btc'] as num?)?.toInt(),
      rateLocksUntilUnix: (json['rate_locks_until_unix'] as num).toInt(),
      expiresAtUnix: (json['expires_at_unix'] as num).toInt(),
      paidVia: json['paid_via'] as String?,
      paidAtUnix: (json['paid_at_unix'] as num?)?.toInt(),
      paidAmountSat: (json['paid_amount_sat'] as num?)?.toInt(),
      lightningPr: json['lightning_pr'] as String?,
      liquidAddress: json['liquid_address'] as String?,
      bitcoinAddress: json['bitcoin_address'] as String?,
      acceptBtc: json['accept_btc'] as bool,
      acceptLn: json['accept_ln'] as bool,
      acceptLiquid: json['accept_liquid'] as bool,
      rateStale: json['rate_stale'] as bool,
    );
  }
}
