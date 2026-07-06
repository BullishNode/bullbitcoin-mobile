import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_donation_page.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_error.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_registration.dart';

enum FakeBullnymMode {
  /// Lookup returns an active registration.
  live,

  /// Lookup returns active:false with the previous nym (a lapsed registration).
  inactiveWithPreviousNym,

  /// Lookup returns a NymNotFound rejection (genuinely missing).
  registrationMissing,

  /// Lookup and register fail with a non-NymNotFound server error.
  serverUnreachable,
}

/// Donation-page fault modes for the §9/F9 matrix. Independent of the
/// registration [FakeBullnymMode] so a single instance can drive the heal
/// matrix (page live / archived / missing / unreachable) while the nym lookup
/// stays live.
enum FakeDonationPageMode {
  /// GET returns the stored row (or NotFound if none saved); writes succeed.
  normal,

  /// GET always throws DonationPageNotFound (page row purged / never created).
  missing,

  /// GET returns the stored row marked archived.
  archived,

  /// Save fails with AuthError — the pre-migration-034 server emulation
  /// (signature includes `kind`, old server rebuilds without it → mismatch).
  saveAuthError,

  /// Every donation-page call fails with a retryable server error.
  serverUnreachable,
}

/// In-memory [BullnymClientPort] for L1 tests (HARNESS §2.2). It survives the
/// simulated app-state wipe (the fake object outlives it), records register and
/// donation-page write calls, and is toggle-driven so a single instance can
/// drive the DG-3 heal matrix (live / lapsed / missing / unreachable).
class FakeBullnymClient implements BullnymClientPort {
  FakeBullnymMode mode = FakeBullnymMode.live;
  FakeDonationPageMode donationPageMode = FakeDonationPageMode.normal;
  String nym = 'alice';

  final List<String> registeredNyms = [];
  final List<BullnymSaveDonationPageRequest> saveDonationPageCalls = [];
  final List<BullnymArchiveDonationPageRequest> archiveDonationPageCalls = [];

  // Server-side donation-page state keyed `(nym, kind)`; survives wipeAppState.
  final Map<String, BullnymDonationPage> _pages = {};

  List<BullnymSupportedCurrency> supportedCurrencies = const [
    BullnymSupportedCurrency(code: 'CAD', precision: 2),
    BullnymSupportedCurrency(code: 'USD', precision: 2),
    BullnymSupportedCurrency(code: 'EUR', precision: 2),
  ];

  String get _lightningAddress => '$nym@example.invalid';

  String _pageKey(String nym, String kind) => '$nym|$kind';

  @override
  Future<BullnymRegisterResult> register(BullnymRegisterRequest request) async {
    registeredNyms.add(request.nym);
    if (mode == FakeBullnymMode.serverUnreachable) {
      throw const BullnymException.serverRejectedRequest(
        code: 'ServiceUnavailable',
        diagnosticReason: 'fake relay unreachable',
        statusCode: 503,
        retryable: true,
      );
    }
    nym = request.nym;
    mode = FakeBullnymMode.live;
    return BullnymRegisterResult(nym: nym, lightningAddress: _lightningAddress);
  }

  @override
  Future<void> deleteRegistration(
    BullnymDeleteRegistrationRequest request,
  ) async {}

  @override
  Future<BullnymLookupResult> lookupRegistration({
    required String npubHex,
  }) async {
    switch (mode) {
      case FakeBullnymMode.live:
        return BullnymLookupResult(
          nym: nym,
          active: true,
          lightningAddress: _lightningAddress,
        );
      case FakeBullnymMode.inactiveWithPreviousNym:
        return BullnymLookupResult(nym: nym, active: false);
      case FakeBullnymMode.registrationMissing:
        throw const BullnymException.serverRejectedRequest(
          code: 'NymNotFound',
          diagnosticReason: 'no registration for npub',
          statusCode: 404,
          retryable: false,
        );
      case FakeBullnymMode.serverUnreachable:
        throw const BullnymException.serverRejectedRequest(
          code: 'ServiceUnavailable',
          diagnosticReason: 'fake relay unreachable',
          statusCode: 503,
          retryable: true,
        );
    }
  }

