part of 'feed_bloc.dart';

abstract class FeedEvent extends Equatable {
  const FeedEvent();
  @override
  List<Object?> get props => [];
}

class LoadFeed extends FeedEvent {
  const LoadFeed();
}

class ToggleLike extends FeedEvent {
  final String linkId;
  const ToggleLike(this.linkId);
  @override
  List<Object?> get props => [linkId];
}

class RefreshFeed extends FeedEvent {
  const RefreshFeed();
}

class LoadMoreFeed extends FeedEvent {
  const LoadMoreFeed();
}

class ChangeFeedPage extends FeedEvent {
  final int page;
  const ChangeFeedPage(this.page);
  @override
  List<Object?> get props => [page];
}

/// Internal: tick the like cooldown timer by 1 second.
class _TickLikeCooldown extends FeedEvent {
  const _TickLikeCooldown();
}

/// Internal: tick the next-button cooldown timer by 1 second.
class _TickNextCooldown extends FeedEvent {
  const _TickNextCooldown();
}

/// Internal: tick the page-wait countdown by 1 second.
class _TickPageWait extends FeedEvent {
  const _TickPageWait();
}
