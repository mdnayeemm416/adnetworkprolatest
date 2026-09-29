import 'dart:convert';
import 'package:adnetwork/layers/data/model/adsterra_models.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Direct client for Adsterra Publisher API (api3.adsterratools.com)
class AdsterraRepository {
  static const String _baseUrl = 'https://api3.adsterratools.com';

  Map<String, String> _headers(String apiKey) => {
        'X-API-Key': apiKey.trim(),
        'Accept': 'application/json',
      };

  /// Verify API key by fetching placements
  Future<bool> validateKey(String apiKey) async {
    try {
      await getPlacements(apiKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get estimated balance by calculating last 30 days accumulated revenue
  Future<AdsterraBalanceModel> getBalance(String apiKey) async {
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final startDate = '${thirtyDaysAgo.year}-${thirtyDaysAgo.month.toString().padLeft(2, '0')}-${thirtyDaysAgo.day.toString().padLeft(2, '0')}';
      final finishDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final stats = await getStats(apiKey, startDate: startDate, finishDate: finishDate);
      double totalRev = 0.0;
      for (final s in stats) {
        totalRev += s.revenue;
      }
      return AdsterraBalanceModel(balance: totalRev);
    } catch (_) {
      return AdsterraBalanceModel(balance: 0.0);
    }
  }

  /// Get publisher placements (direct links / smartlinks)
  Future<List<AdsterraPlacementModel>> getPlacements(String apiKey) async {
    final uri = Uri.parse('$_baseUrl/publisher/placements.json');
    final response = await http.get(uri, headers: _headers(apiKey));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final List<dynamic> items;

      if (decoded is Map<String, dynamic> && decoded['items'] is List) {
        items = decoded['items'] as List;
      } else if (decoded is List) {
        items = decoded;
      } else {
        items = [];
      }

      return items
          .map((e) => AdsterraPlacementModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception(
        'Failed to fetch Adsterra placements (${response.statusCode}): ${response.body}',
      );
    }
  }

  /// Fetch publisher statistics by date range
  Future<List<AdsterraStatItem>> getStats(
    String apiKey, {
    required String startDate,
    required String finishDate,
    String groupBy = 'date',
  }) async {
    final uri = Uri.parse('$_baseUrl/publisher/stats.json').replace(
      queryParameters: {
        'start_date': startDate,
        'finish_date': finishDate,
        'group_by': groupBy,
      },
    );

    final response = await http.get(uri, headers: _headers(apiKey));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final List<dynamic> items;

      if (decoded is Map<String, dynamic> && decoded['items'] is List) {
        items = decoded['items'] as List;
      } else if (decoded is List) {
        items = decoded;
      } else {
        items = [];
      }

      return items
          .map((e) => AdsterraStatItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      debugPrint('AdsterraRepository.getStats error: ${response.statusCode}');
      return [];
    }
  }
}
