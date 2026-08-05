import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';


/// Manages JWT token persistence using SharedPreferences.
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'auth_user_id';
  static const String _cachedEmailKey = 'cached_email';
  static const String _cachedPasswordKey = 'cached_password';
  static const String _manualLogoutKey = 'manual_logout';
  static const String _autoLikeEnabledKey = 'auto_like_enabled';

  /// Save JWT token after successful login.
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Retrieve stored JWT token.  Returns `null` if not logged in.
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Check whether a token exists (user is logged in).
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Save the current user's ID for quick access.
  Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
  }

  /// Retrieve the current user's ID.
  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_autoLikeEnabledKey);
    // Note: Deliberately not clearing _cachedEmailKey and _cachedPasswordKey here
    // so "Remember Me" persists across manual logouts if implemented,
    // but the prompt usually means they stay until unchecked.
  }

  /// Save credentials for remember me
  Future<void> saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedEmailKey, email);
    await prefs.setString(_cachedPasswordKey, password);
  }

  /// Retrieve cached email
  Future<String?> getCachedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cachedEmailKey);
  }

  /// Retrieve cached password
  Future<String?> getCachedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cachedPasswordKey);
  }

  /// Clear cached credentials
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedEmailKey);
    await prefs.remove(_cachedPasswordKey);
  }

  /// Sets whether the user has manually logged out recently.
  Future<void> setManualLogout(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_manualLogoutKey, value);
  }

  /// Checks if the user manually logged out to prevent immediate auto-login loop
  Future<bool> hasManuallyLoggedOut() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_manualLogoutKey) ?? false;
  }

  /// Save auto-like subscription status
  Future<void> saveAutoLikeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLikeEnabledKey, enabled);
  }

  /// Check if auto-like is enabled
  Future<bool> isAutoLikeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoLikeEnabledKey) ?? false;
  }

  static const String _feedAutoplayKey = 'feed_autoplay_key';
  static const String _campaignAutoplayKey = 'campaign_autoplay_key';

  /// Save feed autoplay status (1 for on, 0 for off)
  Future<void> saveFeedAutoplay(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_feedAutoplayKey, value);
  }

  /// Retrieve feed autoplay status
  Future<int> getFeedAutoplay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_feedAutoplayKey) ?? 0;
  }

  /// Save campaign autoplay status (1 for on, 0 for off)
  Future<void> saveCampaignAutoplay(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_campaignAutoplayKey, value);
  }

  /// Retrieve campaign autoplay status
  Future<int> getCampaignAutoplay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_campaignAutoplayKey) ?? 0;
  }

  /// Retrieves the existing device ID or generates a new persistent one if not present.
  Future<String> getOrGenerateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');
    if (deviceId == null) {
      final random = Random();
      final part1 = DateTime.now().microsecondsSinceEpoch;
      final part2 = random.nextInt(1000000);
      deviceId = 'device_${part1}_$part2';
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }
}