  @override
  Future<BullnymDonationPage> getDonationPage({
    required String nym,
    required String kind,
  }) async {
    if (donationPageMode == FakeDonationPageMode.serverUnreachable) {
      throw _serverUnreachable();
    }
    if (donationPageMode == FakeDonationPageMode.missing) {
      throw _notFound();
    }
    final page = _pages[_pageKey(nym, kind)];
    if (page == null) throw _notFound();
    if (donationPageMode == FakeDonationPageMode.archived) {
      return _copyWith(page, isArchived: true);
    }
    return page;
  }

  @override
  Future<BullnymDonationPage> saveDonationPage(
    BullnymSaveDonationPageRequest request,
  ) async {
    saveDonationPageCalls.add(request);
    if (donationPageMode == FakeDonationPageMode.serverUnreachable) {
      throw _serverUnreachable();
    }
    if (donationPageMode == FakeDonationPageMode.saveAuthError) {
      throw const BullnymException.serverRejectedRequest(
        code: 'AuthError',
        diagnosticReason: 'signature verification failed',
        statusCode: 401,
        retryable: false,
      );
    }
    final page = BullnymDonationPage(
      nym: request.nym,
      header: request.header,
      description: request.description,
      displayCurrency: request.displayCurrency,
      website: request.website.isEmpty ? null : request.website,
      twitter: request.twitter.isEmpty ? null : request.twitter,
      instagram: request.instagram.isEmpty ? null : request.instagram,
      kind: request.kind,
      posMode: false,
      enabled: request.enabled,
      isArchived: false,
      publicUrl: 'https://example.invalid/${request.nym}',
    );
    _pages[_pageKey(request.nym, request.kind)] = page;
    return page;
  }

  @override
  Future<BullnymDonationPage> archiveDonationPage(
    BullnymArchiveDonationPageRequest request,
  ) async {
    archiveDonationPageCalls.add(request);
    if (donationPageMode == FakeDonationPageMode.serverUnreachable) {
      throw _serverUnreachable();
    }
    final key = _pageKey(request.nym, request.kind);
    final page = _pages[key];
    if (page == null || page.isArchived) {
      // Double-archive / archive-of-missing: the server preserves nothing to
      // archive and returns DonationPageNotFound.
      throw _notFound();
    }
    final archived = _copyWith(page, isArchived: true);
    _pages[key] = archived;
    return archived;
  }

  @override
  Future<BullnymSupportedCurrencies> getSupportedCurrencies() async {
    if (donationPageMode == FakeDonationPageMode.serverUnreachable) {
      throw _serverUnreachable();
    }
    return BullnymSupportedCurrencies(currencies: supportedCurrencies);
  }

  BullnymException _notFound() => const BullnymException.serverRejectedRequest(
    code: 'DonationPageNotFound',
    diagnosticReason: 'no donation page for nym',
    statusCode: 200,
    retryable: false,
  );

  BullnymException _serverUnreachable() =>
      const BullnymException.serverRejectedRequest(
        code: 'ServiceUnavailable',
        diagnosticReason: 'fake server unreachable',
        statusCode: 503,
        retryable: true,
      );

  BullnymDonationPage _copyWith(
    BullnymDonationPage page, {
    bool? isArchived,
  }) {
    return BullnymDonationPage(
      nym: page.nym,
      header: page.header,
      description: page.description,
      displayCurrency: page.displayCurrency,
      website: page.website,
      twitter: page.twitter,
      instagram: page.instagram,
      kind: page.kind,
      posMode: page.posMode,
      enabled: page.enabled,
      isArchived: isArchived ?? page.isArchived,
      avatarSha256: page.avatarSha256,
      ogSha256: page.ogSha256,
      publicUrl: page.publicUrl,
    );
  }
}
