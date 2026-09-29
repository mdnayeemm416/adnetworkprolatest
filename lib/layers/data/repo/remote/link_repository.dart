import 'package:adnetwork/config/api_endpoints.dart';
import 'package:adnetwork/core/services/api_client.dart';
import 'package:adnetwork/layers/data/model/comment_model.dart';
import 'package:adnetwork/layers/data/model/link_model.dart';
import 'package:adnetwork/layers/dto/api_response.dart';

class LinkRepository {
  final ApiClient _api = ApiClient.instance;

  /// GET /links?page=1&limit=10
  Future<ApiResponse<LinkModel>> getGlobalFeed() async {
    return _api.get<LinkModel>(
      ApiEndpoints.links,

      fromJsonModel: (json) => LinkModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /mylinks
  Future<ApiResponse<LinkModel>> getMyLinks() async {
    return _api.get<LinkModel>(
      ApiEndpoints.myLinks,
      fromJsonModel: (json) => LinkModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /links/:id  (side-effect: increments view counter)
  Future<ApiResponse<LinkModel>> getLink(String linkId) async {
    return _api.get<LinkModel>(
      ApiEndpoints.linkById(linkId),
      fromJsonModel: (json) => LinkModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// POST /links
  Future<ApiResponse<LinkModel>> createLink({
    required String title,
    required String url,
    String? description,
    String? tags,
  }) async {
    return _api.post<LinkModel>(
      ApiEndpoints.links,
      body: {
        'title': title,
        'url': url,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
      },
      fromJsonModel: (json) => LinkModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// PATCH /links/:id
  Future<ApiResponse<LinkModel>> updateLink(
    String linkId, {
    String? title,
    String? url,
    String? description,
    String? tags,
  }) async {
    final Map<String, dynamic> body = {};
    if (title != null) body['title'] = title;
    if (url != null) body['url'] = url;
    if (description != null) body['description'] = description;
    if (tags != null) body['tags'] = tags;

    return _api.patch<LinkModel>(
      ApiEndpoints.linkById(linkId),
      body: body,
      fromJsonModel: (json) => LinkModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// DELETE /links/:id
  Future<ApiResponse<dynamic>> deleteLink(String linkId) async {
    return _api.delete(ApiEndpoints.linkById(linkId));
  }

  /// POST /links/:id/like  (toggle)
  Future<ApiResponse<dynamic>> toggleLike(String linkId) async {
    return _api.post(ApiEndpoints.toggleLike(linkId));
  }

  /// POST /links/:id/comment
  Future<ApiResponse<CommentModel>> addComment({
    required String linkId,
    required String text,
  }) async {
    return _api.post<CommentModel>(
      ApiEndpoints.addComment(linkId),
      body: {'text': text},
      fromJsonModel: (json) =>
          CommentModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// GET /links/:id/comments
  Future<ApiResponse<CommentModel>> getComments(String linkId) async {
    return _api.get<CommentModel>(
      ApiEndpoints.linkComments(linkId),
      fromJsonModel: (json) =>
          CommentModel.fromJson(json as Map<String, dynamic>),
    );
  }

  /// POST /api/links/bulk
  /// Body: {"text": "ZoneName,PlacementName,PlacementId,URL\n..."}
  Future<ApiResponse<dynamic>> importBulkLinks(String csvText) async {
    return _api.post(
      ApiEndpoints.bulkLinks,
      body: {'text': csvText},
    );
  }

  /// Delete all existing links of the current user.
  /// Fetches my links and deletes each one. Returns the number of links deleted.
  Future<int> deleteAllMyLinks() async {
    try {
      final res = await getMyLinks();
      final List<LinkModel> links = [];
      if (res.dataList != null && res.dataList!.isNotEmpty) {
        links.addAll(res.dataList!);
      } else if (res.data != null) {
        links.add(res.data!);
      }

      int deletedCount = 0;
      for (final link in links) {
        if (link.id != null && link.id!.isNotEmpty) {
          try {
            final delRes = await deleteLink(link.id!);
            if (delRes.isSuccess) {
              deletedCount++;
            }
          } catch (_) {}
        }
      }
      return deletedCount;
    } catch (_) {
      return 0;
    }
  }
}
