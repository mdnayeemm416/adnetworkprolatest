import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';

/// Represents a link currently being loaded in one of the 4 WebView slots.
class ActiveLink {
  final String url;
  final String? linkId;
  final DateTime displayedAt;
  final int retryCount;

  ActiveLink({
    required this.url,
    this.linkId,
    required this.displayedAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'linkId': linkId,
    'displayedAt': displayedAt.toIso8601String(),
    'retryCount': retryCount,
  };

  factory ActiveLink.fromJson(Map<String, dynamic> json) => ActiveLink(
    url: json['url'] as String,
    linkId: json['linkId'] as String?,
    displayedAt: DateTime.parse(json['displayedAt'] as String),
    retryCount: (json['retryCount'] as int?) ?? 0,
  );

  int get remainingSeconds {
    final elapsed = DateTime.now().difference(displayedAt).inSeconds;
    return (20 - elapsed).clamp(0, 20);
  }

  bool get isExpired => remainingSeconds <= 0;
}

/// Manages a queue of URLs with 4 simultaneously active WebView slots.
///
/// Architecture:
/// - 4 separate WebView instances load URLs directly as top-level pages
///   (not iframes), avoiding X-Frame-Options / CSP restrictions.
/// - After each page loads, it stays for 5–10 seconds (random),
///   then the slot moves to the next URL in the queue.
/// - If a page fails to load, it is dropped immediately without retries.
/// - All state is persisted to SharedPreferences.
/// - When a slot finishes viewing, the associated linkId is emitted on
///   [completedLinkStream] so the like API can be called at that point.
class LinkQueueManager {
  static final LinkQueueManager instance = LinkQueueManager._();
  LinkQueueManager._();

  static const _pendingKey = 'link_queue_pending';
  static const _activeKey = 'link_queue_active';
  static const int maxSlots = 3;
  static const int maxRetries = 0;

  late SharedPreferences _prefs;
  final _random = Random();
  Timer? _sweeperTimer;

  /// Pending URLs with retry counts.
  final List<_PendingUrl> _pending = [];

  /// Active links indexed by slot (0..3). Null means the slot is empty.
  final List<ActiveLink?> _slots = List.filled(maxSlots, null);

  final _controller = StreamController<List<ActiveLink?>>.broadcast();

  /// Stream that emits a linkId whenever a link has been fully viewed
  /// in the WebView and should now have its like API called.
  final _completedLinkController = StreamController<String>.broadcast();

  /// Stream of slot states — a list of exactly 4 entries (nullable).
  Stream<List<ActiveLink?>> get slotsStream => _controller.stream;

  /// Stream of completed linkIds — subscribe to this to fire the like API.
  Stream<String> get completedLinkStream => _completedLinkController.stream;

  /// Current snapshot of all 4 slots.
  List<ActiveLink?> get slots => List.unmodifiable(_slots);

  /// Number of pending links waiting in queue.
  int get pendingCount => _pending.length;

  /// Whether there are any links to process.
  bool get hasWork => _slots.any((s) => s != null) || _pending.isNotEmpty;

  /// Generate a random delay for page viewing based on the mobile config.
  Duration get randomViewDuration {
    final minS = int.tryParse(MobileConfigManager.instance.config.minAdsTime) ?? 10;
    final maxS = int.tryParse(MobileConfigManager.instance.config.maxAdsTime) ?? 15;
    if (maxS <= minS) {
      return Duration(seconds: minS);
    }
    final range = maxS - minS + 1;
    return Duration(seconds: minS + _random.nextInt(range));
  }

  /// Initialize from SharedPreferences cache on app start.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadFromCache();
    _promoteToSlots();
    _persist();
    _emit();

