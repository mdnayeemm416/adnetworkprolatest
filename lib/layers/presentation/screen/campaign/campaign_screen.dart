import 'dart:async';
import 'dart:math';
import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/config/theme/routes_config.dart';
import 'package:adnetwork/core/extensions/extension.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';
import 'package:adnetwork/core/services/api_client.dart';
import 'package:adnetwork/core/services/token_storage.dart';
import 'package:adnetwork/core/services/autoplay_manager.dart';
import 'package:adnetwork/layers/dto/api_response.dart';
import 'package:adnetwork/layers/data/model/campaign_link_model.dart';
import 'package:adnetwork/layers/presentation/controller/campaign/campaign_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/profile/profile_bloc.dart';
import 'package:adnetwork/layers/presentation/widget/common_text_field.dart';
import 'package:adnetwork/layers/presentation/widget/gradient_button.dart';
import 'package:adnetwork/layers/presentation/widget/show_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart' as custom_tabs;
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

class CampaignScreen extends StatefulWidget {
  final bool isMandatory;
  const CampaignScreen({super.key, this.isMandatory = false});

  @override
  State<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends State<CampaignScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  bool _autoplayActive = false;
  bool _campaignStarted = false;
  final Set<String> _locallyCompletedAdIds = {};
  bool _isAutoLikeEnabled = false;

  // Background timer tracking state
  Timer? _adTimer;
  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  String? _activeAdId;
  DateTime? _activeAdStartTime;
  bool _isWatching = false;
  int _activeAdDuration = 15;

  Future<void> _loadAutoLikeStatus() async {
    final enabled = await TokenStorage.instance.isAutoLikeEnabled();
    if (mounted) {
      setState(() {
        _isAutoLikeEnabled = enabled;
      });
    }
  }

