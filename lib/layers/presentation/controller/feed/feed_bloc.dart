import 'dart:async';

import 'package:adnetwork/core/services/link_queue_manager.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';
import 'package:adnetwork/layers/data/model/link_model.dart';
import 'package:adnetwork/layers/data/repo/remote/link_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'feed_event.dart';
part 'feed_state.dart';

class FeedBloc extends Bloc<FeedEvent, FeedState> {
  final LinkRepository linkRepository;

  Timer? _likeCooldownTimer;
  Timer? _pageWaitTimer;
  Timer? _nextCooldownTimer;
  Timer? _feedBreakCooldownTimer;
  StreamSubscription<String>? _queueCompletionSub;
  StreamSubscription<void>? _allLinksCompletedSub;
  StreamSubscription<List<LinkModel>>? _feedRefreshSub;
  int _pendingPage = 1;
  bool _isRefresh = false;

  FeedBloc({required this.linkRepository}) : super(const FeedState()) {
    on<LoadFeed>(_onLoadFeed);
    on<ToggleLike>(_onToggleLike);
    on<RefreshFeed>(_onRefreshFeed);
    on<LoadMoreFeed>(_onLoadMore);
    on<ChangeFeedPage>(_onChangePage);
    on<CheckFeedCooldowns>(_onCheckFeedCooldowns);
    on<_TickLikeCooldown>(_onTickLikeCooldown);
    on<_TickPageWait>(_onTickPageWait);
    on<_TickNextCooldown>(_onTickNextCooldown);
    on<_TickFeedBreakCooldown>(_onTickFeedBreakCooldown);
    on<_UpdateLinksFromQueue>(_onUpdateLinksFromQueue);

    // Immediately sync cooldowns upon bloc creation
    add(const CheckFeedCooldowns());

    // Listen for completed link viewings from the WebView queue
    // and fire the like API at that point.
    _queueCompletionSub = LinkQueueManager.instance.completedLinkStream.listen(
      _onLinkViewed,
    );

    // Listen for when all queued links have been consumed during autoplay
    // to automatically advance to the next page.
    _allLinksCompletedSub = LinkQueueManager.instance.allLinksCompletedStream.listen((_) {
      debugPrint('[FeedBloc] 🎉 All queued links done — auto-advancing to next page');
      add(ChangeFeedPage(state.currentPage + 1));
    });

    // Listen for fresh links fetched by LinkQueueManager during autoplay/PIP
    // and update BLoC state to keep UI in sync.
    _feedRefreshSub = LinkQueueManager.instance.feedRefreshStream.listen((links) {
      debugPrint('[FeedBloc] 🔄 Received ${links.length} fresh links from autoplay fetch');
      add(_UpdateLinksFromQueue(links));
    });
  }

  /// Synchronize cooldowns against persistent storage and current wall-clock time.
  Future<void> _syncCooldowns(Emitter<FeedState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Next button cooldown
    final nextBlockedUntil = prefs.getInt('feed_next_blocked_until') ?? 0;
    if (nextBlockedUntil > now) {
      final remaining = ((nextBlockedUntil - now) / 1000).ceil();
      emit(state.copyWith(nextCooldownSeconds: remaining));
      _startNextCooldown();
    } else {
      _nextCooldownTimer?.cancel();
      if (nextBlockedUntil > 0) {
        await prefs.setInt('feed_next_blocked_until', 0);
      }
      if (state.nextCooldownSeconds != 0) {
        emit(state.copyWith(nextCooldownSeconds: 0));
      }
    }

    // 2. Feed break cooldown
    final breakBlockedUntil = prefs.getInt('feed_break_blocked_until') ?? 0;
    final savedLikes = prefs.getInt('feed_break_likes_count') ?? 0;

    if (breakBlockedUntil > now) {
      final remaining = ((breakBlockedUntil - now) / 1000).ceil();
      LinkQueueManager.instance.isFeedBreakActive = true;
      emit(state.copyWith(
        feedBreakCooldownSeconds: remaining,
        feedBreakLikesCount: savedLikes,
      ));
      _startFeedBreakCooldown();
    } else {
      _feedBreakCooldownTimer?.cancel();
      LinkQueueManager.instance.isFeedBreakActive = false;
      if (breakBlockedUntil > 0) {
        await prefs.setInt('feed_break_blocked_until', 0);
        await prefs.setInt('feed_break_likes_count', 0);
        emit(state.copyWith(
          feedBreakCooldownSeconds: 0,
          feedBreakLikesCount: 0,
        ));
      } else {
        emit(state.copyWith(
          feedBreakCooldownSeconds: 0,
          feedBreakLikesCount: savedLikes,
        ));
      }
    }
  }

