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
