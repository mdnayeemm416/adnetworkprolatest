import 'package:adnetwork/config/asset_manager.dart';
import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/layers/presentation/controller/feed/feed_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/notice/notice_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/profile/profile_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/explore/explore_bloc.dart';
import 'package:adnetwork/layers/data/repo/remote/user_repository.dart';
import 'package:adnetwork/layers/presentation/widget/link_post_card.dart';
import 'package:adnetwork/layers/presentation/widget/suggested_user_card.dart';
import 'package:flutter/material.dart';
import 'package:adnetwork/main.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:adnetwork/layers/presentation/screen/home/home_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:adnetwork/core/services/token_storage.dart';
import 'package:flutter/services.dart';
import 'package:adnetwork/core/services/api_client.dart';
import 'package:adnetwork/layers/dto/api_response.dart';

import 'dart:async';
import 'dart:io' show Platform;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:pip/pip.dart';

final ValueNotifier<bool> isPipModeNotifier = ValueNotifier(false);
final ValueNotifier<double> webViewOverlayOpacityNotifier = ValueNotifier(0.0);

class FeedScreen extends StatefulWidget {
  final bool isActive;
  const FeedScreen({super.key, this.isActive = false});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with RouteAware {
  late ScrollController _scrollController;
  Timer? _botTimer;
  // ── Debounce timer for overlay opacity disk writes ──
  Timer? _opacityDebounceTimer;
  bool _isAutoScrolling = false;
  int _currentTargetIndex = 0;
  bool _isProcessingTarget = false;
  final _pip = Pip();
  bool _isAutoLikeEnabled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initPip();
    _loadAutoLikeStatus();
    _loadOverlayOpacity();
    // Keep screen awake while app is in foreground
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.isActive) {
          _checkAutoplayPersistentStatus();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    if (mounted) {
      context.read<FeedBloc>().add(const RefreshFeed());
      context.read<NoticeBloc>().add(const LoadNotices());
      context.read<ProfileBloc>().add(const LoadProfileStats());
      context.read<ExploreBloc>().add(const RefreshExplore());
    }
  }