  Future<void> _onCheckFeedCooldowns(
    CheckFeedCooldowns event,
    Emitter<FeedState> emit,
  ) async {
    await _syncCooldowns(emit);
  }

  /// Called when a link has been fully viewed in the WebView.
  /// Now mark it liked in the state and call the like API.
  void _onLinkViewed(String linkId) {
    add(ToggleLike(linkId));
    linkRepository
        .toggleLike(linkId)
        .then(
          (_) {
            debugPrint('[FeedBloc] 👍 Like API called after viewing: $linkId');
          },
          onError: (e) {
            debugPrint('[FeedBloc] ❌ Like API failed for $linkId: $e');
          },
        );
  }

  // ── Load Feed ──

  Future<void> _onLoadFeed(LoadFeed event, Emitter<FeedState> emit) async {
    // Check for existing cooldowns in cache
    await _syncCooldowns(emit);

    emit(state.copyWith(status: FeedStatus.loading));

    try {
      final response = await linkRepository.getGlobalFeed();

      if (response.isSuccess) {
        final links =
            response.dataList ??
            (response.data != null ? [response.data!] : <LinkModel>[]);

        // Populate Hive queue with unliked links from API
        await LinkQueueManager.instance.populateQueue(links);

        emit(
          state.copyWith(
            status: FeedStatus.loaded,
            links: links,
            currentPage: 1,
            hasMore: links.length >= 10,
            isLocked: response.isLocked ?? false,
            instruction: response.instruction,
            errorMessage: response.message ?? '',
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: FeedStatus.error,
            errorMessage: response.message ?? 'Failed to load feed',
            isLocked: response.isLocked ?? false,
            instruction: response.instruction,
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(status: FeedStatus.error, errorMessage: e.toString()),
      );
    }
  }

  // ── Toggle Like (with cooldown and feed break limit) ──

  Future<void> _onToggleLike(ToggleLike event, Emitter<FeedState> emit) async {
    final links = List<LinkModel>.from(state.links);
    final idx = links.indexWhere((l) => l.id == event.linkId);
    if (idx == -1) return;

    final link = links[idx];
    if (link.isLiked) return; // Prevent double-liking

    links[idx] = link.copyWith(isLiked: true, likesCount: link.likesCount + 1);

    // Calculate cooldown: every 4th like → 4s, otherwise → 1s
    final newStreak = state.likeStreak + 1;
    final int cooldown = (newStreak % 4 == 0) ? 4 : 1;

    // Check feed break limits from mobile config
    final config = MobileConfigManager.instance.config;
    final breakLimit = config.breakTimeLinkCountInt;
    final newBreakLikes = state.feedBreakLikesCount + 1;
    final prefs = await SharedPreferences.getInstance();

    if (newBreakLikes >= breakLimit) {
      // User reached break_time_link_count likes! Trigger break time.
      final breakMinutes = config.feedBreakTimeMinutes;
      final breakSecs = breakMinutes * 60;
      final blockedUntil =
          DateTime.now().millisecondsSinceEpoch + (breakSecs * 1000);

      await prefs.setInt('feed_break_blocked_until', blockedUntil);
      await prefs.setInt('feed_break_likes_count', newBreakLikes);

      LinkQueueManager.instance.isFeedBreakActive = true;
      LinkQueueManager.instance.requestPauseAutoPlay();
      LinkQueueManager.instance.cancelViewing(completeLike: false);

      emit(
        state.copyWith(
          links: links,
          likeStreak: newStreak,
          likeCooldownSeconds: cooldown,
          feedBreakLikesCount: newBreakLikes,
          feedBreakCooldownSeconds: breakSecs,
        ),
      );

      _startFeedBreakCooldown();
    } else {
      await prefs.setInt('feed_break_likes_count', newBreakLikes);
      emit(
        state.copyWith(
          links: links,
          likeStreak: newStreak,
          likeCooldownSeconds: cooldown,
          feedBreakLikesCount: newBreakLikes,
        ),
      );

      // Start the cooldown countdown timer
      _startLikeCooldown();
    }
  }

  // ── Like Cooldown Timer ──

  void _startLikeCooldown() {
    _likeCooldownTimer?.cancel();
    _likeCooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const _TickLikeCooldown()),
    );
  }

