import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';

class PaymentPageState {
  final String nym;
  final String header;
  final String description;
  final String displayCurrency;
  final String website;
  final String twitter;
  final String instagram;
  final bool enabled;
  final PaymentPage? page;
  final bool isLoading;
  final bool isSaving;
  final bool isArchiving;
  final bool isUploadingImage;
  final bool loadFailed;
  final String? error;
  final bool saved;
  final bool archived;

  const PaymentPageState({
    this.nym = '',
    this.header = '',
    this.description = '',
    this.displayCurrency = 'CAD',
    this.website = '',
    this.twitter = '',
    this.instagram = '',
    this.enabled = true,
    this.page,
    this.isLoading = false,
    this.isSaving = false,
    this.isArchiving = false,
    this.isUploadingImage = false,
    this.loadFailed = false,
    this.error,
    this.saved = false,
    this.archived = false,
  });

  bool get hasExistingPage => page != null && !page!.isArchived;
  bool get isBusy => isLoading || isSaving || isArchiving || isUploadingImage;

  PaymentPageState copyWith({
    String? nym,
    String? header,
    String? description,
    String? displayCurrency,
    String? website,
    String? twitter,
    String? instagram,
    bool? enabled,
    PaymentPage? page,
    bool clearPage = false,
    bool? isLoading,
    bool? isSaving,
    bool? isArchiving,
    bool? isUploadingImage,
    bool? loadFailed,
    String? error,
    bool clearError = false,
    bool? saved,
    bool? archived,
  }) {
    return PaymentPageState(
      nym: nym ?? this.nym,
      header: header ?? this.header,
      description: description ?? this.description,
      displayCurrency: displayCurrency ?? this.displayCurrency,
      website: website ?? this.website,
      twitter: twitter ?? this.twitter,
      instagram: instagram ?? this.instagram,
      enabled: enabled ?? this.enabled,
      page: clearPage ? null : page ?? this.page,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isArchiving: isArchiving ?? this.isArchiving,
      isUploadingImage: isUploadingImage ?? this.isUploadingImage,
      loadFailed: loadFailed ?? this.loadFailed,
      error: clearError ? null : error ?? this.error,
      saved: saved ?? this.saved,
      archived: archived ?? this.archived,
    );
  }

  factory PaymentPageState.fromPage(PaymentPage page) {
    return PaymentPageState(
      nym: page.nym,
      header: page.header,
      description: page.description,
      displayCurrency: page.displayCurrency,
      website: page.website ?? '',
      twitter: page.twitter ?? '',
      instagram: page.instagram ?? '',
      enabled: page.enabled,
      page: page,
    );
  }
}
