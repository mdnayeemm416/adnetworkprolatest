import 'package:hive_flutter/hive_flutter.dart';

/// Storage manager for Adsterra API credentials and settings using Hive.
class AdsterraStorage {
  AdsterraStorage._();
  static final AdsterraStorage instance = AdsterraStorage._();

  static const String _boxName = 'adsterra_box';
  static const String _keyApiKey = 'adsterra_api_key';
  static const String _keyLastSync = 'adsterra_last_sync';
  static const String _keySyncCount = 'adsterra_sync_count';

  Box? _box;

  /// Ensures the Hive box is open and accessible.
  Future<Box> _getBox() async {
    if (_box != null && _box!.isOpen) {
      return _box!;
    }
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  /// Get the saved Adsterra API key.
  Future<String?> getApiKey() async {
    final box = await _getBox();
    final key = box.get(_keyApiKey) as String?;
    return (key != null && key.trim().isNotEmpty) ? key.trim() : null;
  }

  /// Check whether an Adsterra API key is configured.
  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Save or update the Adsterra API key.
  Future<void> saveApiKey(String key) async {
    final box = await _getBox();
    await box.put(_keyApiKey, key.trim());
  }

  /// Save timestamp and count of the last smartlink bulk sync.
  Future<void> saveLastSyncInfo({required int count}) async {
    final box = await _getBox();
    await box.put(_keyLastSync, DateTime.now().toIso8601String());
    await box.put(_keySyncCount, count);
  }

  /// Retrieve the timestamp of the last smartlink bulk sync.
  Future<DateTime?> getLastSyncDate() async {
    final box = await _getBox();
    final dateStr = box.get(_keyLastSync) as String?;
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  /// Retrieve the count of smartlinks imported in the last bulk sync.
  Future<int> getLastSyncCount() async {
    final box = await _getBox();
    return (box.get(_keySyncCount) as int?) ?? 0;
  }

  /// Remove Adsterra credentials (e.g. on full reset or logout if desired).
  Future<void> clearApiKey() async {
    final box = await _getBox();
    await box.delete(_keyApiKey);
    await box.delete(_keyLastSync);
    await box.delete(_keySyncCount);
  }
}
