class ApiResponse<T> {
  final bool? success;
  final int? statusCode;
  final String? message;
  final String? devMessage;
  final T? data;
  final List<T>? dataList;
  final bool? isLocked;
  final String? instruction;

  ApiResponse({
    this.success,
    this.statusCode,
    this.message,
    this.data,
    this.dataList,
    this.devMessage,
    this.isLocked,
    this.instruction,
  });

  /// Whether the API call succeeded.
  bool get isSuccess => success == true;

  factory ApiResponse.fromJson(
    Map<String, dynamic> res,
    T Function(dynamic json)? fromJsonModel,
  ) {
    var rawData = res.containsKey('data') ? res['data'] : res;

    T? parsedData;
    List<T>? parsedList;

    if (rawData != null) {
      if (fromJsonModel != null) {
        if (rawData is List) {
          parsedList = rawData.map((e) => fromJsonModel(e)).toList();
        } else {
          parsedData = fromJsonModel(rawData);
        }
      } else {
        if (rawData is T) {
          parsedData = rawData;
        } else {
          try {
            parsedData = rawData as T?;
          } catch (_) {
            parsedData = null;
          }
        }
      }
    }

    // The API returns `"status": true/false` (boolean).
    final rawStatus = res['status'];
    bool? success;
    int? statusCode;

    if (rawStatus is bool) {
      success = rawStatus;
    } else if (rawStatus is int) {
      statusCode = rawStatus;
      success = rawStatus >= 200 && rawStatus < 300;
    }

    return ApiResponse(
      success: success,
      statusCode: statusCode,
      message: res['message'] as String?,
      devMessage: res['dev_message'] as String?,
      isLocked: res['is_locked'] as bool?,
      instruction: res['instruction'] as String?,
      data: parsedData,
      dataList: parsedList,
    );
  }

  Map<String, dynamic> toJson(dynamic Function(T model) toJsonModel) => {
        'message': message,
        'dev_message': devMessage,
        'status': success,
        'is_locked': isLocked,
        'instruction': instruction,
        'data': data != null ? toJsonModel(data as T) : null,
        'datalist': dataList?.map((x) => toJsonModel(x)).toList(),
      };
}