  void _navigateToFeedAfterCampaignComplete() {
    if (!mounted) return;
    showToast(
      context: context,
      message: 'Campaign completed! Navigating to feed...',
      toastificationType: ToastificationType.success,
    );
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, Routes.home);
    }
  }

  void _toggleAutoplay() {
    if (!_isAutoLikeEnabled) {
      _showSubscriptionDialog(context);
      return;
    }

    setState(() {
      _autoplayActive = !_autoplayActive;
    });

    if (_autoplayActive) {
      AutoPlayManager.shouldAutoStartFeedAutoPlay = true;
      _locallyCompletedAdIds.clear();
      final state = context.read<CampaignBloc>().state;
      final unlikedLinks = state.feedLinks
          .where((l) => !l.isLiked && !_locallyCompletedAdIds.contains(l.id))
          .toList();

      if (unlikedLinks.isNotEmpty) {
        _launchAd(unlikedLinks.first);
      } else {
        _navigateToFeedAfterCampaignComplete();
      }
    } else {
      AutoPlayManager.shouldAutoStartFeedAutoPlay = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAutoLikeStatus();
    _activeAdDuration = int.tryParse(MobileConfigManager.instance.config.campaignSecondsMin) ?? 15;
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);

    // Fetch fresh list of campaigns and completions on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final campaignBloc = context.read<CampaignBloc>();
      campaignBloc.add(const LoadCampaignFeed());
      campaignBloc.add(const LoadMyCampaigns());
      campaignBloc.add(const LoadCampaignCompletions());
      campaignBloc.add(const LoadCampaignStatus());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _adTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // App lifecycle changes listener
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isWatching && _activeAdStartTime != null) {
        // App resumed, let's cancel any active countdown/timers
        _countdownTimer?.cancel();
        _adTimer?.cancel();

        final elapsed = DateTime.now()
            .difference(_activeAdStartTime!)
            .inSeconds;
        // Check if the timer completed (either seconds remaining reached 0, or elapsed >= active duration)
        if (_secondsRemaining == 0 || elapsed >= _activeAdDuration) {
          _onAdCompleted();
        } else {
          // Closed early!
          setState(() {
            _activeAdId = null;
            _activeAdStartTime = null;
            _isWatching = false;
            _secondsRemaining = 0;
            _autoplayActive = false;
          });
          _showEarlyCloseDialog();
        }
      }
    }
  }

  Future<void> _launchAd(CampaignLinkModel campaign) async {
    final minSeconds = int.tryParse(MobileConfigManager.instance.config.campaignSecondsMin) ?? 15;
    final maxSeconds = int.tryParse(MobileConfigManager.instance.config.campaignSecondsMax) ?? 25;
    final adDuration = minSeconds >= maxSeconds
        ? minSeconds
        : minSeconds + Random().nextInt(maxSeconds - minSeconds + 1);
    final double height = MediaQuery.of(context).size.height;

    setState(() {
      _activeAdId = campaign.id;
      _activeAdStartTime = DateTime.now();
      _isWatching = true;
      _activeAdDuration = adDuration;
      _secondsRemaining = adDuration;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
        if (_secondsRemaining == 0) {
          _countdownTimer?.cancel();
          HapticFeedback.vibrate();
          custom_tabs.closeCustomTabs();
        }
      }
    });

    final theme = Theme.of(context);
    try {
      // First attempt: Try launching Custom Tab using the device's default browser
      await custom_tabs.launchUrl(
        Uri.parse(campaign.url),
        customTabsOptions: custom_tabs.CustomTabsOptions(
          partial: custom_tabs.PartialCustomTabsConfiguration(
            initialHeight: height * 0.9,
            activityHeightResizeBehavior:
                custom_tabs.CustomTabsActivityHeightResizeBehavior.fixed,
            cornerRadius: 16,
          ),
          colorSchemes: custom_tabs.CustomTabsColorSchemes.defaults(
            toolbarColor: theme.colorScheme.surface,
            navigationBarColor: theme.colorScheme.surface,
          ),
          shareState: custom_tabs.CustomTabsShareState.on,
          urlBarHidingEnabled: true,
          showTitle: true,
          browser: const custom_tabs.CustomTabsBrowserConfiguration(
            prefersDefaultBrowser: true,
          ),
        ),

        safariVCOptions: custom_tabs.SafariViewControllerOptions(
          preferredBarTintColor: theme.colorScheme.surface,
          preferredControlTintColor: theme.colorScheme.primary,
          barCollapsingEnabled: true,
          dismissButtonStyle:
              custom_tabs.SafariViewControllerDismissButtonStyle.close,
        ),
      );
    } catch (e) {
      // Second attempt (Fallback): If the default browser attempt fails,
      // launch using default custom tabs configurations as Partial Custom Tab.
      try {
        await custom_tabs.launchUrl(
          Uri.parse(campaign.url),
          customTabsOptions: custom_tabs.CustomTabsOptions(
            partial: custom_tabs.PartialCustomTabsConfiguration(
              initialHeight: height * 0.9,
              activityHeightResizeBehavior:
                  custom_tabs.CustomTabsActivityHeightResizeBehavior.fixed,
              cornerRadius: 16,
            ),
            colorSchemes: custom_tabs.CustomTabsColorSchemes.defaults(
              toolbarColor: theme.colorScheme.surface,
              navigationBarColor: theme.colorScheme.surface,
            ),
            shareState: custom_tabs.CustomTabsShareState.on,
            urlBarHidingEnabled: true,
            showTitle: true,
            browser: const custom_tabs.CustomTabsBrowserConfiguration(
              prefersDefaultBrowser: true,
            ),
          ),
          safariVCOptions: custom_tabs.SafariViewControllerOptions(
            preferredBarTintColor: theme.colorScheme.surface,
            preferredControlTintColor: theme.colorScheme.primary,
            barCollapsingEnabled: true,
            dismissButtonStyle:
                custom_tabs.SafariViewControllerDismissButtonStyle.close,
          ),
        );
      } catch (fallbackError) {
        _countdownTimer?.cancel();
        setState(() {
          _activeAdId = null;
          _activeAdStartTime = null;
          _isWatching = false;
          _secondsRemaining = 0;
        });
        if (mounted) {
          showToast(
            context: context,
            message: 'Could not open ad link: $fallbackError',
            toastificationType: ToastificationType.error,
          );
        }
      }
    }
  }

  BuildContext? _loaderContext;

  void _showLoaderDialog(BuildContext context) {
    if (_loaderContext != null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _loaderContext = ctx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  'Completing campaign ad...',
                  style: getMediumStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _loaderContext = null;
    });
  }

  void _dismissLoaderDialog(BuildContext context) {
    if (_loaderContext != null) {
      Navigator.of(_loaderContext!).pop();
      _loaderContext = null;
    }
  }

  Future<bool> _showExitConfirmationDialog(int remainingAds) async {
    if (!mounted) return false;
    final cs = Theme.of(context).colorScheme;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: cs.error.withValues(alpha: .2), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: .1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: cs.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ক্যাম্পেইন অসম্পূর্ণ!',
                  style: getBoldStyle(fontSize: 18, color: cs.onSurface),
                ),
              ),
            ],
          ),
          content: Text(
            'আপনার এখনও $remainingAds টি বিজ্ঞাপন দেখা বাকি আছে। আপনি যদি এখন ফিরে যান, তবে পরবর্তীতে পয়েন্ট পেতে আপনাকে আবার শুরু থেকে ২০টি লিঙ্ক দেখতে হবে।',
            style: getRegularStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: .8),
            ).copyWith(height: 1.5),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cs.error.withValues(alpha: .5)),
                        foregroundColor: cs.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'ফিরে যান',
                        style: getBoldStyle(fontSize: 14, color: cs.error),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'এখানেই থাকুন',
                        style: getBoldStyle(fontSize: 14, color: cs.onPrimary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _onAdCompleted() {
    if (_activeAdId == null) return;

    final adId = _activeAdId!;
    _locallyCompletedAdIds.add(adId);

    // Reward scoring
    context.read<CampaignBloc>().add(LikeCampaignLink(adId));

    setState(() {
      _activeAdId = null;
      _activeAdStartTime = null;
      _isWatching = false;
      _secondsRemaining = 0;
    });
  }

  Future<void> _launchNextAdWithDelay() async {
    // Wait for a brief moment for UI transition
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    final state = context.read<CampaignBloc>().state;
    final unlikedLinks = state.feedLinks
        .where((l) => !l.isLiked && !_locallyCompletedAdIds.contains(l.id))
        .toList();

    if (_autoplayActive && unlikedLinks.isNotEmpty) {
      _launchAd(unlikedLinks.first);
    } else {
      final wasAutoplay = _autoplayActive;
      setState(() {
        _autoplayActive = false;
      });
      if (wasAutoplay && unlikedLinks.isEmpty) {
        AutoPlayManager.shouldAutoStartFeedAutoPlay = true;
        _navigateToFeedAfterCampaignComplete();
      }
    }
  }

  void _showEarlyCloseDialog() {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: cs.error.withValues(alpha: .2), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: .1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: cs.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'বিজ্ঞাপনটি সম্পূর্ণ দেখুন',
                  style: getBoldStyle(fontSize: 18, color: cs.onSurface),
                ),
              ),
            ],
          ),
          content: Text(
            'অনুগ্রহ করে বিজ্ঞাপনটি নিজে বন্ধ করবেন না, এটি ১৫ সেকেন্ড পর স্বয়ংক্রিয়ভাবে বন্ধ হয়ে যাবে। নিজে থেকে আগে বন্ধ করলে আপনার দেখার সময় গণনা করা হবে না এবং কোনো ক্রেডিট পাবেন না।',
            style: getRegularStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: .8),
            ).copyWith(height: 1.5),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'ঠিক আছে',
                  style: getBoldStyle(fontSize: 14, color: cs.onPrimary),
                ),
              ),
            ),
          ],
        );
      },
    );
  }



  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final state = context.watch<CampaignBloc>().state;
    final unlikedLinks = state.feedLinks.where((l) => !l.isLiked).toList();
    final canPop = !_campaignStarted || unlikedLinks.isEmpty;

    if (_isWatching) {
      final double progress = _activeAdDuration > 0
          ? (_activeAdDuration - _secondsRemaining) / _activeAdDuration
          : 0.0;
      final isCompleted = _secondsRemaining == 0;
      final height = MediaQuery.of(context).size.height;
      final topHeight = height * 0.1; // 10% of screen height

      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                height: topHeight - MediaQuery.of(context).padding.top,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [cs.surface, cs.surface.withValues(alpha: 0.85)]
                        : [const Color(0xFF0F0F0F), Colors.black],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: (isCompleted ? Colors.green : cs.primary)
                          .withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isCompleted ? Colors.green : cs.primary)
                          .withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isCompleted ? Colors.green : cs.primary,
                          ),
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isCompleted ? '✓' : '${_secondsRemaining}s',
                        style: getBoldStyle(
                          fontSize: 12,
                          color: isCompleted ? Colors.green : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '|',
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isCompleted
                              ? 'বিজ্ঞাপন সম্পন্ন! নিচে ব্রাউজারটি বন্ধ করে ফিরে আসুন।'
                              : 'বিজ্ঞাপন ভেরিফাই হচ্ছে, অনুগ্রহ করে অপেক্ষা করুন...',
                          style: getMediumStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.open_in_new_rounded,
                        color: Colors.white12,
                        size: 32,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Sponsor website is shown below',
                        style: TextStyle(color: Colors.white12, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: widget.isMandatory ? false : canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (widget.isMandatory) {
          showToast(
            context: context,
            message: 'You must complete the campaigns to proceed.',
            toastificationType: ToastificationType.warning,
          );
          return;
        }
        final shouldExit = await _showExitConfirmationDialog(
          unlikedLinks.length,
        );
        if (shouldExit && context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: BlocListener<CampaignBloc, CampaignState>(
        listenWhen: (previous, current) =>
            previous.actionStatus != current.actionStatus ||
            previous.feedStatus != current.feedStatus ||
            previous.feedLinks != current.feedLinks,
        listener: (context, state) {
          if (state.actionStatus == CampaignActionStatus.loading) {
            _showLoaderDialog(context);
          } else if (state.actionStatus == CampaignActionStatus.success) {
            _dismissLoaderDialog(context);
            showToast(
              context: context,
              message: state.actionMessage,
              toastificationType: ToastificationType.success,
            );
            context.read<CampaignBloc>().add(const ClearCampaignErrors());

            final unlikedLinks = state.feedLinks.where((l) => !l.isLiked).toList();
            if (state.feedStatus == CampaignStatus.loaded && unlikedLinks.isEmpty) {
              AutoPlayManager.shouldAutoStartFeedAutoPlay = true;
              _navigateToFeedAfterCampaignComplete();
              return;
            }

            if (_autoplayActive) {
              _launchNextAdWithDelay();
            }
          } else if (state.actionStatus == CampaignActionStatus.error) {
            _dismissLoaderDialog(context);
            showToast(
              context: context,
              message: state.actionMessage,
              toastificationType: ToastificationType.error,
            );
            context.read<CampaignBloc>().add(const ClearCampaignErrors());
            if (_autoplayActive) {
              _launchNextAdWithDelay();
            }
          }

          // When feed loads and all campaigns are already done or no campaigns exist,
          // navigate to feed and auto-start auto-play.
          if (state.feedStatus == CampaignStatus.loaded) {
            final unlikedLinks = state.feedLinks.where((l) => !l.isLiked).toList();
            if (unlikedLinks.isEmpty || state.feedLinks.isEmpty) {
              AutoPlayManager.shouldAutoStartFeedAutoPlay = true;
              _navigateToFeedAfterCampaignComplete();
            }
          }
        },
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
            elevation: 0,
            automaticallyImplyLeading: !widget.isMandatory,
            leading: widget.isMandatory
                ? null
                : IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                    onPressed: () async {
                      if (canPop) {
                        Navigator.pop(context);
                      } else {
                        final shouldExit = await _showExitConfirmationDialog(
                          unlikedLinks.length,
                        );
                        if (shouldExit && context.mounted) {
                          Navigator.pop(context);
                        }
                      }
                    },
                  ),
            title: Text(
              'Campaigns',
              style: getBoldStyle(fontSize: 20, color: cs.onSurface),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(66),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark
                      ? cs.onSurface.withValues(alpha: .04)
                      : cs.primary.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: isDark ? .1 : .05),
                    width: 1,
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: cs.primary,
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: isDark ? .25 : .15),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: cs.onPrimary,
                  unselectedLabelColor: cs.onSurface.withValues(alpha: .6),
                  labelStyle: getBoldStyle(fontSize: 13),
                  unselectedLabelStyle: getMediumStyle(fontSize: 13),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Campaign Feed'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_link_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('My Campaigns'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _CampaignFeedTab(
                isDark: isDark,
                campaignStarted: _campaignStarted,
                onStartCampaign: () {
                  setState(() {
                    _campaignStarted = true;
                  });
                },
                autoplayActive: _autoplayActive,
                onToggleAutoplay: _toggleAutoplay,
                onLaunchAd: _launchAd,
                activeAdId: _activeAdId,
                activeAdDuration: _activeAdDuration,
              ),
              _MyCampaignsTab(isDark: isDark),
            ],
          ),
        ),
      ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// CAMPAIGN FEED TAB
