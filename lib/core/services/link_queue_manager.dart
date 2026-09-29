import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';
import 'package:adnetwork/layers/data/model/link_model.dart';
import 'package:adnetwork/core/services/pip_service.dart';

/// Represents an active link session being displayed in the full display WebView.
class ActiveViewSession {
  final String sessionId;
  final String url;
  final String linkId;
  final int durationSeconds;
  final int pageIndex;
  final int linkIndex;
  final int totalLinks;
  final bool isAutoPlay;
  final DateTime startedAt;

  ActiveViewSession({
    String? sessionId,
    required this.url,
    required this.linkId,
    required this.durationSeconds,
    this.pageIndex = 1,
    this.linkIndex = 1,
    this.totalLinks = 1,
    this.isAutoPlay = false,
    DateTime? startedAt,
  })  : sessionId = sessionId ?? '${DateTime.now().microsecondsSinceEpoch}_$linkId',
        startedAt = startedAt ?? DateTime.now();

  int get elapsedSeconds => DateTime.now().difference(startedAt).inSeconds;
  int get remainingSeconds => (durationSeconds - elapsedSeconds).clamp(0, durationSeconds);
  bool get isExpired => remainingSeconds <= 0;
}

/// A queued link entry stored in Hive for persistent autoplay.
class QueuedLink {
  final String linkId;
  final String url;

  QueuedLink({required this.linkId, required this.url});

  Map<String, dynamic> toMap() => {'linkId': linkId, 'url': url};

  factory QueuedLink.fromMap(Map<dynamic, dynamic> map) {
    return QueuedLink(
      linkId: map['linkId']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
    );
  }
}

/// Manages active full-display WebView viewing sessions for single likes and autoplay.
/// Uses a Hive box (`link_queue`) for persistent queue storage so that:
/// - When the feed API loads, all unliked links are saved to Hive.
/// - Manual likes remove the entry from Hive after the viewing timer completes.
/// - AutoPlay pulls URLs from Hive sequentially; when the timer ends, the entry
///   is deleted and the next URL is loaded. When all entries are consumed,
///   the link API is called again to fetch fresh links and continue autoplay.
/// - If the user closes the WebView, autoplay stops but remaining Hive entries
///   are preserved for resumption.
/// Global notifier indicating whether the app is currently displaying in Picture-in-Picture mode.
ValueNotifier<bool> get isPipModeNotifier => PipService.instance.isPipMode;

class LinkQueueManager {
  static final LinkQueueManager instance = LinkQueueManager._();
  LinkQueueManager._();

  final _random = Random();

  static const String _boxName = 'link_queue';
  Box? _box;

  /// Set of link IDs currently in-flight across Slot 1 and Slot 2.
  final Set<String> _inProgressLinkIds = <String>{};

  /// Notifiers for the two concurrent WebView slots.
  final ValueNotifier<ActiveViewSession?> slot1SessionNotifier = ValueNotifier(null);
  final ValueNotifier<ActiveViewSession?> slot2SessionNotifier = ValueNotifier(null);

  /// Global active session notifier (active if either slot is viewing).
  final ValueNotifier<ActiveViewSession?> activeSessionNotifier = ValueNotifier(null);

  /// Stream that emits a linkId whenever a link has been fully viewed
  /// in either WebView slot and should now have its like API called.
  final _completedLinkController = StreamController<String>.broadcast();
  Stream<String> get completedLinkStream => _completedLinkController.stream;

  /// Stream of session changes for reactive UI updates.
  final _sessionController = StreamController<ActiveViewSession?>.broadcast();
  Stream<ActiveViewSession?> get sessionStream => _sessionController.stream;

  /// Stream that notifies FeedScreen when AutoPlay should be paused.
  final _autoPlayPauseController = StreamController<void>.broadcast();
  Stream<void> get autoPlayPauseStream => _autoPlayPauseController.stream;

  /// Stream that notifies when all queued links have been consumed during autoplay.
  final _allLinksCompletedController = StreamController<void>.broadcast();
  Stream<void> get allLinksCompletedStream => _allLinksCompletedController.stream;

  /// Stream that notifies FeedBloc to refresh its state with fresh links
  /// fetched during autoplay/PIP mode.
  final _feedRefreshController = StreamController<List<LinkModel>>.broadcast();
  Stream<List<LinkModel>> get feedRefreshStream => _feedRefreshController.stream;

  ActiveViewSession? get currentSession => activeSessionNotifier.value;
  bool get isViewing => activeSessionNotifier.value != null;

  /// Whether a feed break time is currently active.
  bool isFeedBreakActive = false;

