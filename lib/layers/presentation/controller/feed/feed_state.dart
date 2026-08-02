part of 'feed_bloc.dart';

enum FeedStatus { initial, loading, loaded, error }

class FeedState extends Equatable {
  final FeedStatus status;
  final List<LinkModel> links;
  final int currentPage;
  final bool hasMore;
  final String errorMessage;

  /// Seconds remaining before the user can like again (0 = ready).
  final int likeCooldownSeconds;

  /// How many likes have been given in the current streak.
  final int likeStreak;

  /// Seconds remaining on the page-transition wait card (0 = no wait).
  final int pageWaitSeconds;

  /// How many times the NEXT button has been clicked in this "session"
  final int nextButtonClicks;

  /// Seconds remaining for the 5-minute cooldown (0 = no cooldown).
  final int nextCooldownSeconds;

  /// Feed locked by campaign requirement.
  final bool isLocked;

  /// Campaign instruction banner message.
  final String? instruction;

  const FeedState({
    this.status = FeedStatus.initial,
    this.links = const [],
    this.currentPage = 1,
    this.hasMore = true,
    this.errorMessage = '',
    this.likeCooldownSeconds = 0,
    this.likeStreak = 0,
    this.pageWaitSeconds = 0,
    this.nextButtonClicks = 0,
    this.nextCooldownSeconds = 0,
    this.isLocked = false,
    this.instruction,
  });

  FeedState copyWith({
    FeedStatus? status,
    List<LinkModel>? links,
    int? currentPage,
    bool? hasMore,
    String? errorMessage,
    int? likeCooldownSeconds,
    int? likeStreak,
    int? pageWaitSeconds,
    int? nextButtonClicks,
    int? nextCooldownSeconds,
    bool? isLocked,
    String? instruction,
  }) {
    return FeedState(
      status: status ?? this.status,
      links: links ?? this.links,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
      likeCooldownSeconds: likeCooldownSeconds ?? this.likeCooldownSeconds,
      likeStreak: likeStreak ?? this.likeStreak,
      pageWaitSeconds: pageWaitSeconds ?? this.pageWaitSeconds,
      nextButtonClicks: nextButtonClicks ?? this.nextButtonClicks,
      nextCooldownSeconds: nextCooldownSeconds ?? this.nextCooldownSeconds,
      isLocked: isLocked ?? this.isLocked,
      instruction: instruction ?? this.instruction,
    );
  }

  @override
  List<Object?> get props => [
    status,
    links,
    currentPage,
    hasMore,
    errorMessage,
    likeCooldownSeconds,
    likeStreak,
    pageWaitSeconds,
    nextButtonClicks,
    nextCooldownSeconds,
    isLocked,
    instruction,
  ];
}
