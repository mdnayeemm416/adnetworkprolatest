import 'package:adnetwork/config/api_endpoints.dart';
import 'package:adnetwork/core/services/api_client.dart';
import 'package:adnetwork/layers/data/model/user_model.dart';
import 'package:adnetwork/layers/data/model/device_association_model.dart';
import 'package:adnetwork/layers/data/model/client_override_model.dart';
import 'package:adnetwork/layers/data/model/finance_summary_model.dart';
import 'package:adnetwork/layers/data/model/finance_daily_detail_model.dart';
import 'package:adnetwork/layers/dto/api_response.dart';

class AdminRepository {
  final ApiClient _api = ApiClient.instance;

  /// GET /admin/users
  Future<ApiResponse<UserModel>> getAllUsers() async {
    return _api.get<UserModel>(
      ApiEndpoints.adminUsers,
      fromJsonModel: (json) =>
          UserModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /admin/users/pending
  Future<ApiResponse<UserModel>> getPendingApprovals() async {
    return _api.get<UserModel>(
      ApiEndpoints.adminPending,
      fromJsonModel: (json) =>
          UserModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/approve
  Future<ApiResponse<UserModel>> approveUser(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminApprove(userId),
      fromJsonModel: (json) =>
          UserModel.fromJson(
              (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/reject
  Future<ApiResponse<UserModel>> rejectUser(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminReject(userId),
      fromJsonModel: (json) =>
          UserModel.fromJson(
              (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/block
  Future<ApiResponse<UserModel>> blockUser(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminBlock(userId),
      fromJsonModel: (json) =>
          UserModel.fromJson(
              (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/unblock
  Future<ApiResponse<UserModel>> unblockUser(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminUnblock(userId),
      fromJsonModel: (json) =>
          UserModel.fromJson(
              (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/make-admin
  Future<ApiResponse<UserModel>> makeAdmin(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminMakeAdmin(userId),
      fromJsonModel: (json) =>
          UserModel.fromJson(
              (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/remove-admin
  Future<ApiResponse<UserModel>> removeAdmin(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminRemoveAdmin(userId),
      fromJsonModel: (json) => UserModel.fromJson(
          (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/make-moderator
  Future<ApiResponse<UserModel>> makeModerator(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminMakeModerator(userId),
      fromJsonModel: (json) => UserModel.fromJson(
          (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/remove-moderator
  Future<ApiResponse<UserModel>> removeModerator(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminRemoveModerator(userId),
      fromJsonModel: (json) => UserModel.fromJson(
          (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/reset-password
  Future<ApiResponse<UserModel>> resetPassword(String userId) async {
    return _api.patch<UserModel>(
      ApiEndpoints.adminResetPassword(userId),
      fromJsonModel: (json) => UserModel.fromJson(
          (json as Map<String, dynamic>)['user'] as Map<String, dynamic>),
    );
  }

  /// GET /admin/users/reset-requests
  Future<ApiResponse<UserModel>> getResetRequests({
    int page = 1,
    int limit = 20,
  }) async {
    return _api.get<UserModel>(
      ApiEndpoints.adminResetRequests,
      queryParams: {
        'page': page.toString(),
        'limit': limit.toString(),
      },
      fromJsonModel: (json) => UserModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /api/admin/devices/pending
  Future<ApiResponse<DeviceAssociationModel>> getPendingDevices({
    int page = 1,
    int limit = 50,
  }) async {
    return _api.get<DeviceAssociationModel>(
      ApiEndpoints.adminPendingDevices,
      queryParams: {
        'page': page.toString(),
        'limit': limit.toString(),
      },
      fromJsonModel: (json) => DeviceAssociationModel.fromJson(
          json as Map<String, dynamic>),
    );
  }

  /// PATCH /admin/users/:id/subscription
  Future<ApiResponse<dynamic>> updateSubscription(
    String userId,
    int autolike, {
    int? isFree,
    String? paymentMethod,
    String? txid,
  }) async {
    return _api.patch(
      ApiEndpoints.adminUpdateSubscription(userId),
      body: {
        'autolike': autolike,
        if (isFree != null) 'is_free': isFree,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (txid != null) 'txid': txid,
      },
    );
  }

  /// PATCH /admin/users/bulk/subscription
  Future<ApiResponse<dynamic>> bulkUpdateSubscription(List<String> userIds, int autolike) async {
    return _api.patch(
      ApiEndpoints.adminBulkUpdateSubscription,
      body: {
        'userIds': userIds,
        'autolike': autolike,
      },
    );
  }

  /// GET /api/getprice
  Future<ApiResponse<double>> getSubscriptionPrice({String? namespace}) async {
    return _api.get<double>(
      ApiEndpoints.getPrice,
      queryParams: namespace != null ? {'namespace': namespace} : null,
      fromJsonModel: (json) {
        if (json is Map && json.containsKey('price')) {
          final p = json['price'];
          if (p is num) return p.toDouble();
          return double.tryParse(p.toString()) ?? 0.0;
        }
        if (json is num) return json.toDouble();
        return double.tryParse(json.toString()) ?? 0.0;
      },
    );
  }

  /// POST /api/setprice
  Future<ApiResponse<dynamic>> setSubscriptionPrice(double price, {String? appname}) async {
    return _api.post(
      ApiEndpoints.setPrice,
      body: {
        'price': price,
        if (appname != null) 'appname': appname,
      },
    );
  }

  /// GET /api/admin/clients
  Future<ApiResponse<ClientOverrideModel>> getClientOverrides({String? appname}) async {
    return _api.get<ClientOverrideModel>(
      ApiEndpoints.adminClients,
      queryParams: appname != null ? {'appname': appname} : null,
      fromJsonModel: (json) => ClientOverrideModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// POST /api/admin/clients
  Future<ApiResponse<dynamic>> createClientOverride({
    required String clientName,
    required String status,
    String? appname,
  }) async {
    return _api.post(
      ApiEndpoints.adminClients,
      body: {
        'client_name': clientName,
        'status': status,
        if (appname != null) 'appname': appname,
      },
    );
  }

  /// PATCH /api/admin/clients/:id
  Future<ApiResponse<dynamic>> updateClientOverride(
    String id, {
    String? clientName,
    String? status,
    String? appname,
  }) async {
    return _api.patch(
      ApiEndpoints.adminClientById(id),
      body: {
        if (clientName != null) 'client_name': clientName,
        if (status != null) 'status': status,
        if (appname != null) 'appname': appname,
      },
    );
  }

  /// DELETE /api/admin/clients/:id
  Future<ApiResponse<dynamic>> deleteClientOverride(String id) async {
    return _api.delete(
      ApiEndpoints.adminClientById(id),
    );
  }

  /// GET /api/admin/finance/summary
  Future<ApiResponse<FinanceSummaryModel>> getFinanceSummary({
    required String cycle,
    String? namespace,
  }) async {
    return _api.get<FinanceSummaryModel>(
      ApiEndpoints.financeSummary,
      queryParams: {
        'cycle': cycle,
        if (namespace != null && namespace != 'all') 'namespace': namespace,
        if (namespace != null && namespace != 'all') 'appname': namespace,
      },
      fromJsonModel: (json) => FinanceSummaryModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /api/admin/finance/daily-detail
  Future<ApiResponse<DailyDetailModel>> getDailyDetail({
    String? date,
    String? namespace,
    int page = 1,
    int limit = 50,
  }) async {
    return _api.get<DailyDetailModel>(
      ApiEndpoints.financeDailyDetail,
      queryParams: {
        if (date != null && date.isNotEmpty) 'date': date,
        if (namespace != null && namespace != 'all') 'namespace': namespace,
        if (namespace != null && namespace != 'all') 'appname': namespace,
        'page': page.toString(),
        'limit': limit.toString(),
      },
      fromJsonModel: (json) => DailyDetailModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// POST /api/admin/finance/payouts
  Future<ApiResponse<dynamic>> logPartnerPayout({
    required double shakilAmount,
    required double nayeemAmount,
    required double rashedAmount,
    required String cycle,
    String? namespace,
    String? notes,
  }) async {
    return _api.post(
      ApiEndpoints.financePayouts,
      body: {
        'shakil_amount': shakilAmount,
        'nayeem_amount': nayeemAmount,
        'rashed_amount': rashedAmount,
        'cycle': cycle,
        if (namespace != null && namespace != 'all') 'namespace': namespace,
        'appname': (namespace != null && namespace != 'all') ? namespace : 'adnetworkpro',
        if (notes != null) 'notes': notes,
      },
    );
  }

  /// POST /api/admin/devices/approve
  Future<ApiResponse<dynamic>> approveDevice(String userId, String deviceId) async {
    return _api.post<dynamic>(
      ApiEndpoints.adminApproveDevice,
      body: {
        'userId': userId,
        'deviceId': deviceId,
      },
      fromJsonModel: (json) => json,
    );
  }

  /// POST /api/admin/devices/reject
  Future<ApiResponse<dynamic>> rejectDevice(String userId, String deviceId) async {
    return _api.post<dynamic>(
      ApiEndpoints.adminRejectDevice,
      body: {
        'userId': userId,
        'deviceId': deviceId,
      },
      fromJsonModel: (json) => json,
    );
  }
}
