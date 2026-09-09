import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:adnetwork/core/services/api_client.dart';

class MobileConfig {
  final String adsHeight;
  final String adsWidth;
  final String allowDns;
  final String autoPermission;
  final String breakTimeLinkCount;
  final String campaignMust;
  final String campaignSeconds;
  final String campaignSecondsMax;
  final String campaignSecondsMin;
  final String feedBreakTime;
  final String maxAdsTime;
  final String minAdsTime;
  final String useDeviceResolution;
  final String maintenanceMode;
  final String maintenanceMessage;

  const MobileConfig({
    required this.adsHeight,
    required this.adsWidth,
    required this.allowDns,
    required this.autoPermission,
    required this.breakTimeLinkCount,
    required this.campaignMust,
    required this.campaignSeconds,
    required this.campaignSecondsMax,
    required this.campaignSecondsMin,
    required this.feedBreakTime,
    required this.maxAdsTime,
    required this.minAdsTime,
    required this.useDeviceResolution,
    required this.maintenanceMode,
    required this.maintenanceMessage,
  });

  static const defaultConfig = MobileConfig(
    adsHeight: "256",
    adsWidth: "256",
    allowDns: "0",
    autoPermission: "",
    breakTimeLinkCount: "100",
    campaignMust: "1",
    campaignSeconds: "20",
    campaignSecondsMax: "25",
    campaignSecondsMin: "15",
    feedBreakTime: "30",
    maxAdsTime: "15",
    minAdsTime: "10",
    useDeviceResolution: "1",
    maintenanceMode: "0",
    maintenanceMessage: "System is currently under maintenance. Please try again later.",
  );

  int get breakTimeLinkCountInt => int.tryParse(breakTimeLinkCount) ?? 100;
  int get feedBreakTimeMinutes => int.tryParse(feedBreakTime) ?? 30;

  List<String> get autoPermissionEmails => autoPermission
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toList();

  bool hasAutoPermission(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final normalized = email.trim().toLowerCase();
    return autoPermissionEmails.contains(normalized);
  }

  factory MobileConfig.fromJson(Map<String, dynamic> json) {
    // If the json has a "data" field, look inside it; otherwise parse the root object.
    final Map<String, dynamic> data = (json['data'] is Map<String, dynamic>)
        ? json['data']
        : json;

    return MobileConfig(
      adsHeight: data['ads_height']?.toString() ?? "256",
      adsWidth: data['ads_width']?.toString() ?? "256",
      allowDns: data['allow_dns']?.toString() ?? "0",
      autoPermission: (data['auto_permisson'] ?? data['auto_permission'])?.toString() ?? "",
      breakTimeLinkCount: data['break_time_link_count']?.toString() ?? "100",
      campaignMust: data['campaign_must']?.toString() ?? "1",
      campaignSeconds: data['campaign_seconds']?.toString() ?? "20",
      campaignSecondsMax: data['campaign_seconds_max']?.toString() ?? "25",
      campaignSecondsMin: data['campaign_seconds_min']?.toString() ?? "15",
      feedBreakTime: data['feed_break_time']?.toString() ?? "30",
      maxAdsTime: data['max_ads_time']?.toString() ?? "15",
      minAdsTime: data['min_ads_time']?.toString() ?? "10",
      useDeviceResolution: data['use_device_resolution']?.toString() ?? "1",
      maintenanceMode: data['maintenance_mode']?.toString() ?? "0",
      maintenanceMessage: data['maintenance_message']?.toString() ?? "System is currently under maintenance. Please try again later.",
    );
  }

  Map<String, String> toJson() {
    return {
      'ads_height': adsHeight,
      'ads_width': adsWidth,
      'allow_dns': allowDns,
      'auto_permisson': autoPermission,
      'break_time_link_count': breakTimeLinkCount,
      'campaign_must': campaignMust,
      'campaign_seconds': campaignSeconds,
      'campaign_seconds_max': campaignSecondsMax,
      'campaign_seconds_min': campaignSecondsMin,
      'feed_break_time': feedBreakTime,
      'max_ads_time': maxAdsTime,
      'min_ads_time': minAdsTime,
      'use_device_resolution': useDeviceResolution,
      'maintenance_mode': maintenanceMode,
      'maintenance_message': maintenanceMessage,
    };
  }
}

class MobileConfigManager {
  MobileConfigManager._();
  static final MobileConfigManager instance = MobileConfigManager._();

  static const String _storageKey = 'mobile_config';

  MobileConfig _config = MobileConfig.defaultConfig;

  MobileConfig get config => _config;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_storageKey);
      if (cached != null) {
        final json = jsonDecode(cached) as Map<String, dynamic>;
        _config = MobileConfig.fromJson(json);
      }
    } catch (e) {
      debugPrint('MobileConfigManager init error: $e');
    }
  }

  Future<void> fetchAndCacheConfig() async {
    try {
      final response = await ApiClient.instance.get('/api/mobile-config');
      if (response.isSuccess && response.data != null) {
        final rawData = response.data;
        if (rawData is Map<String, dynamic>) {
          _config = MobileConfig.fromJson(rawData);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_storageKey, jsonEncode(_config.toJson()));
          debugPrint('MobileConfigManager successfully updated and cached config: ${_config.toJson()}');
        } else {
          debugPrint('MobileConfigManager API data is not a Map: $rawData');
        }
      } else {
        debugPrint('MobileConfigManager API response unsuccessful: ${response.message}');
      }
    } catch (e) {
      debugPrint('MobileConfigManager fetchAndCacheConfig error: $e');
    }
  }
}
