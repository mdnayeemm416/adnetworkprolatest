import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';
import 'package:adnetwork/core/services/api_client.dart';
import 'package:adnetwork/config/api_endpoints.dart';
import 'package:adnetwork/layers/data/model/link_model.dart';
import 'package:adnetwork/core/services/pip_service.dart';

/// Represents an active link session being displayed in the full display WebView.
class ActiveViewSession {
  final String url;
  final String linkId;
  final int durationSeconds;
  final int pageIndex;
  final int linkIndex;
  final int totalLinks;
  final bool isAutoPlay;
  final DateTime startedAt;

  ActiveViewSession({
    required this.url,
    required this.linkId,
    required this.durationSeconds,
    this.pageIndex = 1,
    this.linkIndex = 1,
    this.totalLinks = 1,
    this.isAutoPlay = false,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

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

  /// Flag to prevent concurrent API fetch calls.
  bool _isFetchingLinks = false;

  /// Notifier for the currently active full-display WebView session.
  final ValueNotifier<ActiveViewSession?> activeSessionNotifier = ValueNotifier(null);

  /// Stream that emits a linkId whenever a link has been fully viewed
  /// in the WebView and should now have its like API called.
  final _completedLinkController = StreamController<String>.broadcast();
  Stream<String> get completedLinkStream => _completedLinkController.stream;

  /// Stream of session changes for reactive UI updates.
  final _sessionController = StreamController<ActiveViewSession?>.broadcast();
  Stream<ActiveViewSession?> get sessionStream => _sessionController.stream;

  /// Stream that notifies FeedScreen when AutoPlay should be paused.
  final _autoPlayPauseController = StreamController<void>.broadcast();
  Stream<void> get autoPlayPauseStream => _autoPlayPauseController.stream;

  /// Stream that notifies when all queued links have been consumed during autoplay
  /// AND the API returned no new links.
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
    activeSessionNotifier.value = null;
    debugPrint('[LinkQueue] ✅ Hive box "$_boxName" opened with ${_box!.length} queued items');
  }

  /// Populate the Hive queue with links from the API.
  /// Clears any existing queue and adds only unliked links.
  Future<void> populateQueue(List<dynamic> links) async {
    if (_box == null) return;
    await _box!.clear();

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

  /// Peek at the next queued link without removing it.
  QueuedLink? peekNext() {
    if (_box == null || _box!.isEmpty) return null;
    final raw = _box!.getAt(0);
    if (raw is Map) {
      return QueuedLink.fromMap(raw);
    }
    return null;
  }

  /// Remove and return the first queued link from Hive.
  QueuedLink? dequeueNext() {
    if (_box == null || _box!.isEmpty) return null;
    final raw = _box!.getAt(0);
    _box!.deleteAt(0);
    if (raw is Map) {
      final link = QueuedLink.fromMap(raw);
      debugPrint('[LinkQueue] 📤 Dequeued: ${link.linkId} ($queueLength remaining)');
      return link;
    }
    return null;
  }

  /// Remove a specific link from the queue by linkId (e.g., after manual like).
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
    if (keys.isNotEmpty) {
      debugPrint('[LinkQueue] 🗑️ Removed linkId=$linkId from queue ($queueLength remaining)');
    }
  }

  // ─────────────────── Auto-Fetch API ───────────────────

  /// Fetch fresh links from the API, populate Hive, and continue autoplay.
  /// Called when the Hive queue is empty during autoplay (especially PIP mode).
  /// The WebView stays open while fetching — no close/reopen flicker.
  Future<void> _fetchAndContinueAutoPlay(int pageIndex) async {
    if (_isFetchingLinks) return;
    _isFetchingLinks = true;

    debugPrint('[LinkQueue] 🔄 Hive queue empty — fetching fresh links from API...');

    try {
      final response = await ApiClient.instance.get<LinkModel>(
        ApiEndpoints.links,
        fromJsonModel: (json) => LinkModel.fromJson(json as Map<String, dynamic>),
      );

      if (response.isSuccess) {
        final links = response.dataList ??
            (response.data != null ? [response.data!] : <LinkModel>[]);

        // Notify FeedBloc to update its state with fresh links
        if (links.isNotEmpty) {
          _feedRefreshController.add(links);
        }

        // Clear and populate Hive with fresh unliked links
        await populateQueue(links);

        // Now continue autoplay with the new queue
        if (hasQueuedLinks) {
          final next = peekNext();
          if (next != null) {
            final duration = randomViewDurationSeconds;
            final newSession = ActiveViewSession(
              url: next.url,
              linkId: next.linkId,
              durationSeconds: duration,
              pageIndex: pageIndex + 1,
              linkIndex: 1,
              totalLinks: queueLength,
              isAutoPlay: true,
            );
            debugPrint('[LinkQueue] ▶ Continuing autoplay with fresh links: ${next.url} (${duration}s) [$queueLength total]');
            activeSessionNotifier.value = newSession;
            _sessionController.add(newSession);
            _isFetchingLinks = false;
            return;
          }
        }

        // API returned no unliked links — truly done
        debugPrint('[LinkQueue] ⚠️ API returned no new unliked links. Closing WebView.');
      } else {
        debugPrint('[LinkQueue] ❌ API fetch failed: ${response.message}');
      }
    } catch (e) {
      debugPrint('[LinkQueue] ❌ API fetch error: $e');
    }

    _isFetchingLinks = false;

    // Failed to get new links — close WebView and signal completion
    activeSessionNotifier.value = null;
    _sessionController.add(null);
    _allLinksCompletedController.add(null);
  }

  // ─────────────────── Session Management ───────────────────

  /// Start viewing a link in the full-display WebView.
  void startViewing({
    required String url,
    required String linkId,
    int pageIndex = 1,
    int linkIndex = 1,
    int totalLinks = 1,
    bool isAutoPlay = false,
    int? customDurationSeconds,
  }) {
    if (isFeedBreakActive) {
      debugPrint('[LinkQueue] 🛑 Cannot start viewing — feed break time is active');
      return;
    }

    if (url.isEmpty || !url.startsWith('http')) {
      debugPrint('[LinkQueue] ⚠️ Skipping invalid URL: $url');
      if (linkId.isNotEmpty) {
        removeFromQueue(linkId);
        _completedLinkController.add(linkId);
      }
      return;
    }

    final duration = customDurationSeconds ?? randomViewDurationSeconds;
    final session = ActiveViewSession(
      url: url,
      linkId: linkId,
      durationSeconds: duration,
      pageIndex: pageIndex,
      linkIndex: linkIndex,
      totalLinks: totalLinks,
      isAutoPlay: isAutoPlay,
    );

    activeSessionNotifier.value = session;
    _sessionController.add(session);
    debugPrint('[LinkQueue] ▶ Started full viewing: $url (${duration}s) [Link $linkIndex/$totalLinks]');
  }

  /// Legacy enqueue compatibility — opens the link in full display.
  void enqueue(String url, {String? linkId}) {
    if (url.isNotEmpty && linkId != null) {
      startViewing(url: url, linkId: linkId);
    }
  }

  /// Called when the active session completes viewing successfully.
  /// Removes the link from Hive, calls the completed stream (triggers like API),
  /// and in autoplay mode, directly swaps to the next queued link (no close/reopen).
  /// If the queue is empty, fetches fresh links from the API and continues.
  void onSessionFinished() {
    final session = activeSessionNotifier.value;
    if (session == null) return;

    debugPrint('[LinkQueue] ✅ Session finished: ${session.url} (${session.linkId})');
    final linkId = session.linkId;
    final wasAutoPlay = session.isAutoPlay;
    final pageIndex = session.pageIndex;

    // Remove from Hive queue
    removeFromQueue(linkId);

    // Trigger the like API
    if (linkId.isNotEmpty) {
      _completedLinkController.add(linkId);
    }

    // In autoplay mode, directly swap to next queued link (WebView stays open) if not in break time
    if (wasAutoPlay && hasQueuedLinks && !isFeedBreakActive) {
      final next = peekNext();
      if (next != null) {
        final duration = randomViewDurationSeconds;
        final newSession = ActiveViewSession(
          url: next.url,
          linkId: next.linkId,
          durationSeconds: duration,
          pageIndex: pageIndex,
          linkIndex: 1,
          totalLinks: queueLength,
          isAutoPlay: true,
        );
        debugPrint('[LinkQueue] ▶ Swapping to next: ${next.url} (${duration}s) [$queueLength remaining]');
        activeSessionNotifier.value = newSession;
        _sessionController.add(newSession);
        return;
      }
    }

    // Queue empty during autoplay — fetch fresh links from API and continue if not in break time
    if (wasAutoPlay && !isFeedBreakActive) {
      _fetchAndContinueAutoPlay(pageIndex);
      return;
    }

    // Not autoplay or break time active — close WebView
    activeSessionNotifier.value = null;
    _sessionController.add(null);
    if (isFeedBreakActive && wasAutoPlay) {
      requestPauseAutoPlay();
    }
  }

  /// Called when the session encountered an error or timed out.
  /// Same direct-swap behavior as onSessionFinished for seamless autoplay.
  void onSessionError() {
    final session = activeSessionNotifier.value;
    if (session == null) return;

    debugPrint('[LinkQueue] ❌ Session error/timeout: ${session.url}');
    final linkId = session.linkId;
    final wasAutoPlay = session.isAutoPlay;
    final pageIndex = session.pageIndex;

    // Remove from Hive queue and complete the link so user doesn't get stuck
    removeFromQueue(linkId);

    if (linkId.isNotEmpty) {
      _completedLinkController.add(linkId);
    }

    // In autoplay mode, directly swap to next queued link (WebView stays open) if not in break time
    if (wasAutoPlay && hasQueuedLinks && !isFeedBreakActive) {
      final next = peekNext();
      if (next != null) {
        final duration = randomViewDurationSeconds;
        final newSession = ActiveViewSession(
          url: next.url,
          linkId: next.linkId,
          durationSeconds: duration,
          pageIndex: pageIndex,
          linkIndex: 1,
          totalLinks: queueLength,
          isAutoPlay: true,
        );
        debugPrint('[LinkQueue] ▶ Swapping to next (after error): ${next.url} (${duration}s)');
        activeSessionNotifier.value = newSession;
        _sessionController.add(newSession);
        return;
      }
    }

    // Queue empty during autoplay — fetch fresh links from API and continue if not in break time
    if (wasAutoPlay && !isFeedBreakActive) {
      _fetchAndContinueAutoPlay(pageIndex);
      return;
    }

    // Not autoplay or break time active — close WebView
    activeSessionNotifier.value = null;
    _sessionController.add(null);
    if (isFeedBreakActive && wasAutoPlay) {
      requestPauseAutoPlay();
    }
  }

  void requestPauseAutoPlay() {
    _autoPlayPauseController.add(null);
  }

  /// Dismisses/cancels the current viewing session without calling like API (e.g. user closed manually).
  /// The link is NOT removed from Hive so it can be resumed later.
  void cancelViewing({bool completeLike = false}) {
    final session = activeSessionNotifier.value;
    if (session == null) return;

    debugPrint('[LinkQueue] 🚫 Session cancelled: ${session.url}');
    final linkId = session.linkId;
    final wasAutoPlay = session.isAutoPlay;

    activeSessionNotifier.value = null;
    _sessionController.add(null);

    if (wasAutoPlay) {
      requestPauseAutoPlay();
    }

    if (completeLike && linkId.isNotEmpty) {
      removeFromQueue(linkId);
      _completedLinkController.add(linkId);
    }
    // Note: When cancelled without completeLike, the link stays in Hive
    // so autoplay can resume from it later.
  }

  void dispose() {
    _completedLinkController.close();
    _sessionController.close();
    _autoPlayPauseController.close();
    _allLinksCompletedController.close();
    _feedRefreshController.close();
    activeSessionNotifier.dispose();
    _box?.close();
  }
}
