import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/upload_payment_page_image_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_error_message.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_state.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PaymentPageCubit extends Cubit<PaymentPageState> {
  final FindPaymentPageUsecase _findPaymentPage;
  final SavePaymentPageUsecase _savePaymentPage;
  final ArchivePaymentPageUsecase _archivePaymentPage;
  final UploadPaymentPageImageUsecase _uploadImage;

  PaymentPageCubit({
    required FindPaymentPageUsecase findPaymentPage,
    required SavePaymentPageUsecase savePaymentPage,
    required ArchivePaymentPageUsecase archivePaymentPage,
    required UploadPaymentPageImageUsecase uploadImage,
  }) : _findPaymentPage = findPaymentPage,
       _savePaymentPage = savePaymentPage,
       _archivePaymentPage = archivePaymentPage,
       _uploadImage = uploadImage,
       super(const PaymentPageState());

  Future<void> load({required String nym}) async {
    if (nym.isEmpty) {
      emit(
        state.copyWith(
          nym: '',
          clearPage: true,
          error: 'Choose a Bullnym name before creating a payment page',
          isLoading: false,
          loadFailed: false,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        nym: nym,
        isLoading: true,
        clearError: true,
        loadFailed: false,
        saved: false,
        archived: false,
      ),
    );
    try {
      final page = await _findPaymentPage.execute(nym: nym);
      if (isClosed) return;
      if (page == null || page.isArchived) {
        emit(
          state.copyWith(
            nym: nym,
            isLoading: false,
            clearError: true,
            clearPage: true,
            loadFailed: false,
          ),
        );
        return;
      }
      emit(PaymentPageState.fromPage(page));
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoading: false,
          loadFailed: true,
          error: paymentPageErrorMessage(e),
        ),
      );
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Payment Page load failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          loadFailed: true,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  void setHeader(String value) {
    emit(state.copyWith(header: value, clearError: true, saved: false));
  }

  void setDescription(String value) {
    emit(state.copyWith(description: value, clearError: true, saved: false));
  }

  void setDisplayCurrency(String value) {
    emit(
      state.copyWith(displayCurrency: value, clearError: true, saved: false),
    );
  }

  void setWebsite(String value) {
    emit(state.copyWith(website: value, clearError: true, saved: false));
  }

  void setTwitter(String value) {
    emit(state.copyWith(twitter: value, clearError: true, saved: false));
  }

  void setInstagram(String value) {
    emit(state.copyWith(instagram: value, clearError: true, saved: false));
  }

  bool validateImageBytes(List<int> bytes) {
    try {
      UploadPaymentPageImageUsecase.validateBytes(bytes);
      if (state.error != null) {
        emit(state.copyWith(clearError: true));
      }
      return true;
    } on PaymentPageApplicationError catch (e) {
      emit(state.copyWith(error: paymentPageErrorMessage(e)));
      return false;
    }
  }

  Future<void> publish() async {
    await save(enabled: true);
  }

  Future<void> save({List<int>? imageBytes, bool? enabled}) async {
    if (state.nym.isEmpty || state.loadFailed || state.isBusy) return;
    emit(state.copyWith(isSaving: true, clearError: true, saved: false));
    try {
      final selectedImageBytes = imageBytes;
      if (selectedImageBytes != null) {
        UploadPaymentPageImageUsecase.validateBytes(selectedImageBytes);
      }
      final command = SavePaymentPageCommand(
        nym: state.nym,
        header: state.header.trim(),
        description: state.description.trim(),
        displayCurrency: state.displayCurrency,
        website: _blankToNull(state.website),
        twitter: _blankToNull(state.twitter),
        instagram: _blankToNull(state.instagram),
        enabled: enabled ?? state.enabled,
      );
      var page = await _savePaymentPage.execute(command: command);
      if (selectedImageBytes != null) {
        try {
          page = await _uploadImage.execute(
            nym: state.nym,
            bytes: selectedImageBytes,
          );
        } on PaymentPageApplicationError catch (e) {
          if (isClosed) return;
          emit(
            PaymentPageState.fromPage(
              page,
            ).copyWith(error: paymentPageErrorMessage(e)),
          );
          return;
        } on Exception catch (e) {
          if (isClosed) return;
          log.warning('Payment Page image upload failed after save', error: e);
          emit(
            PaymentPageState.fromPage(
              page,
            ).copyWith(error: 'Something went wrong. Please try again.'),
          );
          return;
        }
      }
      if (isClosed) return;
      emit(
        PaymentPageState.fromPage(
          page,
        ).copyWith(isSaving: false, saved: true, clearError: true),
      );
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(state.copyWith(isSaving: false, error: paymentPageErrorMessage(e)));
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Payment Page save failed', error: e);
      emit(
        state.copyWith(
          isSaving: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<void> archive() async {
    if (state.nym.isEmpty || state.loadFailed || state.isBusy) return;
    emit(state.copyWith(isArchiving: true, clearError: true, archived: false));
    try {
      await _archivePaymentPage.execute(
        command: ArchivePaymentPageCommand(nym: state.nym),
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          isArchiving: false,
          clearPage: true,
          archived: true,
          saved: false,
          clearError: true,
        ),
      );
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(isArchiving: false, error: paymentPageErrorMessage(e)),
      );
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Payment Page archive failed', error: e);
      emit(
        state.copyWith(
          isArchiving: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<void> uploadImage(List<int> bytes) async {
    if (state.nym.isEmpty ||
        state.loadFailed ||
        !state.hasExistingPage ||
        state.isBusy) {
      return;
    }
    emit(state.copyWith(isUploadingImage: true, clearError: true));
    try {
      final page = await _uploadImage.execute(nym: state.nym, bytes: bytes);
      if (isClosed) return;
      emit(
        PaymentPageState.fromPage(
          page,
        ).copyWith(isUploadingImage: false, clearError: true),
      );
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isUploadingImage: false,
          error: paymentPageErrorMessage(e),
        ),
      );
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Payment Page image upload failed', error: e);
      emit(
        state.copyWith(
          isUploadingImage: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