    // Periodic sweeper: every 15s, force-expire any slot older than 45s.
    // Belt-and-suspenders safeguard in case the WebView overlay fails to
    // call onSlotFinished/onSlotError.
    _sweeperTimer?.cancel();
    _sweeperTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sweepStuckSlots();
    });
  }

  /// Force-expire any slot whose link has been active for more than 45 seconds.
  void _sweepStuckSlots() {
    final now = DateTime.now();
    bool changed = false;
    for (int i = 0; i < maxSlots; i++) {
      final link = _slots[i];
      if (link != null) {
        final elapsed = now.difference(link.displayedAt).inSeconds;
        if (elapsed > 45) {
          debugPrint(
            '[LinkQueue] \u{1F9F9} Sweeper: slot $i stuck for ${elapsed}s, force-expiring: ${link.url}',
          );
          // Emit completed so the like API is still called
          if (link.linkId != null && link.linkId!.isNotEmpty) {
            _completedLinkController.add(link.linkId!);
          }
          _slots[i] = null;
          changed = true;
        }
      }
    }
    if (changed) {
      _promoteToSlots();
      _persist();
      _emit();
    }
  }

  /// Add a URL to the pending queue.
  /// [linkId] is the ID of the link, used to call the like API after viewing.
  void enqueue(String url, {String? linkId}) {
    if (url.isEmpty || !url.startsWith('http')) {
      debugPrint('[LinkQueue] ⚠️ Skipping invalid URL: $url');
      return;
    }
    _pending.add(_PendingUrl(url: url, linkId: linkId, retryCount: 0));
    _promoteToSlots();
    _persist();
    _emit();
  }

  /// Called when a slot's page has fully loaded and its display time elapsed.
  void onSlotFinished(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= maxSlots) return;
    final link = _slots[slotIndex];
    debugPrint('[LinkQueue] ✅ Slot $slotIndex done: ${link?.url}');

    // Emit the linkId so the like API can be called
    if (link?.linkId != null && link!.linkId!.isNotEmpty) {
      _completedLinkController.add(link.linkId!);
    }

    _slots[slotIndex] = null;
    _promoteToSlots();
    _persist();
    _emit();
  }

  /// Called when a slot's page failed to load.
  /// Re-enqueues with retry tracking, up to maxRetries.
  void onSlotError(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= maxSlots) return;
    final link = _slots[slotIndex];
    if (link == null) return;

    final retries = link.retryCount;
    final url = link.url;
    final linkId = link.linkId;
    _slots[slotIndex] = null;

    if (retries < maxRetries) {
      debugPrint(
        '[LinkQueue] ❌ Slot $slotIndex failed (retry ${retries + 1}/$maxRetries): $url',
      );
      _pending.insert(
        0,
        _PendingUrl(url: url, linkId: linkId, retryCount: retries + 1),
      );
    } else {
      debugPrint(
        '[LinkQueue] 🚫 Slot $slotIndex exhausted retries, dropping: $url',
      );
      // Even if viewing failed, still call the like API since user already liked
      if (linkId != null && linkId.isNotEmpty) {
        _completedLinkController.add(linkId);
      }
    }

    _promoteToSlots();
    _persist();
    _emit();
  }

  // ── Internal logic ──

  /// Fill empty slots with pending URLs.
  void _promoteToSlots() {
    for (int i = 0; i < maxSlots; i++) {
      if (_slots[i] == null && _pending.isNotEmpty) {
        final next = _pending.removeAt(0);
        _slots[i] = ActiveLink(
          url: next.url,
          linkId: next.linkId,
          displayedAt: DateTime.now(),
          retryCount: next.retryCount,
        );
        debugPrint('[LinkQueue] ▶ Slot $i loading: ${_slots[i]!.url}');
      }
    }
  }

  void _emit() {
    _controller.add(List.unmodifiable(_slots));
  }

  // ── Persistence ──

  void _persist() {
    final pendingJson = _pending
        .map(
          (p) => jsonEncode({
            'url': p.url,
            'linkId': p.linkId,
            'retryCount': p.retryCount,
          }),
        )
        .toList();
    _prefs.setStringList(_pendingKey, pendingJson);

    final activeJson = <String>[];
    for (int i = 0; i < maxSlots; i++) {
      if (_slots[i] != null) {
        activeJson.add(jsonEncode({'slot': i, ..._slots[i]!.toJson()}));
      }
    }
    _prefs.setStringList(_activeKey, activeJson);
  }

  void _loadFromCache() {
    _pending.clear();
    final pendingRaw = _prefs.getStringList(_pendingKey) ?? [];
    for (final raw in pendingRaw) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _pending.add(
          _PendingUrl(
            url: json['url'] as String,
            linkId: json['linkId'] as String?,
            retryCount: (json['retryCount'] as int?) ?? 0,
          ),
        );
      } catch (_) {
        _pending.add(_PendingUrl(url: raw, retryCount: 0));
      }
    }

    for (int i = 0; i < maxSlots; i++) {
      _slots[i] = null;
    }
    final activeJson = _prefs.getStringList(_activeKey) ?? [];
    for (final raw in activeJson) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final slot = json['slot'] as int;
        if (slot >= 0 && slot < maxSlots) {
          final link = ActiveLink.fromJson(json);
          // If the link is older than 60s (stale from a previous app session),
          // move it back to pending for a fresh retry instead of leaving it
          // stuck in a slot with no WebView attached.
          if (link.isExpired ||
              DateTime.now().difference(link.displayedAt).inSeconds > 60) {
            debugPrint(
              '[LinkQueue] \u267b\ufe0f Stale active link in slot $slot moved to pending: ${link.url}',
            );
            _pending.add(
              _PendingUrl(
                url: link.url,
                linkId: link.linkId,
                retryCount: link.retryCount,
              ),
            );
          } else {
            _slots[slot] = link;
          }
        }
      } catch (_) {}
    }
  }

  void dispose() {
    _controller.close();
    _completedLinkController.close();
    _sweeperTimer?.cancel();
  }
}

class _PendingUrl {
  final String url;
  final String? linkId;
  final int retryCount;
  _PendingUrl({required this.url, this.linkId, required this.retryCount});
}