  /// Generate a random delay for page viewing based on the mobile config.
  int get randomViewDurationSeconds {
    final minS = int.tryParse(MobileConfigManager.instance.config.minAdsTime) ?? 10;
    final maxS = int.tryParse(MobileConfigManager.instance.config.maxAdsTime) ?? 15;
    if (maxS <= minS) return minS;
    final range = maxS - minS + 1;
    return minS + _random.nextInt(range);
  }

  // ─────────────────── Hive Queue API ───────────────────

  /// Initialize queue manager on app start. Opens the Hive box.
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _inProgressLinkIds.clear();
    slot1SessionNotifier.value = null;
    slot2SessionNotifier.value = null;
    activeSessionNotifier.value = null;
    debugPrint('[LinkQueue] ✅ Hive box "$_boxName" opened with ${_box!.length} queued items');
  }

  /// Populate the Hive queue with links from the API.
  /// Clears any existing queue and adds only unliked links.
  Future<void> populateQueue(List<dynamic> links) async {
    if (_box == null) return;
    await _box!.clear();
    _inProgressLinkIds.clear();

    int addedCount = 0;
    for (final link in links) {
      final String? id = link.id?.toString();
      final String? url = link.url?.toString();
      final bool isLiked = link.isLiked ?? false;

      if (id != null && id.isNotEmpty && url != null && url.isNotEmpty && !isLiked) {
        await _box!.add({'linkId': id, 'url': url});
        addedCount++;
      }
    }

    debugPrint('[LinkQueue] 📦 Queue populated with $addedCount unliked links (cleared ${links.length - addedCount} liked/invalid)');
  }

  /// Returns the number of remaining links in the Hive queue.
  int get queueLength => _box?.length ?? 0;

  /// Whether there are any links remaining in the Hive queue.
  bool get hasQueuedLinks => queueLength > 0;

  /// Get list of links in Hive queue not currently in progress in Slot 1 or Slot 2.
  List<QueuedLink> get _unassignedLinks {
    if (_box == null) return [];
    final list = <QueuedLink>[];
    for (int i = 0; i < _box!.length; i++) {
      final raw = _box!.getAt(i);
      if (raw is Map) {
        final link = QueuedLink.fromMap(raw);
        if (!_inProgressLinkIds.contains(link.linkId)) {
          list.add(link);
        }
      }
    }
    return list;
  }

  /// Remove a specific link from the queue by linkId.
  Future<void> removeFromQueue(String linkId) async {
    if (_box == null) return;
    final keys = <dynamic>[];
    for (int i = 0; i < _box!.length; i++) {
      final raw = _box!.getAt(i);
      if (raw is Map && raw['linkId']?.toString() == linkId) {
        keys.add(_box!.keyAt(i));
      }
    }
    for (final key in keys) {
      await _box!.delete(key);
    }
    _inProgressLinkIds.remove(linkId);
    if (keys.isNotEmpty) {
      debugPrint('[LinkQueue] 🗑️ Removed linkId=$linkId from queue ($queueLength remaining)');
    }
  }

  /// Enqueue a single link and trigger concurrent dual slot dispatch.
  Future<void> enqueueLink({
    required String url,
    required String linkId,
    bool isAutoPlay = false,
  }) async {
    if (url.isEmpty || !url.startsWith('http')) {
      debugPrint('[LinkQueue] ⚠️ Skipping invalid URL enqueue: $url');
      return;
    }

    if (_box != null) {
      bool alreadyExists = false;
      for (int i = 0; i < _box!.length; i++) {
        final raw = _box!.getAt(i);
        if (raw is Map && raw['linkId']?.toString() == linkId) {
          alreadyExists = true;
          break;
        }
      }

      if (!alreadyExists) {
        await _box!.add({'linkId': linkId, 'url': url});
        debugPrint('[LinkQueue] 📥 Enqueued link: $linkId ($queueLength in queue)');
      }
    }

    _dispatchQueue(isAutoPlay: isAutoPlay);
  }

  /// Dispatches queued URLs to Slot 1 and Slot 2 concurrently.
  /// If 1 URL is available, 1 slot is used.
  /// If multiple URLs are available, 2 slots run concurrently to complete 2 at a time!
  void _dispatchQueue({bool isAutoPlay = true}) {
    if (isFeedBreakActive) {
      debugPrint('[LinkQueue] 🛑 Cannot dispatch queue — feed break time is active');
      return;
    }

    final unassigned = _unassignedLinks;

    // ── Check Slot 1 ──
    if (slot1SessionNotifier.value == null && unassigned.isNotEmpty) {
      final next1 = unassigned.removeAt(0);
      _inProgressLinkIds.add(next1.linkId);
      final duration = randomViewDurationSeconds;
      final session1 = ActiveViewSession(
        url: next1.url,
        linkId: next1.linkId,
        durationSeconds: duration,
        isAutoPlay: isAutoPlay,
      );
      debugPrint('[LinkQueue] ▶ Slot 1 assigned: ${next1.url} (${duration}s) [$queueLength in queue]');
      slot1SessionNotifier.value = session1;
    }

    // ── Check Slot 2 ──
    if (slot2SessionNotifier.value == null && unassigned.isNotEmpty) {
      final next2 = unassigned.removeAt(0);
      _inProgressLinkIds.add(next2.linkId);
      final duration = randomViewDurationSeconds;
      final session2 = ActiveViewSession(
        url: next2.url,
        linkId: next2.linkId,
        durationSeconds: duration,
        isAutoPlay: isAutoPlay,
      );
      debugPrint('[LinkQueue] ▶ Slot 2 assigned: ${next2.url} (${duration}s) [$queueLength in queue]');
      slot2SessionNotifier.value = session2;
    }

    // Sync global activeSessionNotifier
    activeSessionNotifier.value =
        slot1SessionNotifier.value ?? slot2SessionNotifier.value;
    _sessionController.add(activeSessionNotifier.value);

    // If both slots idle and no unassigned items
    if (slot1SessionNotifier.value == null &&
        slot2SessionNotifier.value == null &&
        !hasQueuedLinks) {
      debugPrint('[LinkQueue] 🏁 All queue items completed in dual slots');
      _allLinksCompletedController.add(null);
    }
  }

  // ─────────────────── Slot Completion & Error Handlers ───────────────────

  /// Called when Slot 1 or Slot 2 finishes viewing its link.
  Future<void> onSlotFinished(int slotIndex, String linkId) async {
    debugPrint('[LinkQueue] ✅ Slot $slotIndex finished link: $linkId');
    _inProgressLinkIds.remove(linkId);
    await removeFromQueue(linkId);

    if (slotIndex == 1) {
      slot1SessionNotifier.value = null;
    } else {
      slot2SessionNotifier.value = null;
    }

    if (linkId.isNotEmpty) {
      _completedLinkController.add(linkId);
    }

    if (isFeedBreakActive) {
      cancelViewing();
      return;
    }

    // Immediately pick and play next available URL from queue for this slot!
    _dispatchQueue();
  }

  /// Called when Slot 1 or Slot 2 encounters an error or timeout.
  Future<void> onSlotError(int slotIndex, String linkId) async {
    debugPrint('[LinkQueue] ❌ Slot $slotIndex error on link: $linkId');
    _inProgressLinkIds.remove(linkId);
    await removeFromQueue(linkId);

    if (slotIndex == 1) {
      slot1SessionNotifier.value = null;
    } else {
      slot2SessionNotifier.value = null;
    }

    if (linkId.isNotEmpty) {
      _completedLinkController.add(linkId);
    }

    if (isFeedBreakActive) {
      cancelViewing();
      return;
    }

    // Immediately pick next available URL
    _dispatchQueue();
  }

  /// Legacy compatibility methods
  Future<void> onSessionFinished() async {
    if (slot1SessionNotifier.value != null) {
      await onSlotFinished(1, slot1SessionNotifier.value!.linkId);
    } else if (slot2SessionNotifier.value != null) {
      await onSlotFinished(2, slot2SessionNotifier.value!.linkId);
    }
  }

  Future<void> onSessionError() async {
    if (slot1SessionNotifier.value != null) {
      await onSlotError(1, slot1SessionNotifier.value!.linkId);
    } else if (slot2SessionNotifier.value != null) {
      await onSlotError(2, slot2SessionNotifier.value!.linkId);
    }
  }

  void startViewing({
    required String url,
    required String linkId,
    int pageIndex = 1,
    int linkIndex = 1,
    int totalLinks = 1,
    bool isAutoPlay = false,
    int? customDurationSeconds,
  }) {
    enqueueLink(url: url, linkId: linkId, isAutoPlay: isAutoPlay);
  }

  void enqueue(String url, {String? linkId}) {
    if (url.isNotEmpty && linkId != null) {
      enqueueLink(url: url, linkId: linkId);
    }
  }

  void requestPauseAutoPlay() {
    _autoPlayPauseController.add(null);
  }

  /// Dismisses/cancels all active slot viewing sessions.
  void cancelViewing({bool completeLike = false}) {
    debugPrint('[LinkQueue] 🚫 Cancelling active slot viewing sessions');
    _inProgressLinkIds.clear();
    slot1SessionNotifier.value = null;
    slot2SessionNotifier.value = null;
    activeSessionNotifier.value = null;
    _sessionController.add(null);

    requestPauseAutoPlay();
  }

  void dispose() {
    _completedLinkController.close();
    _sessionController.close();
    _autoPlayPauseController.close();
    _allLinksCompletedController.close();
    _feedRefreshController.close();
    slot1SessionNotifier.dispose();
    slot2SessionNotifier.dispose();
    activeSessionNotifier.dispose();
    _box?.close();
  }
}
