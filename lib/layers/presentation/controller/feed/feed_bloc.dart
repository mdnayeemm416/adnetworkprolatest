import 'dart:async';

import 'package:adnetwork/core/services/link_queue_manager.dart';
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
  StreamSubscription<String>? _queueCompletionSub;
  int _pendingPage = 1;
  bool _isRefresh = false;

  FeedBloc({required this.linkRepository}) : super(const FeedState()) {
    on<LoadFeed>(_onLoadFeed);
    on<ToggleLike>(_onToggleLike);
    on<RefreshFeed>(_onRefreshFeed);
    on<LoadMoreFeed>(_onLoadMore);
    on<ChangeFeedPage>(_onChangePage);
    on<_TickLikeCooldown>(_onTickLikeCooldown);
    on<_TickPageWait>(_onTickPageWait);
    on<_TickNextCooldown>(_onTickNextCooldown);

    // Listen for completed link viewings from the WebView queue
    // and fire the like API at that point.
    _queueCompletionSub = LinkQueueManager.instance.completedLinkStream.listen(
      _onLinkViewed,
    );
  }

  /// Called when a link has been fully viewed in the WebView.
  /// Now it's safe to call the like API.
  void _onLinkViewed(String linkId) {
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
    // Check for existing cooldown in cache on first load
    if (state.status == FeedStatus.initial) {
      final prefs = await SharedPreferences.getInstance();
      final blockedUntil = prefs.getInt('feed_next_blocked_until') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (blockedUntil > now) {
        final remaining = ((blockedUntil - now) / 1000).ceil();
        emit(state.copyWith(nextCooldownSeconds: remaining));
        _startNextCooldown();
      }
    }

    emit(state.copyWith(status: FeedStatus.loading));

    try {
      final response = await linkRepository.getGlobalFeed();

      if (response.isSuccess) {
        final links =
            response.dataList ??
            (response.data != null ? [response.data!] : <LinkModel>[]);
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

  // ── Toggle Like (with cooldown) ──

  Future<void> _onToggleLike(ToggleLike event, Emitter<FeedState> emit) async {
    // Block if cooldown is active
    if (state.likeCooldownSeconds > 0) return;

    // Optimistic update — apply immediately, no waiting for API
    final links = List<LinkModel>.from(state.links);
    final idx = links.indexWhere((l) => l.id == event.linkId);
    if (idx == -1) return;

    final link = links[idx];
    if (link.isLiked) return; // Prevent unliking once liked

    links[idx] = link.copyWith(isLiked: true, likesCount: link.likesCount + 1);

    // Calculate cooldown: every 4th like → 4s, otherwise → 1s
    final newStreak = state.likeStreak + 1;
    final int cooldown = (newStreak % 4 == 0) ? 4 : 1;

    emit(
      state.copyWith(
        links: links,
        likeStreak: newStreak,
        likeCooldownSeconds: cooldown,
      ),
    );

    // Start the cooldown countdown timer
    _startLikeCooldown();

    // DO NOT call the like API here.
    // Instead, enqueue the link for background WebView viewing.
    // The like API will be called automatically when the WebView
    // finishes viewing this link (via completedLinkStream).
    if (link.url != null) {
      LinkQueueManager.instance.enqueue(link.url!, linkId: event.linkId);
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

  void _onTickNextCooldown(_TickNextCooldown event, Emitter<FeedState> emit) {
    final remaining = state.nextCooldownSeconds - 1;
    if (remaining <= 0) {
      _nextCooldownTimer?.cancel();
      emit(state.copyWith(nextCooldownSeconds: 0));
    } else {
      emit(state.copyWith(nextCooldownSeconds: remaining));
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

  @override
  Future<void> close() {
    _likeCooldownTimer?.cancel();
    _pageWaitTimer?.cancel();
    _nextCooldownTimer?.cancel();
    _queueCompletionSub?.cancel();
    return super.close();
  }
}