  Future<void> _loadOverlayOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    final opacity = prefs.getDouble('webview_overlay_opacity') ?? 0.0;
    webViewOverlayOpacityNotifier.value = opacity;
  }

  /// Debounced — only writes to disk 300ms after the user stops dragging
  /// to avoid hammering SharedPreferences on every slider frame.
  void _saveOverlayOpacityDebounced(double opacity) {
    _opacityDebounceTimer?.cancel();
    _opacityDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('webview_overlay_opacity', opacity);
    });
  }

  Future<void> _loadAutoLikeStatus() async {
    final enabled = await TokenStorage.instance.isAutoLikeEnabled();
    debugPrint('feed_screen.dart: _loadAutoLikeStatus - enabled: $enabled');
    if (mounted) {
      setState(() {
        _isAutoLikeEnabled = enabled;
      });
    }
  }

  Future<void> _initPip() async {
    try {
      final isSupported = await _pip.isSupported();
      if (isSupported) {
        PipOptions options = PipOptions(autoEnterEnabled: false);
        if (Platform.isAndroid) {
          options = PipOptions(
            autoEnterEnabled: false,
            aspectRatioX: 9,
            aspectRatioY: 16,
          );
        } else if (Platform.isIOS) {
          options = PipOptions(
            autoEnterEnabled: false,
            preferredContentWidth: 300,
            preferredContentHeight: 533,
            controlStyle: 0,
          );
        }
        await _pip.setup(options);
        await _pip.registerStateChangedObserver(
          PipStateChangedObserver(
            onPipStateChanged: (state, error) {
              if (mounted) {
                isPipModeNotifier.value = state == PipState.pipStateStarted;
              }
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to init PIP: $e');
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _botTimer?.cancel();
    _opacityDebounceTimer?.cancel();
    _scrollController.dispose();
    _pip.dispose();
    super.dispose();
  }

  void _toggleAutoPlay(FeedState state) {
    setState(() {
      _isAutoScrolling = !_isAutoScrolling;
      TokenStorage.instance.saveFeedAutoplay(_isAutoScrolling ? 1 : 0);
      _isProcessingTarget = false;
      if (_isAutoScrolling) {
        _currentTargetIndex = 0;
        _scrollToIndex(0);
        _isProcessingTarget = true;
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && _isAutoScrolling) {
            setState(() {
              _isProcessingTarget = false;
            });
            _startBotTimer();
          }
        });
      } else {
        _botTimer?.cancel();
        _botTimer = null;
      }
    });
  }

  void _stopAutoplayTemporarily() {
    if (_isAutoScrolling) {
      setState(() {
        _isAutoScrolling = false;
        _isProcessingTarget = false;
        _botTimer?.cancel();
        _botTimer = null;
      });
    }
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _checkAutoplayPersistentStatus();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopAutoplayTemporarily();
    }
  }

  Future<void> _checkAutoplayPersistentStatus() async {
    final autoplayVal = await TokenStorage.instance.getFeedAutoplay();
    if (autoplayVal == 1) {
      if (mounted && !_isAutoScrolling) {
        final feedBloc = context.read<FeedBloc>();
        _toggleAutoPlay(feedBloc.state);
      }
    } else {
      if (mounted && _isAutoScrolling) {
        final feedBloc = context.read<FeedBloc>();
        _toggleAutoPlay(feedBloc.state);
      }
    }
  }

  void _startBotTimer() {
    _botTimer?.cancel();
    // Reduced from 600ms to 800ms — imperceptible difference but meaningfully
    // less CPU pressure during prolonged auto-like sessions.
    _botTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted || !_isAutoScrolling) {
        timer.cancel();
        return;
      }

      if (_isProcessingTarget) return;

      final feedBloc = context.read<FeedBloc>();
      final state = feedBloc.state;

      // Wait if loading or in page wait cooldown
      if (state.pageWaitSeconds > 0 ||
          state.nextCooldownSeconds > 0 ||
          state.status == FeedStatus.loading) {
        return;
      }

      if (state.links.isEmpty) return;

      // Boundary safety check
      if (_currentTargetIndex >= state.links.length) {
        _currentTargetIndex = 0;
      }

      final link = state.links[_currentTargetIndex];

      if (link.isLiked) {
        _currentTargetIndex++;
        if (_currentTargetIndex >= state.links.length) {
          _currentTargetIndex = 0;
          feedBloc.add(ChangeFeedPage(state.currentPage + 1));
        } else {
          _isProcessingTarget = true;
          _scrollToIndex(_currentTargetIndex);
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted) {
              setState(() {
                _isProcessingTarget = false;
              });
            }
          });
        }
      } else {
        // wait for the likeCooldownSeconds
        if (state.likeCooldownSeconds > 0) {
          return;
        }

        _isProcessingTarget = true;

        // Human-like delay before liking (1000ms)
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!mounted || !_isAutoScrolling) {
            _isProcessingTarget = false;
            return;
          }

          // do the action onLike
          feedBloc.add(ToggleLike(link.id ?? ''));

          // Human-like delay after liking before scrolling (1500ms)
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (!mounted || !_isAutoScrolling) {
              _isProcessingTarget = false;
              return;
            }

            if (context.mounted) {
              // when index end then call next page
              if (_currentTargetIndex == state.links.length - 1) {
                feedBloc.add(ChangeFeedPage(state.currentPage + 1));
                setState(() {
                  _currentTargetIndex = 0;
                  _isProcessingTarget = false;
                });
              } else {
                final int nextIndex = _currentTargetIndex + 1;
                _scrollToIndex(nextIndex);

                // Wait for scroll animation to complete, then update index
                Future.delayed(const Duration(milliseconds: 900), () {
                  if (!mounted || !_isAutoScrolling) {
                    _isProcessingTarget = false;
                    return;
                  }
                  setState(() {
                    _currentTargetIndex = nextIndex;
                    _isProcessingTarget = false;
                  });
                });
              }
            } else {
              _isProcessingTarget = false;
            }
          });
        });
      }
    });
  }

  void _scrollToIndex(int index) {
    if (_scrollController.hasClients) {
      final double targetOffset = 50.0 + (index * 280.0);
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ── Scoped BlocBuilder: only rebuild when the fields that actually
    //    control which top-level card is shown change, OR when the links
    //    list / loading status changes.  Countdown-only ticks (every 1s)
    //    will NOT reach child BlocBuilders that have their own buildWhen.
    return BlocBuilder<FeedBloc, FeedState>(
      buildWhen: (prev, curr) =>
          prev.status != curr.status ||
          prev.links != curr.links ||
          prev.isLocked != curr.isLocked ||
          // Show/hide like-button cooldown countdown on cards
          prev.likeCooldownSeconds != curr.likeCooldownSeconds ||
          // Switch between the three top-level views
          (prev.nextCooldownSeconds > 0) != (curr.nextCooldownSeconds > 0) ||
          (prev.pageWaitSeconds > 0) != (curr.pageWaitSeconds > 0),
      builder: (context, state) {
        Widget content;
        // ── Next Button Cooldown Card (5m countdown) ──
        if (state.nextCooldownSeconds > 0) {
          // Wrap in its own scoped BlocBuilder so only the time text
          // rebuilds every second — the feed list is untouched.
          content = BlocBuilder<FeedBloc, FeedState>(
            buildWhen: (p, c) => p.nextCooldownSeconds != c.nextCooldownSeconds,
            builder: (context, cdState) {
              final mins = cdState.nextCooldownSeconds ~/ 60;
              final secs = cdState.nextCooldownSeconds % 60;
              final timeStr =
                  '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
              return Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.timer_outlined,
                          color: cs.primary,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        timeStr,
                        style: getBoldStyle(fontSize: 40, color: cs.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '৫ মিনিট পর আবার চেষ্টা করুন',
                        style: getBoldStyle(fontSize: 18, color: cs.onSurface),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'নতুন বিজ্ঞাপন লোড হচ্ছে',
                        style: getMediumStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        } else if (state.pageWaitSeconds > 0) {
          // Wrap in its own scoped BlocBuilder so only the countdown
          // number rebuilds every second.
          content = BlocBuilder<FeedBloc, FeedState>(
            buildWhen: (p, c) => p.pageWaitSeconds != c.pageWaitSeconds,
            builder: (context, pwState) {
              return Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated countdown circle
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: CircularProgressIndicator(
                              value: pwState.pageWaitSeconds / 4.0,
                              strokeWidth: 6,
                              backgroundColor: cs.primary.withValues(alpha: 0.1),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(cs.primary),
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Text(
                            '${pwState.pageWaitSeconds}',
                            style:
                                getBoldStyle(fontSize: 32, color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'অপেক্ষা করুন...',
                        style:
                            getBoldStyle(fontSize: 20, color: cs.onSurface),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${pwState.pageWaitSeconds} সেকেন্ডে নতুন বিজ্ঞাপন লোড হচ্ছে',
                        style: getMediumStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'দয়া করে একটু ধৈর্য ধরুন 🙏',
                        style: getRegularStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        } else if (state.status == FeedStatus.loading) {
          content = const Center(child: CircularProgressIndicator());
        } else {
          content = RefreshIndicator(
            color: cs.primary,
            onRefresh: () async {
              context.read<FeedBloc>().add(const RefreshFeed());
              context.read<NoticeBloc>().add(const LoadNotices());
              context.read<ProfileBloc>().add(const LoadProfileStats());
              context.read<ExploreBloc>().add(const RefreshExplore());
              await Future.delayed(const Duration(milliseconds: 600));
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  backgroundColor: cs.surface,
                  surfaceTintColor: Colors.transparent,
                  leading: IconButton(
                    icon: Icon(Icons.menu_rounded, color: cs.onSurface),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          ImageAssets.adNetworkLogo,
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AdNetwork',
                        style: getBoldStyle(fontSize: 18, color: cs.primary),
                      ),
                    ],
                  ),
                  centerTitle: false,
                  actions: [
                    IconButton(
                      onPressed: () async {
                        final Uri url = Uri.parse(
                          "https://beta.publishers.adsterra.com/referral/kRdPCzuf8a",
                        );

                        try {
                          if (!await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          )) {
                            debugPrint('Could not launch $url');
                          }
                        } catch (e) {
                          debugPrint('Error launching URL: $e');
                        }
                      },
                      icon: Text(
                        'Adsterra',
                        style: getBoldStyle(fontSize: 18, color: cs.primary),
                      ),
                    ),
                  ],
                ),
                // ── Stats Card ──
                SliverToBoxAdapter(
                  child: BlocBuilder<ProfileBloc, ProfileState>(
                    buildWhen: (prev, curr) => prev.stats != curr.stats,
                    builder: (context, profileState) {
                      final stats = profileState.stats;
                      if (stats == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Your Stats',
                                  style: getBoldStyle(
                                    fontSize: 14,
                                    color: cs.onSurface.withValues(alpha: .7),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () => context
                                      .read<ProfileBloc>()
                                      .add(const LoadProfileStats()),
                                  style: IconButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(28, 28),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _StatItem(
                                    icon: Icons.thumb_up_alt_rounded,
                                    label: 'Given Today',
                                    value: '${stats.likesGivenToday}',
                                    color: cs.primary,
                                    cs: cs,
                                  ),
                                  _verticalDivider(cs),
                                  _StatItem(
                                    icon: Icons.favorite_rounded,
                                    label: 'Received Today',
                                    value: '${stats.likesReceivedToday}',
                                    color: cs.error,
                                    cs: cs,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () {
                                final homeState = context.findAncestorStateOfType<HomePageState>();
                                if (homeState != null) {
                                  homeState.setIndex(2);
                                } else {
                                  Navigator.pushNamed(context, '/campaign');
                                }
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      cs.primary,
                                      Color.lerp(
                                        cs.primary,
                                        cs.secondary,
                                        0.45,
                                      )!,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.primary.withValues(alpha: 0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.rocket_launch_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Ad Campaigns',
                                            style: getBoldStyle(
                                              fontSize: 15,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'View sponsors & boost your score',
                                            style: getRegularStyle(
                                              fontSize: 11,
                                              color: Colors.white.withValues(
                                                alpha: 0.8,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (state.links.isEmpty)
                  SliverToBoxAdapter(
                    child: state.isLocked
                        ? _buildLockedFeedView(context, state)
                        : _buildEmptyFeedView(context),
                  ),
                if (state.links.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final link = state.links[index];
                      // RepaintBoundary isolates each card's GPU layer so
                      // parent rebuilds don't force every card to repaint.
                      return RepaintBoundary(
                        child: LinkPostCard(
                          key: ValueKey(link.id ?? 'link_$index'),
                          link: link,
                          likeCooldownSeconds: state.likeCooldownSeconds,
                          onLike: () {
                            Future.microtask(() {
                              if (context.mounted) {
                                context.read<FeedBloc>().add(
                                  ToggleLike(link.id ?? ''),
                                );
                              }
                            });
                          },
                          onUserTap: () => Navigator.of(context).pushNamed(
                            '/user-profile',
                            arguments: link.userId ?? '',
                          ),
                        ),
                      );
                    }, childCount: state.links.length),
                  ),

                // ── Notices Section ──
                SliverToBoxAdapter(
                  child: BlocBuilder<NoticeBloc, NoticeState>(
                    builder: (context, noticeState) {
                      if (noticeState.status == NoticeStatus.loading &&
                          noticeState.notices.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Notices',
                                  style: getBoldStyle(
                                    fontSize: 14,
                                    color: cs.onSurface.withValues(alpha: .7),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () => context
                                      .read<NoticeBloc>()
                                      .add(const LoadNotices()),
                                  style: IconButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(28, 28),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (noticeState.notices.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'No new notices',
                                    style: getMediumStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(alpha: .4),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Column(
                                children: noticeState.notices.map((notice) {
                                  Color bg = _parseColor(
                                    notice.bgColor,
                                    cs.primaryContainer,
                                  );
                                  Color text = _parseColor(
                                    notice.textColor,
                                    cs.onSurface,
                                  );
                                  return Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: text.withValues(alpha: .25),
                                      ),
                                    ),
                                    child: SelectableText(
                                      notice.text ?? '',
                                      textAlign: TextAlign.center,
                                      style: getSemiBoldStyle(
                                        fontSize: 14,
                                        color: text,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (state.links.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 20),
                      child: state.links.length >= 4
                          ? Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: 16,
                                  bottom: 20,
                                ),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  onPressed: () {
                                    context.read<FeedBloc>().add(
                                      ChangeFeedPage(state.currentPage + 1),
                                    );
                                  },
                                  child: Text(
                                    'NEXT',
                                    style: getBoldStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 8,
                              ),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.1),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.timer_outlined,
                                      color: cs.primary,
                                      size: 36,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'আর কোনো বিজ্ঞাপন নেই',
                                    style: getBoldStyle(
                                      fontSize: 18,
                                      color: cs.onSurface,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'পাঁচ মিনিট পর আবার চেষ্টা করুন',
                                    style: getMediumStyle(
                                      fontSize: 14,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: 16,
                                      bottom: 20,
                                    ),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF3B82F6,
                                        ),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 05,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        context.read<FeedBloc>().add(
                                          ChangeFeedPage(state.currentPage + 1),
                                        );
                                      },
                                      child: Text(
                                        'Refresh',
                                        style: getBoldStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                // ── Follow Suggestions Section ──
                SliverToBoxAdapter(
                  child: BlocBuilder<ExploreBloc, ExploreState>(
                    builder: (context, exploreState) {
                      if (exploreState.status == ExploreStatus.loading &&
                          exploreState.users.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final unfollowedUsers = exploreState.users
                          .where((u) => !u.isFollowing)
                          .toList();
                      if (unfollowedUsers.isEmpty)
                        return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Suggested for you',
                                  style: getBoldStyle(
                                    fontSize: 15,
                                    color: cs.onSurface.withValues(alpha: .7),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () => context
                                        .read<ExploreBloc>()
                                        .add(const RefreshExplore()),
                                    style: IconButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(28, 28),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 180,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: unfollowedUsers.length,
                              itemBuilder: (context, index) {
                                final u = unfollowedUsers[index];
                                return SuggestedUserCard(
                                  key: ValueKey(u.id),
                                  user: u,
                                  onFollowToggle: () async {
                                    final repo = context.read<UserRepository>();
                                    final res = await repo.toggleFollow(
                                      u.id ?? '',
                                    );
                                    if (res.isSuccess) {
                                      context.read<ExploreBloc>().add(
                                        ToggleExploreFollowState(
                                          u.id ?? '',
                                          !u.isFollowing,
                                        ),
                                      );
                                      return true;
                                    } else {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              res.message ??
                                                  'Failed to follow user.',
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          ),
                                        );
                                      }
                                      return false;
                                    }
                                  },
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/user-profile',
                                    arguments: u.id ?? '',
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 200)),
              ],
            ),
          );
        }
        final showFab =
            state.nextCooldownSeconds <= 0 &&
            state.pageWaitSeconds <= 0 &&
            state.status != FeedStatus.loading &&
            state.links.isNotEmpty;

        return SafeArea(
          child: Stack(
            children: [
              content,
              if (showFab)
                Positioned(
                  right: 16,
                  bottom: 24,
                  // Extracted into its own StatefulWidget so toggling the
                  // opacity slider or FAB state does NOT rebuild the
                  // BLoC-driven feed tree above it.
                  child: _FeedFabColumn(
                    pip: _pip,
                    isAutoScrolling: _isAutoScrolling,
                    isAutoLikeEnabled: _isAutoLikeEnabled,
                    onToggleAutoPlay: () => _toggleAutoPlay(state),
                    onShowSubscription: () => _showSubscriptionDialog(context),
                    saveOpacityDebounced: _saveOverlayOpacityDebounced,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSubscriptionDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.transparent,
          child: FutureBuilder<ApiResponse<dynamic>>(
            future: ApiClient.instance.get<dynamic>(
              '/api/getprice',
              queryParams: {'appname': 'adnetworkpro'},
              auth: true,
            ),
            builder: (context, snapshot) {
              String priceText = 'লোড হচ্ছে...';
              double? price;

              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasData &&
                    snapshot.data!.isSuccess &&
                    snapshot.data!.data is Map) {
                  final priceVal = snapshot.data!.data['price'];
                  if (priceVal != null) {
                    price = double.tryParse(priceVal.toString());
                    if (price != null) {
                      priceText = '$price ৳';
                    } else {
                      priceText = 'ফ্রি';
                    }
                  } else {
                    priceText = 'ফ্রি';
                  }
                } else {
                  priceText = 'মূল্য জানতে যোগাযোগ করুন';
                }
              }

              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Premium Icon with Gold Gradient
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.amber.shade700,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.amber.shade800,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Dialog Title
                    Text(
                      'অটো প্লে সাবস্ক্রিপশন',
                      style: getBoldStyle(
                        fontSize: 22,
                        color: isDark ? Colors.white : cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      'বিজ্ঞাপন অটো প্লে করার মাধ্যমে খুব সহজেই কাজ সম্পন্ন করুন। এই প্রিমিয়াম ফিচারটি আনলক করতে নিচের নম্বরে সাবস্ক্রিপশন পেমেন্ট করুন।',
                      style: getMediumStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.7)
                            : cs.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Dynamic Price Section
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.monetization_on_outlined,
                            color: Colors.amber.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'সাবস্ক্রিপশন ফি: ',
                            style: getMediumStyle(
                              fontSize: 15,
                              color: isDark ? Colors.white : cs.onSurface,
                            ),
                          ),
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.amber,
                                ),
                              ),
                            )
                          else
                            Text(
                              priceText,
                              style: getBoldStyle(
                                fontSize: 18,
                                color: Colors.amber.shade800,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Payment Methods Label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'বিকাশ • নগদ • রকেট • উপায়',
                            style: getBoldStyle(
                              fontSize: 12,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Number Field with Copy Button
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? cs.onSurface.withValues(alpha: 0.05)
                            : cs.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'পার্সোনাল নম্বর',
                                style: getRegularStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.5)
                                      : cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '01401011049',
                                style: getBoldStyle(
                                  fontSize: 18,
                                  color: isDark ? Colors.white : cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(
                                const ClipboardData(text: '01401011049'),
                              );
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('নম্বরটি কপি করা হয়েছে!'),
                                  backgroundColor: cs.primary,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            },
                            icon: Icon(Icons.copy_rounded, color: cs.primary),
                            tooltip: 'কপি করুন',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Instructions
                    Text(
                      'টাকা পাঠানোর পর ট্রানজেকশন আইডি এবং আপনার ইউজারনেম সহ এডমিনের সাথে যোগাযোগ করুন।',
                      style: getRegularStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : cs.onSurface.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'বন্ধ করুন',
                          style: getBoldStyle(
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _parseColor(String? hexCode, Color fallback) {
    if (hexCode == null || hexCode.isEmpty) return fallback;
    try {
      final code = hexCode.replaceAll('#', '');
      return Color(int.parse('FF$code', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Widget _verticalDivider(ColorScheme cs) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: cs.onSurface.withValues(alpha: 0.08),
    );
  }

  Widget _StatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ColorScheme cs,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: getBoldStyle(fontSize: 16, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: getRegularStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedFeedView(BuildContext context, FeedState state) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.red.withValues(alpha: 0.05)
              : cs.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Soft glowing red circle for locked icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Colors.red,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Feed Locked',
              style: getBoldStyle(fontSize: 22, color: Colors.red),
            ),
            const SizedBox(height: 12),
            if (state.errorMessage.isNotEmpty)
              Text(
                state.errorMessage,
                style: getSemiBoldStyle(
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.85),
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            if (state.instruction != null && state.instruction!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.instruction!,
                        style: getMediumStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 28),
            // Call to action button to launch Campaign Screen
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 4,
                shadowColor: cs.primary.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                final homeState = context.findAncestorStateOfType<HomePageState>();
                if (homeState != null) {
                  homeState.setIndex(2);
                } else {
                  Navigator.pushNamed(context, '/campaign');
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rocket_launch_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Go to Campaigns',
                    style: getBoldStyle(fontSize: 15, color: cs.onPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFeedView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dynamic_feed_rounded,
              size: 64,
              color: cs.onSurface.withValues(alpha: .3),
            ),
            const SizedBox(height: 12),
            Text(
              'No posts yet',
              style: getMediumStyle(
                fontSize: 16,
                color: cs.onSurface.withValues(alpha: .5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── FAB Column extracted into its own StatefulWidget ──────────────────────
// By isolating the opacity-slider toggle and auto-scroll FAB state here,
// tapping the FAB or dragging the slider rebuilds ONLY this small widget
// and never triggers a rebuild of the BLoC-driven feed list above.
class _FeedFabColumn extends StatefulWidget {
  final Pip pip;
  final bool isAutoScrolling;
  final bool isAutoLikeEnabled;
  final VoidCallback onToggleAutoPlay;
  final VoidCallback onShowSubscription;
  final void Function(double) saveOpacityDebounced;

  const _FeedFabColumn({
    required this.pip,
    required this.isAutoScrolling,
    required this.isAutoLikeEnabled,
    required this.onToggleAutoPlay,
    required this.onShowSubscription,
    required this.saveOpacityDebounced,
  });

  @override
  State<_FeedFabColumn> createState() => _FeedFabColumnState();
}

class _FeedFabColumnState extends State<_FeedFabColumn> {
  bool _showOpacitySlider = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Opacity slider panel ──
        if (_showOpacitySlider) ...[
          Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'White Overlay',
                      style: getBoldStyle(fontSize: 12, color: cs.onSurface),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: webViewOverlayOpacityNotifier,
                      builder: (context, val, _) => Text(
                        '${(val * 100).round()}%',
                        style: getBoldStyle(fontSize: 12, color: cs.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<double>(
                  valueListenable: webViewOverlayOpacityNotifier,
                  builder: (context, val, _) {
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                      ),
                      child: Slider(
                        value: val,
                        min: 0.0,
                        max: 1.0,
                        activeColor: cs.primary,
                        onChanged: (newVal) {
                          webViewOverlayOpacityNotifier.value = newVal;
                          // Debounced — only writes to disk after dragging stops
                          widget.saveOpacityDebounced(newVal);
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Overlay toggle FAB ──
        FloatingActionButton(
          heroTag: 'overlayBtn',
          onPressed: () {
            setState(() => _showOpacitySlider = !_showOpacitySlider);
          },
          backgroundColor:
              _showOpacitySlider ? cs.primary : cs.surfaceContainerHigh,
          foregroundColor: _showOpacitySlider ? Colors.white : cs.onSurface,
          mini: true,
          tooltip: 'WebView White Overlay Density',
          child: const Icon(Icons.layers_outlined, size: 20),
        ),
        const SizedBox(height: 12),

        // ── PIP button (only when auto-play is running) ──
        if (widget.isAutoScrolling) ...[
          FloatingActionButton(
            heroTag: 'pipBtn',
            onPressed: () async {
              try {
                final isSupported = await widget.pip.isSupported();
                if (isSupported) {
                  await widget.pip.start();
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'PIP is not supported on this device',
                        ),
                        backgroundColor:
                            Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              } catch (e) {
                debugPrint('Failed to start PIP: $e');
              }
            },
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            mini: true,
            child: const Icon(
              Icons.picture_in_picture_alt_rounded,
              size: 20,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Auto Play / Pause FAB ──
        FloatingActionButton.extended(
          heroTag: 'autoPlayBtn',
          onPressed: () {
            if (widget.isAutoLikeEnabled) {
              widget.onToggleAutoPlay();
            } else {
              widget.onShowSubscription();
            }
          },
          backgroundColor:
              widget.isAutoScrolling ? Colors.orange.shade700 : cs.primary,
          foregroundColor: Colors.white,
          icon: Icon(
            widget.isAutoScrolling
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 24,
          ),
          label: Text(
            widget.isAutoScrolling ? 'PAUSE' : 'AUTO PLAY',
            style: getBoldStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

