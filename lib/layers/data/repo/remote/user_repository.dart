import 'package:adnetwork/config/api_endpoints.dart';
import 'package:adnetwork/core/services/api_client.dart';
import 'package:adnetwork/layers/data/model/score_model.dart';
import 'package:adnetwork/layers/data/model/user_model.dart';
import 'package:adnetwork/layers/data/model/user_stats_model.dart';
import 'package:adnetwork/layers/data/model/activity_stats_model.dart';
import 'package:adnetwork/layers/dto/api_response.dart';

class UserRepository {
  final ApiClient _api = ApiClient.instance;

  /// PATCH /users/change-password
  Future<ApiResponse<dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _api.patch(
      ApiEndpoints.changePassword,
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  /// GET /users/me/score
  Future<ApiResponse<ScoreModel>> getMyScore() async {
    return _api.get<ScoreModel>(
      ApiEndpoints.myScore,
      fromJsonModel: (json) =>
          ScoreModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /users/me/stats
  Future<ApiResponse<UserStatsModel>> getMyStats() async {
    return _api.get<UserStatsModel>(
      ApiEndpoints.myStats,
      fromJsonModel: (json) =>
          UserStatsModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// PATCH /users/me/like-back-limit
  Future<ApiResponse<dynamic>> updateMaxLikeBackLimit(int limit) async {
    return _api.patch(
      ApiEndpoints.likeBackLimit,
      body: {
        'limit': limit,
      },
    );
  }

  /// GET /users/me/activity-stats
  Future<ApiResponse<ActivityStatsModel>> getActivityStats() async {
    return _api.get<ActivityStatsModel>(
      ApiEndpoints.myActivityStats,
      fromJsonModel: (json) =>
          ActivityStatsModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /users/:id
  Future<ApiResponse<UserModel>> getUserProfile(String userId) async {
    return _api.get<UserModel>(
      ApiEndpoints.userProfile(userId),
      fromJsonModel: (json) {
        final Map<String, dynamic> combined = Map<String, dynamic>.from(
          json['user'] ?? {},
        );
        if (json['stats'] != null) {
          combined.addAll(Map<String, dynamic>.from(json['stats']));
        }
        if (json['is_following'] != null) {
          combined['is_following'] = json['is_following'];
        }
        if (json['links'] != null) {
          combined['links'] = json['links'];
        }
        return UserModel.fromJson(combined);
      },
    );
  }

  /// GET /users/explore
  Future<ApiResponse<UserModel>> exploreUsers({
    int page = 1,
    int limit = 30,
  }) async {
    return _api.get<UserModel>(
      '${ApiEndpoints.exploreUsers}?page=$page&limit=$limit',
      fromJsonModel: (json) => UserModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// POST /users/:id/follow  (toggle)
  Future<ApiResponse<dynamic>> toggleFollow(String userId) async {
    return _api.post(ApiEndpoints.toggleFollow(userId));
  }

  /// GET /users/:id/followers
  Future<ApiResponse<UserModel>> getFollowers(
    String userId, {
    int page = 1,
    int limit = 30,
  }) async {
    return _api.get<UserModel>(
      '${ApiEndpoints.followers(userId)}?page=$page&limit=$limit',
      fromJsonModel: (json) => UserModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /users/:id/following
  Future<ApiResponse<UserModel>> getFollowing(
    String userId, {
    int page = 1,
    int limit = 30,
  }) async {
    return _api.get<UserModel>(
      '${ApiEndpoints.following(userId)}?page=$page&limit=$limit',
      fromJsonModel: (json) => UserModel.fromJson(json as Map<String, dynamic>),
    );
  }
}