  void _onTickLikeCooldown(_TickLikeCooldown event, Emitter<FeedState> emit) {
    final remaining = state.likeCooldownSeconds - 1;
    if (remaining <= 0) {
      _likeCooldownTimer?.cancel();
      emit(state.copyWith(likeCooldownSeconds: 0));
    } else {
      emit(state.copyWith(likeCooldownSeconds: remaining));
    }
  }

  // ── Refresh Feed (with 4s wait) ──

  Future<void> _onRefreshFeed(
    RefreshFeed event,
    Emitter<FeedState> emit,
  ) async {
    await _syncCooldowns(emit);
    _isRefresh = true;
    _pendingPage = state.currentPage;
    emit(state.copyWith(pageWaitSeconds: 4));
    _startPageWait();
  }

  // ── Change Page (with 4s wait) ──

  Future<void> _onChangePage(
    ChangeFeedPage event,
    Emitter<FeedState> emit,
  ) async {
    // 1. Check if we are currently in cooldown
    if (state.nextCooldownSeconds > 0) return;

    // 2. Increment click count
    final newClicks = state.nextButtonClicks + 1;

    if (newClicks >= 30) {
      // START COOLDOWN
      final cooldownSecs = 300; // 5 minutes
      final blockedUntil =
          DateTime.now().millisecondsSinceEpoch + (cooldownSecs * 1000);

      // Save to cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('feed_next_blocked_until', blockedUntil);

      emit(
        state.copyWith(nextButtonClicks: 0, nextCooldownSeconds: cooldownSecs),
      );
      _startNextCooldown();
      return;
    }

    _isRefresh = false;
    _pendingPage = event.page;
    emit(state.copyWith(pageWaitSeconds: 4, nextButtonClicks: newClicks));
    _startPageWait();
  }

  // ── Next Button Cooldown Timer ──