// ─────────────────────────────────────────────────────────────────────────────
class _CampaignFeedTab extends StatelessWidget {
  final bool isDark;
  final bool campaignStarted;
  final VoidCallback onStartCampaign;
  final bool autoplayActive;
  final VoidCallback onToggleAutoplay;
  final Function(CampaignLinkModel) onLaunchAd;
  final String? activeAdId;
  final int activeAdDuration;

  const _CampaignFeedTab({
    required this.isDark,
    required this.campaignStarted,
    required this.onStartCampaign,
    required this.autoplayActive,
    required this.onToggleAutoplay,
    required this.onLaunchAd,
    required this.activeAdId,
    required this.activeAdDuration,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: () async {
        final campaignBloc = context.read<CampaignBloc>();
        campaignBloc.add(const LoadCampaignFeed());
        campaignBloc.add(const LoadCampaignCompletions());
        campaignBloc.add(const LoadCampaignStatus());
        await Future.delayed(const Duration(milliseconds: 600));
      },
      child: BlocBuilder<CampaignBloc, CampaignState>(
        builder: (context, state) {
          if (state.feedStatus == CampaignStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.feedStatus == CampaignStatus.error) {
            final errorMsg = state.feedErrorMessage.toLowerCase();
            final isLimitReached = errorMsg.contains('limit reached');
            final isUnderfilled =
                errorMsg.contains('not available') ||
                errorMsg.contains('underfilled');

            return Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? cs.onSurface.withValues(alpha: .04)
                          : cs.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isLimitReached
                            ? cs.primary.withValues(alpha: .2)
                            : cs.error.withValues(alpha: .15),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isLimitReached
                                ? cs.primary.withValues(alpha: .1)
                                : cs.error.withValues(alpha: .08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isLimitReached
                                ? Icons.timer_rounded
                                : (isUnderfilled
                                      ? Icons.campaign_rounded
                                      : Icons.error_outline_rounded),
                            size: 48,
                            color: isLimitReached ? cs.primary : cs.error,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          isLimitReached
                              ? 'Limit Reached'
                              : (isUnderfilled
                                    ? 'No Campaigns Available'
                                    : 'Error Occurred'),
                          style: getBoldStyle(
                            fontSize: 18,
                            color: cs.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          state.feedErrorMessage,
                          style: getRegularStyle(
                            fontSize: 14,
                            color: cs.onSurface.withValues(alpha: .6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 160,
                          child: GradientButton(
                            buttonName: 'Retry Feed',
                            icon: Icons.refresh_rounded,
                            onPressed: () {
                              context.read<CampaignBloc>().add(
                                const LoadCampaignFeed(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final status = state.campaignStatus;
          final bool isAvailable = status?.campaignsAvailable ?? true;
          final int timeRemaining = status?.timeRemaining ?? 0;
          final String timeReadable =
              status?.timeRemainingReadable ?? "0 hours and 0 minutes";
          final int completedToday = status?.completedToday ?? 0;
          final bool isOnCooldown = !isAvailable || timeRemaining > 0;

          if (!campaignStarted) {
            return Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 36,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isOnCooldown
                            ? (isDark
                                  ? [
                                      Colors.orange.withValues(alpha: .08),
                                      cs.error.withValues(alpha: .04),
                                      cs.surface,
                                    ]
                                  : [
                                      Colors.orange.withValues(alpha: .04),
                                      cs.error.withValues(alpha: .02),
                                      cs.surface,
                                    ])
                            : (isDark
                                  ? [
                                      cs.primary.withValues(alpha: .12),
                                      cs.secondary.withValues(alpha: .06),
                                      cs.surface,
                                    ]
                                  : [
                                      cs.primary.withValues(alpha: .06),
                                      cs.secondary.withValues(alpha: .03),
                                      cs.surface,
                                    ]),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: isOnCooldown
                            ? Colors.orange.withValues(alpha: .25)
                            : cs.primary.withValues(alpha: .15),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isOnCooldown ? Colors.orange : cs.primary)
                              .withValues(alpha: isDark ? .15 : .05),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tag Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isOnCooldown
                                  ? [Colors.orange, cs.error]
                                  : [cs.primary, cs.secondary],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isOnCooldown ? Colors.orange : cs.primary)
                                        .withValues(alpha: .25),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            isOnCooldown
                                ? 'COOLDOWN ACTIVE'
                                : 'HIGH-YIELD OPTION',
                            style: getBoldStyle(
                              fontSize: 10,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Rocket Launch Stack
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                color:
                                    (isOnCooldown ? Colors.orange : cs.primary)
                                        .withValues(alpha: .08),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isOnCooldown
                                      ? [
                                          Colors.orange,
                                          Color.lerp(
                                            Colors.orange,
                                            cs.error,
                                            0.5,
                                          )!,
                                        ]
                                      : [
                                          cs.primary,
                                          Color.lerp(
                                            cs.primary,
                                            cs.secondary,
                                            0.5,
                                          )!,
                                        ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isOnCooldown
                                                ? Colors.orange
                                                : cs.primary)
                                            .withValues(alpha: .35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isOnCooldown
                                    ? Icons.timer_rounded
                                    : Icons.rocket_launch_rounded,
                                size: 36,
                                color: cs.onPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(
                          isOnCooldown ? 'Campaign Cooldown' : 'Start Campaign',
                          style: getBoldStyle(
                            fontSize: 24,
                            color: cs.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isOnCooldown
                              ? 'You have completed today\'s campaigns. Please wait for the cooldown timer to finish before starting new campaigns.'
                              : 'Unlock higher CPM and better revenue stream by viewing targeted sponsor campaigns.',
                          style: getRegularStyle(
                            fontSize: 14,
                            color: cs.onSurface.withValues(alpha: .6),
                          ).copyWith(height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                        if (isOnCooldown) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(
                                alpha: isDark ? .1 : .05,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: .2),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.hourglass_bottom_rounded,
                                  color: Colors.orange.shade700,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "Remaining: $timeReadable",
                                    style: getSemiBoldStyle(
                                      fontSize: 13,
                                      color: Colors.orange.shade700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 28),
                          Divider(color: cs.onSurface.withValues(alpha: .06)),
                          const SizedBox(height: 20),
                          // Premium Stat Cards Row
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  title: 'Ads Available',
                                  value: '${state.feedLinks.length}',
                                  icon: Icons.filter_none_rounded,
                                  color: cs.primary,
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  title: 'Completed Today',
                                  value: '$completedToday',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: Colors.green,
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  title: 'Status',
                                  value: 'Ready',
                                  icon: Icons.flash_on_rounded,
                                  color: Colors.blue,
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 32),
                        GradientButton(
                          buttonName: isOnCooldown
                              ? 'Cooldown Active'
                              : 'Start Campaign',
                          icon: isOnCooldown
                              ? Icons.lock_outline_rounded
                              : Icons.rocket_launch_rounded,
                          onPressed: isOnCooldown ? null : onStartCampaign,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final unlikedLinks = state.feedLinks
              .where((l) => !l.isLiked)
              .toList();

          if (state.feedLinks.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: .05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.track_changes_rounded,
                        size: 48,
                        color: cs.primary.withValues(alpha: .4),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No Campaigns Available',
                      style: getSemiBoldStyle(
                        fontSize: 18,
                        color: cs.onSurface.withValues(alpha: .6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pull down to refresh and try again',
                      style: getRegularStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: .35),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (unlikedLinks.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: .05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 48,
                        color: cs.primary.withValues(alpha: .4),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'All Campaigns Completed!',
                      style: getSemiBoldStyle(
                        fontSize: 18,
                        color: cs.onSurface.withValues(alpha: .6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You have viewed all available sponsor ads.',
                      style: getRegularStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: .35),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Active ad list with Auto Play control bar at the top
          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: unlikedLinks.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildAutoplayControlBar(context, state.feedLinks.length, unlikedLinks.length);
              }
              final campaign = unlikedLinks[index - 1];
              final originalIndex = state.feedLinks.indexWhere(
                (l) => l.id == campaign.id,
              );
              return _CampaignFeedCard(
                campaign: campaign,
                index: originalIndex != -1 ? originalIndex : (index - 1),
                isDark: isDark,
                onTap: () {
                  if (activeAdId == null) {
                    onLaunchAd(campaign);
                  }
                },
                isActiveWatch: activeAdId == campaign.id,
                activeAdDuration: activeAdDuration,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAutoplayControlBar(BuildContext context, int totalAds, int remainingAds) {
    final cs = Theme.of(context).colorScheme;
    final completedAds = totalAds - remainingAds;
    final double percent = totalAds > 0 ? (completedAds / totalAds) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: autoplayActive
              ? [
                  cs.primary.withValues(alpha: .15),
                  cs.secondary.withValues(alpha: .08),
                ]
              : [
                  cs.onSurface.withValues(alpha: .04),
                  cs.onSurface.withValues(alpha: .02),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: autoplayActive
              ? cs.primary.withValues(alpha: .3)
              : cs.onSurface.withValues(alpha: .1),
          width: 1.5,
        ),
        boxShadow: [
          if (autoplayActive)
            BoxShadow(
              color: cs.primary.withValues(alpha: .08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _AutoplayStatusDot(active: autoplayActive),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      autoplayActive ? 'Auto Play Running' : 'Auto Play Paused',
                      style: getBoldStyle(
                        fontSize: 15,
                        color: autoplayActive ? cs.primary : cs.onSurface.withValues(alpha: .8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      autoplayActive ? 'Watching ads sequentially...' : 'Sequence is idle',
                      style: getRegularStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: .5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: onToggleAutoplay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: autoplayActive ? Colors.orange.shade700 : cs.primary,
                  foregroundColor: Colors.white,
                  elevation: autoplayActive ? 0 : 2,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  autoplayActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 18,
                ),
                label: Text(
                  autoplayActive ? 'Pause' : 'Start Auto Play',
                  style: getBoldStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Campaign Progress',
                style: getSemiBoldStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: .6),
                ),
              ),
              Text(
                '$completedAds / $totalAds Ads Completed',
                style: getBoldStyle(
                  fontSize: 11,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 6,
              backgroundColor: autoplayActive
                  ? cs.primary.withValues(alpha: .1)
                  : cs.onSurface.withValues(alpha: .06),
              valueColor: AlwaysStoppedAnimation<Color>(
                autoplayActive ? cs.primary : cs.onSurface.withValues(alpha: .4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoplayStatusDot extends StatefulWidget {
  final bool active;
  const _AutoplayStatusDot({required this.active});

  @override
  State<_AutoplayStatusDot> createState() => _AutoplayStatusDotState();
}

class _AutoplayStatusDotState extends State<_AutoplayStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.active) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AutoplayStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dotColor = widget.active ? Colors.green : Colors.grey;

    if (!widget.active) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: dotColor.withValues(alpha: .6),
          shape: BoxShape.circle,
          border: Border.all(color: cs.surface, width: 2),
        ),
      );
    }

    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: dotColor.withValues(alpha: .5),
              blurRadius: 6,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: cs.surface, width: 2),
        ),
      ),
    );
  }
}

class _CampaignFeedCard extends StatelessWidget {
  final CampaignLinkModel campaign;
  final int index;
  final bool isDark;
  final VoidCallback onTap;
  final bool isActiveWatch;
  final int activeAdDuration;

  const _CampaignFeedCard({
    required this.campaign,
    required this.index,
    required this.isDark,
    required this.onTap,
    required this.isActiveWatch,
    required this.activeAdDuration,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    final Color cardBg = isDark
        ? cs.onSurface.withValues(alpha: .04)
        : cs.primaryContainer;
    final Color borderColor = cs.primary.withValues(alpha: isDark ? .12 : .06);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isActiveWatch ? cs.primary : borderColor,
          width: isActiveWatch ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: cs.primary.withValues(alpha: .04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Glowing Icon squircle
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: .15),
                      cs.secondary.withValues(alpha: .1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.star_rounded, size: 24, color: cs.secondary),
              ),
              const SizedBox(width: 16),
              // Ad info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sponsor Ad Task #${index + 1}',
                      style: getBoldStyle(fontSize: 16, color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'High CPM Yield Campaign',
                      style: getBoldStyle(fontSize: 10, color: cs.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Yield explanation content
          Text(
            'Launch this campaign task and watch the sponsor ad for ${MobileConfigManager.instance.config.campaignSecondsMin} to ${MobileConfigManager.instance.config.campaignSecondsMax} seconds to receive your yield score credit. The tab will automatically close on completion.',
            style: getRegularStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: .6),
            ).copyWith(height: 1.4),
          ),
          const SizedBox(height: 20),
          // View Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: isActiveWatch ? Colors.grey : cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isActiveWatch
                        ? Icons.hourglass_top_rounded
                        : Icons.rocket_launch_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isActiveWatch
                        ? 'Watching (${activeAdDuration}s)...'
                        : 'Launch Campaign Ad',
                    style: getBoldStyle(fontSize: 13, color: cs.onPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MY CAMPAIGNS TAB
// ─────────────────────────────────────────────────────────────────────────────
class _MyCampaignsTab extends StatelessWidget {
  final bool isDark;

  const _MyCampaignsTab({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final user = context.watch<ProfileBloc>().state.currentUser;
    final isHighRole = user?.role == 'admin' || user?.role == 'superadmin';
    final maxLinks = isHighRole ? 10 : 6;

    return BlocBuilder<CampaignBloc, CampaignState>(
      builder: (context, state) {
        final linksCount = state.myLinks.length;

        return RefreshIndicator(
          color: cs.primary,
          onRefresh: () async {
            context.read<CampaignBloc>().add(const LoadMyCampaigns());
            await Future.delayed(const Duration(milliseconds: 600));
          },
          child: Stack(
            children: [
              CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // Quota Progress Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? cs.onSurface.withValues(alpha: .03)
                              : cs.primary.withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: .1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Campaign Upload Quota',
                                  style: getSemiBoldStyle(
                                    fontSize: 14,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$linksCount / $maxLinks Links',
                                    style: getBoldStyle(
                                      fontSize: 12,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: maxLinks > 0
                                    ? (linksCount / maxLinks).clamp(0.0, 1.0)
                                    : 0,
                                minHeight: 8,
                                backgroundColor: cs.primary.withValues(
                                  alpha: .1,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cs.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              user?.role == 'admin' ||
                                      user?.role == 'superadmin'
                                  ? 'Admins/Superadmins can upload up to 10 active campaign links.'
                                  : 'Users/Moderators can upload up to 6 active campaign links.',
                              style: getRegularStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: .5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Links List
                  if (state.myLinksStatus == CampaignStatus.loading &&
                      state.myLinks.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (state.myLinks.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: .05),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.add_link_rounded,
                                size: 48,
                                color: cs.primary.withValues(alpha: .4),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No campaigns uploaded',
                              style: getSemiBoldStyle(
                                fontSize: 18,
                                color: cs.onSurface.withValues(alpha: .6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap + below to add your campaign link',
                              style: getRegularStyle(
                                fontSize: 13,
                                color: cs.onSurface.withValues(alpha: .35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final campaign = state.myLinks[index];
                          return _MyCampaignCard(
                            campaign: campaign,
                            index: index,
                            isDark: isDark,
                          );
                        }, childCount: state.myLinks.length),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 90)),
                ],
              ),
              // Floating Action Button
              if (linksCount < maxLinks)
                Positioned(
                  right: 20,
                  bottom: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          cs.primary,
                          Color.lerp(cs.primary, cs.secondary, 0.4)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: .35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () =>
                            _showAddCampaignDialog(context, state.myLinks),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                color: cs.onPrimary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Add Campaign',
                                style: getMediumStyle(
                                  fontSize: 14,
                                  color: cs.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAddCampaignDialog(
    BuildContext context,
    List<CampaignLinkModel> currentLinks,
  ) {
    final urlCtrl = TextEditingController();
    final cs = context.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Add Campaign Link',
                  style: getBoldStyle(fontSize: 20, color: cs.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter the URL of the promotional campaign you want to add.',
                  style: getRegularStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: .5),
                  ),
                ),
                const SizedBox(height: 20),
                CommonTextField(
                  label: 'Campaign URL *',
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  hintText: 'https://example.com/promo',
                  prefixIcon: Icons.link_rounded,
                ),
                const SizedBox(height: 24),
                GradientButton(
                  buttonName: 'Submit Campaign',
                  icon: Icons.rocket_launch_rounded,
                  onPressed: () {
                    final url = urlCtrl.text.trim();

                    if (url.isEmpty) {
                      showToast(
                        context: context,
                        message: 'URL field cannot be empty',
                        toastificationType: ToastificationType.error,
                      );
                      return;
                    }

                    if (!url.startsWith('http://') &&
                        !url.startsWith('https://')) {
                      showToast(
                        context: context,
                        message: 'URL must start with http:// or https://',
                        toastificationType: ToastificationType.error,
                      );
                      return;
                    }

                    // Check for duplicate URL
                    final isDuplicate = currentLinks.any(
                      (link) => link.url.toLowerCase() == url.toLowerCase(),
                    );
                    if (isDuplicate) {
                      showToast(
                        context: context,
                        message: 'This campaign link already exists!',
                        toastificationType: ToastificationType.warning,
                      );
                      return;
                    }
                    // Submit
                    context.read<CampaignBloc>().add(AddCampaignLink(url: url));

                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyCampaignCard extends StatelessWidget {
  final CampaignLinkModel campaign;
  final int index;
  final bool isDark;

  const _MyCampaignCard({
    required this.campaign,
    required this.index,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final displayIndex = index + 1;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? cs.onSurface.withValues(alpha: .04)
            : cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withValues(alpha: isDark ? .12 : .06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: cs.primary.withValues(alpha: .03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: Row(
        children: [
          // Index number badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: .2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '#$displayIndex',
                style: getBoldStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // URL & date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promo Link $displayIndex',
                  style: getSemiBoldStyle(fontSize: 13, color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  campaign.url,
                  style: getRegularStyle(
                    fontSize: 12,
                    color: cs.primary.withValues(alpha: .8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      size: 12,
                      color: cs.error.withValues(alpha: .6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${campaign.globalLikes}',
                      style: getRegularStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: .5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.access_time_rounded,
                      size: 12,
                      color: cs.onSurface.withValues(alpha: .35),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd MMM yyyy').format(campaign.createdAt),
                      style: getRegularStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: .5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Delete Button
          Material(
            color: cs.error.withValues(alpha: isDark ? .1 : .06),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _confirmDelete(context),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: cs.error.withValues(alpha: .75),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final cs = context.colorScheme;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Delete Campaign',
            style: getBoldStyle(fontSize: 18, color: cs.onSurface),
          ),
          content: Text(
            'Are you sure you want to delete this campaign link? This action cannot be undone.',
            style: getRegularStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: .7),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: getMediumStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: .6),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                context.read<CampaignBloc>().add(
                  DeleteCampaignLink(campaign.id),
                );
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Delete',
                style: getBoldStyle(fontSize: 14, color: cs.onError),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? cs.onSurface.withValues(alpha: .03) : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .15), width: 1),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: color.withValues(alpha: .04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: getBoldStyle(fontSize: 16, color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: getRegularStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: .5),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
