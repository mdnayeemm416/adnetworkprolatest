import 'package:adnetwork/core/services/adsterra_storage.dart';
import 'package:adnetwork/layers/data/model/adsterra_models.dart';
import 'package:adnetwork/layers/data/repo/remote/adsterra_repository.dart';
import 'package:adnetwork/layers/data/repo/remote/link_repository.dart';
import 'package:adnetwork/layers/data/repo/remote/leaderboard_repository.dart';
import 'package:flutter/foundation.dart';

class AdsterraSyncResult {
  final bool isSuccess;
  final String message;
  final int deletedCount;
  final int importedCount;
  final List<AdsterraPlacementModel> smartlinks;

  AdsterraSyncResult({
    required this.isSuccess,
    required this.message,
    this.deletedCount = 0,
    this.importedCount = 0,
    this.smartlinks = const [],
  });
}

class AdsterraSyncService {
  AdsterraSyncService._();
  static final AdsterraSyncService instance = AdsterraSyncService._();

  final AdsterraRepository _adsterraRepo = AdsterraRepository();
  final LinkRepository _linkRepo = LinkRepository();
  final LeaderboardRepository _leaderboardRepo = LeaderboardRepository();

  /// Executes full sync:
  /// 1. Verifies API key with Adsterra
  /// 2. Deletes all user's existing links
  /// 3. Fetches up to 20 smartlinks/direct links from Adsterra
  /// 4. Bulk imports them to backend POST /api/links/bulk
  /// 5. Saves API key in Hive on success
  Future<AdsterraSyncResult> syncSmartlinks(String rawApiKey) async {
    final apiKey = rawApiKey.trim();
    if (apiKey.isEmpty) {
      return AdsterraSyncResult(
        isSuccess: false,
        message: 'Adsterra API Key cannot be empty.',
      );
    }

    try {
      // Step 1: Validate API key by fetching placements from Adsterra
      debugPrint('[AdsterraSync] 1. Validating API key & fetching placements...');
      final List<AdsterraPlacementModel> allPlacements;
      try {
        allPlacements = await _adsterraRepo.getPlacements(apiKey);
      } catch (e) {
        debugPrint('[AdsterraSync] Key validation error: $e');
        return AdsterraSyncResult(
          isSuccess: false,
          message: 'Invalid Adsterra API Key or unauthorized. Please verify your token.',
        );
      }

      // Step 2: Delete existing links saved by user
      debugPrint('[AdsterraSync] 2. Deleting user existing links...');
      final int deletedCount = await _linkRepo.deleteAllMyLinks();
      debugPrint('[AdsterraSync] Deleted $deletedCount existing links.');

      // Filter only placements with valid direct/smartlink URLs
      final validPlacements = allPlacements.where((p) {
        final url = p.directUrl;
        return url != null &&
            url.isNotEmpty &&
            (url.startsWith('http://') || url.startsWith('https://'));
      }).toList();

      if (validPlacements.isEmpty) {
        // Save the key anyway since it was validated, but notify user
        await AdsterraStorage.instance.saveApiKey(apiKey);
        return AdsterraSyncResult(
          isSuccess: true,
          message: 'API Key saved, but no active Direct Links/Smartlinks found on your Adsterra account. Please create Direct Links in your Adsterra panel.',
          deletedCount: deletedCount,
          importedCount: 0,
        );
      }

      // Cap at maximum 20 smartlinks
      final smartlinksToImport = validPlacements.take(20).toList();
      debugPrint('[AdsterraSync] Selected ${smartlinksToImport.length} smartlinks (max 20).');

      // Step 4: Build CSV format: ZoneName,PlacementName,PlacementId,URL
      final csvBuffer = StringBuffer();
      for (final p in smartlinksToImport) {
        final zone = (p.domainName ?? 'Adsterra').replaceAll(',', ' ').trim();
        final name = p.name.replaceAll(',', ' ').trim();
        final id = 'PL${p.id}';
        final url = p.directUrl!.trim();
        csvBuffer.writeln('$zone,$name,$id,$url');
      }

      // Step 5: Bulk Import to backend
      debugPrint('[AdsterraSync] 4. Importing bulk links to backend...');
      final bulkResponse = await _linkRepo.importBulkLinks(csvBuffer.toString());

      if (bulkResponse.isSuccess || bulkResponse.statusCode == 201 || bulkResponse.statusCode == 200) {
        // Step 6: Save API Key and sync metadata to Hive
        await AdsterraStorage.instance.saveApiKey(apiKey);
        await AdsterraStorage.instance.saveLastSyncInfo(count: smartlinksToImport.length);

        // Step 7: Also save user's Adsterra API Key to backend server for hourly leaderboard
        try {
          debugPrint('[AdsterraSync] Syncing key to backend /api/user/adsterra-key...');
          await _leaderboardRepo.saveUserAdsterraKey(apiKey);
        } catch (e) {
          debugPrint('[AdsterraSync] Warning: Failed to sync key to backend: $e');
        }

        return AdsterraSyncResult(
          isSuccess: true,
          message: 'Successfully imported ${smartlinksToImport.length} Adsterra smartlinks!',
          deletedCount: deletedCount,
          importedCount: smartlinksToImport.length,
          smartlinks: smartlinksToImport,
        );
      } else {
        // If 403 or error, report server message
        return AdsterraSyncResult(
          isSuccess: false,
          message: bulkResponse.message ?? 'Server bulk import failed. Please try again.',
          deletedCount: deletedCount,
        );
      }
    } catch (e) {
      debugPrint('[AdsterraSync] Error during sync: $e');
      return AdsterraSyncResult(
        isSuccess: false,
        message: 'Sync error: $e',
      );
    }
  }
}