  void _startNextCooldown() {
    _nextCooldownTimer?.cancel();
    _nextCooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const _TickNextCooldown()),
    );
  }

  Future<void> _onTickNextCooldown(_TickNextCooldown event, Emitter<FeedState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    final nextBlockedUntil = prefs.getInt('feed_next_blocked_until') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (nextBlockedUntil <= now) {
      _nextCooldownTimer?.cancel();
      if (nextBlockedUntil > 0) {
        await prefs.setInt('feed_next_blocked_until', 0);
      }
      emit(state.copyWith(nextCooldownSeconds: 0));
    } else {
      final remaining = ((nextBlockedUntil - now) / 1000).ceil();
      emit(state.copyWith(nextCooldownSeconds: remaining));
    }
  }

  // ── Feed Break Cooldown Timer ──

  void _startFeedBreakCooldown() {
    _feedBreakCooldownTimer?.cancel();
    _feedBreakCooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const _TickFeedBreakCooldown()),
    );
  }

  Future<void> _onTickFeedBreakCooldown(
    _TickFeedBreakCooldown event,
    Emitter<FeedState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final breakBlockedUntil = prefs.getInt('feed_break_blocked_until') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (breakBlockedUntil <= now) {
      _feedBreakCooldownTimer?.cancel();
      LinkQueueManager.instance.isFeedBreakActive = false;

      // Break ended — reset like value in cache and state
      await prefs.setInt('feed_break_blocked_until', 0);
      await prefs.setInt('feed_break_likes_count', 0);

      emit(
        state.copyWith(
          feedBreakCooldownSeconds: 0,
          feedBreakLikesCount: 0,
        ),
      );
    } else {
      final remaining = ((breakBlockedUntil - now) / 1000).ceil();
      emit(state.copyWith(feedBreakCooldownSeconds: remaining));
    }
  }

  // ── Page Wait Timer ──

  void _startPageWait() {
    _pageWaitTimer?.cancel();
    _pageWaitTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const _TickPageWait()),
    );
  }

  Future<void> _onTickPageWait(
    _TickPageWait event,
    Emitter<FeedState> emit,
  ) async {
    final remaining = state.pageWaitSeconds - 1;
    if (remaining <= 0) {
      _pageWaitTimer?.cancel();
      emit(state.copyWith(pageWaitSeconds: 0));
      // Now actually fetch the page
      await _fetchPage(_pendingPage, emit, isRefresh: _isRefresh);
    } else {
      emit(state.copyWith(pageWaitSeconds: remaining));
    }
  }

  // ── Shared page fetch logic ──

  Future<void> _fetchPage(
    int page,
    Emitter<FeedState> emit, {
    bool isRefresh = false,
  }) async {
    emit(state.copyWith(status: FeedStatus.loading));

    try {
      final response = await linkRepository.getGlobalFeed();

      if (response.isSuccess) {
        final links =
            response.dataList ??
            (response.data != null ? [response.data!] : <LinkModel>[]);

        // Populate Hive queue with unliked links from new page
        await LinkQueueManager.instance.populateQueue(links);

        emit(
          state.copyWith(
            status: FeedStatus.loaded,
            links: links,
            currentPage: isRefresh ? 1 : page,
            hasMore: links.length >= 10,
            isLocked: response.isLocked ?? false,
            instruction: response.instruction,
            errorMessage: response.message ?? '',
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: FeedStatus.error,
            errorMessage: response.message ?? 'Failed to load page',
            isLocked: response.isLocked ?? false,
            instruction: response.instruction,
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(status: FeedStatus.error, errorMessage: e.toString()),
      );
    }
  }

  // ── Load More (no wait needed) ──

  Future<void> _onLoadMore(LoadMoreFeed event, Emitter<FeedState> emit) async {
    if (!state.hasMore) return;

    final nextPage = state.currentPage + 1;

    try {
      final response = await linkRepository.getGlobalFeed();

      if (response.isSuccess) {
        final newLinks = response.dataList ?? <LinkModel>[];
        emit(
          state.copyWith(
            links: [...state.links, ...newLinks],
            currentPage: nextPage,
            hasMore: newLinks.length >= 10,
            isLocked: response.isLocked ?? false,
            instruction: response.instruction,
          ),
        );
      }
    } catch (_) {
      // Silently fail on load more
    }
  }

  /// Handle fresh links pushed from LinkQueueManager during autoplay/PIP.
  void _onUpdateLinksFromQueue(_UpdateLinksFromQueue event, Emitter<FeedState> emit) {
    emit(
      state.copyWith(
        status: FeedStatus.loaded,
        links: event.links,
        currentPage: state.currentPage + 1,
        hasMore: event.links.length >= 10,
      ),
    );
  }

  @override
  Future<void> close() {
    _likeCooldownTimer?.cancel();
    _pageWaitTimer?.cancel();
    _nextCooldownTimer?.cancel();
    _feedBreakCooldownTimer?.cancel();
    _queueCompletionSub?.cancel();
    _allLinksCompletedSub?.cancel();
    _feedRefreshSub?.cancel();
    return super.close();
  }
}
