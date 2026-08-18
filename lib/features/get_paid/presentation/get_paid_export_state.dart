enum GetPaidExportStatus { initial, loading, success, empty, failure }

class GetPaidExportState {
  final GetPaidExportStatus status;

  const GetPaidExportState({this.status = GetPaidExportStatus.initial});

  bool get isLoading => status == GetPaidExportStatus.loading;
}
