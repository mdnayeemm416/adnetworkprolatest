import 'package:adnetwork/config/api_endpoints.dart';
import 'package:adnetwork/core/services/api_client.dart';
import 'package:adnetwork/layers/data/model/leaderboard_model.dart';
import 'package:adnetwork/layers/dto/api_response.dart';

class LeaderboardRepository {
  final ApiClient _api = ApiClient.instance;

  /// GET /api/leaderboard/hourly
  Future<ApiResponse<HourlyLeaderboardResponse>> getHourlyLeaderboard({
    String? date,
    int? hour,
  }) async {
    final Map<String, String> queryParams = {};
    if (date != null && date.isNotEmpty) queryParams['date'] = date;
    if (hour != null) queryParams['hour'] = hour.toString();

    return _api.get<HourlyLeaderboardResponse>(
      ApiEndpoints.hourlyLeaderboard,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      fromJsonModel: (json) => HourlyLeaderboardResponse.fromJson(
        json as Map<String, dynamic>,
      ),
    );
  }

  /// POST /api/user/adsterra-key
  /// Saves and validates the user's Adsterra API token on the backend server.
  Future<ApiResponse<dynamic>> saveUserAdsterraKey(String apiKey) async {
    return _api.post(
      ApiEndpoints.userAdsterraKey,
      body: {'apiKey': apiKey.trim()},
    );
  }

  /// GET /api/user/adsterra-key
  /// Fetches the user's backend key connection status and last sync time.
  Future<ApiResponse<dynamic>> getUserAdsterraKeyStatus() async {
    return _api.get(ApiEndpoints.userAdsterraKey);
  }

  /// DELETE /api/user/adsterra-key
  /// Removes the connected key from backend server.
  Future<ApiResponse<dynamic>> deleteUserAdsterraKey() async {
    return _api.delete(ApiEndpoints.userAdsterraKey);
  }
}
