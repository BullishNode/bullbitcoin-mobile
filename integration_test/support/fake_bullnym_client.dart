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

  /// Every donation-page call fails with a retryable server error.
  serverUnreachable,
}

/// Point-of-sale fault modes for the §9/F10 matrix. Independent of both
/// [FakeBullnymMode] and [FakeDonationPageMode] so a single instance can hold a
/// live page (102) while the POS (103) surface is driven through its own
/// heal/provision faults - the coexistence property (DELTA 4). Applied only to
/// `kind='pos'` calls; `kind='payment_page'` calls stay on [donationPageMode].
enum FakePosMode {
  /// GET returns the stored pos row (or NotFound if none saved); writes succeed.
  normal,

  /// GET always throws DonationPageNotFound (pos row purged / never created).
  missing,

  /// GET returns the stored pos row marked archived.
  archived,

  /// A kind=pos save/archive fails with AuthError - the pre-release pay2
  /// fail-closed emulation (KR-2/DG-P7): the old server rebuilds the signed
  /// message without `kind`, so the signature never verifies.
  saveAuthError,

  /// Every kind=pos call fails with a retryable server error.
  serverUnreachable,
}

/// In-memory [BullnymClientPort] for L1 tests (HARNESS §2.2). It survives the
/// simulated app-state wipe (the fake object outlives it), records register and
/// donation-page write calls, and is toggle-driven so a single instance can
/// drive the DG-3 heal matrix (live / lapsed / missing / unreachable).
class FakeBullnymClient implements BullnymClientPort {
  FakeBullnymMode mode = FakeBullnymMode.live;
  FakeDonationPageMode donationPageMode = FakeDonationPageMode.normal;
  FakePosMode posMode = FakePosMode.normal;
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

  int get totalDonationWriteCalls =>
      saveDonationPageCalls.length + archiveDonationPageCalls.length;

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
    final isPos = kind == bullnymDonationPageKindPos;
    if (isPos) {
      if (posMode == FakePosMode.serverUnreachable) throw _serverUnreachable();
      if (posMode == FakePosMode.missing) throw _notFound();
    } else {
      if (donationPageMode == FakeDonationPageMode.serverUnreachable) {
        throw _serverUnreachable();
      }
      if (donationPageMode == FakeDonationPageMode.missing) throw _notFound();
    }
    final page = _pages[_pageKey(nym, kind)];
    if (page == null) throw _notFound();
    final archived = isPos
        ? posMode == FakePosMode.archived
        : donationPageMode == FakeDonationPageMode.archived;
    if (archived) return _copyWith(page, isArchived: true);
    return page;
  }

  @override
  Future<BullnymDonationPage> saveDonationPage(
    BullnymSaveDonationPageRequest request,
  ) async {
    saveDonationPageCalls.add(request);
    final isPos = request.kind == bullnymDonationPageKindPos;
    if (isPos) {
      // KR-1 server backstop: a kind=pos save has NO LA-cursor fallback, so a
      // descriptorless pos save is HARD-REJECTED here (never silently routed to
      // the LA wallet 101). The client must make an empty descriptor impossible.
      if (request.ctDescriptor.isEmpty) throw _donationPageInvalid();
      if (posMode == FakePosMode.serverUnreachable) throw _serverUnreachable();
      if (posMode == FakePosMode.saveAuthError) throw _authError();
    } else {
      if (donationPageMode == FakeDonationPageMode.serverUnreachable) {
        throw _serverUnreachable();
      }
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
      publicUrl: isPos
          ? 'https://example.invalid/${request.nym}/pos'
          : 'https://example.invalid/${request.nym}',
    );
    _pages[_pageKey(request.nym, request.kind)] = page;
    return page;
  }

  @override
  Future<BullnymDonationPage> archiveDonationPage(
    BullnymArchiveDonationPageRequest request,
  ) async {
    archiveDonationPageCalls.add(request);
    final isPos = request.kind == bullnymDonationPageKindPos;
    if (isPos) {
      if (posMode == FakePosMode.serverUnreachable) throw _serverUnreachable();
      if (posMode == FakePosMode.saveAuthError) throw _authError();
    } else {
      if (donationPageMode == FakeDonationPageMode.serverUnreachable) {
        throw _serverUnreachable();
      }
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

  // The kind=pos server backstop for a descriptorless save (KR-1): the server
  // rejects it as invalid rather than falling back to any wallet.
  BullnymException _donationPageInvalid() =>
      const BullnymException.serverRejectedRequest(
        code: 'DonationPageInvalid',
        diagnosticReason: 'kind=pos save requires a non-empty ct_descriptor',
        statusCode: 400,
        retryable: false,
      );

  // The pre-release-server fail-closed emulation (KR-2/DG-P7): signing over a
  // `kind` the old server does not rebuild yields a signature mismatch.
  BullnymException _authError() =>
      const BullnymException.serverRejectedRequest(
        code: 'AuthError',
        diagnosticReason: 'signature verification failed',
        statusCode: 401,
        retryable: false,
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
