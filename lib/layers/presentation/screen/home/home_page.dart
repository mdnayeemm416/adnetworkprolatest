import 'dart:async';
import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/core/services/token_storage.dart';
import 'package:adnetwork/core/services/vpn_dns_checker.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';
import 'package:adnetwork/core/services/app_update_service.dart';
import 'package:adnetwork/layers/data/repo/remote/link_repository.dart';
import 'package:adnetwork/layers/data/repo/remote/user_repository.dart';
import 'package:adnetwork/layers/presentation/controller/feed/feed_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/link/link_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/notice/notice_bloc.dart';
import 'package:adnetwork/layers/data/repo/remote/notice_repository.dart';
import 'package:adnetwork/layers/presentation/controller/explore/explore_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/profile/profile_bloc.dart';
import 'package:adnetwork/layers/presentation/screen/explore/explore_screen.dart';
import 'package:adnetwork/layers/presentation/screen/feed/feed_screen.dart';
import 'package:adnetwork/layers/presentation/screen/links/my_links_screen.dart';
import 'package:adnetwork/layers/presentation/screen/profile/profile_screen.dart';
import 'package:adnetwork/layers/presentation/screen/campaign/campaign_screen.dart';
import 'package:adnetwork/layers/presentation/controller/campaign/campaign_bloc.dart';
import 'package:adnetwork/layers/presentation/widget/link_queue_overlay.dart';
import 'package:adnetwork/layers/presentation/widget/user_avatar.dart';
import 'package:adnetwork/core/services/link_queue_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';


class HomePage extends StatefulWidget {
  final int? initialIndex;
  const HomePage({
    super.key,
    this.initialIndex,
  });
  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int _idx = 0;
  BuildContext? _descendantContext;

  int getCurrentIndex() => _idx;

  void _showCampaignLockDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: cs.primary.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.lock_rounded, color: cs.primary, size: 28),
              const SizedBox(width: 12),
              Text(
                'ফিড লক করা আছে',
                style: getBoldStyle(fontSize: 18, color: cs.onSurface),
              ),
            ],
          ),
          content: Text(
            'ফিড পেজের লক খোলার জন্য অনুগ্রহ করে ১টি সম্পূর্ণ ক্যাম্পেইন সম্পন্ন করুন।',
            style: getRegularStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'বন্ধ করুন',
                style: getMediumStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(dialogCtx);
                setIndex(2); // Go to Campaigns tab
              },
              child: Text(
                'ক্যাম্পেইনে যান',
                style: getBoldStyle(fontSize: 14, color: cs.onPrimary),
              ),
            ),
          ],
        );
      },
    );
  }

  void setIndex(int index, {bool bypassLock = false}) {
    if (index == 0 && !bypassLock) {
      final campaignState = context.read<CampaignBloc>().state;
      final hasAvailableCampaigns = campaignState.campaignStatus?.campaignsAvailable ?? false;
      if (hasAvailableCampaigns) {
        _showCampaignLockDialog(context);
        return;
      }
    }
    setState(() {
      _idx = index;
    });

    if (_descendantContext != null) {
      if (index == 0) {
        final feedBloc = _descendantContext!.read<FeedBloc>();
        if (feedBloc.state.status == FeedStatus.initial) {
          feedBloc.add(const LoadFeed());
        }
        _descendantContext!.read<NoticeBloc>().add(const LoadNotices());
      } else if (index == 1) {
        _descendantContext!.read<LinkBloc>().add(const LoadMyLinks());
      } else if (index == 2) {
        final campaignBloc = _descendantContext!.read<CampaignBloc>();
        campaignBloc.add(const LoadCampaignFeed());
        campaignBloc.add(const LoadMyCampaigns());
        campaignBloc.add(const LoadCampaignCompletions());
        campaignBloc.add(const LoadCampaignStatus());
      } else if (index == 3) {
        _descendantContext!.read<ExploreBloc>().add(const LoadExplore());
      } else if (index == 4) {
        _descendantContext!.read<ProfileBloc>().add(const LoadProfileStats());
      }
    }
  }

  static const _labels = ['Feed', 'My Links', 'Campaign', 'Explore', 'Profile'];
  static const _icons = [
    Icons.dynamic_feed_rounded,
    Icons.link_rounded,
    Icons.track_changes_rounded,
    Icons.explore_rounded,
    Icons.person_rounded,
  ];


  Timer? _vpnDnsCheckTimer;
  bool _isDialogShowing = false;
  BuildContext? _dialogContext;

  @override
  void initState() {
    super.initState();
    if (widget.initialIndex != null) {
      _idx = widget.initialIndex!;
    }
    // Load stats once on initial feed load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ProfileBloc>().add(const LoadProfileStats());
        // Run update check in the background after login/navigation
        AppUpdateService.checkAndShowUpdate(context);

        if (_descendantContext != null) {
          if (_idx == 0) {
            _descendantContext!.read<FeedBloc>().add(const LoadFeed());
            _descendantContext!.read<NoticeBloc>().add(const LoadNotices());
          } else if (_idx == 1) {
            _descendantContext!.read<LinkBloc>().add(const LoadMyLinks());
          } else if (_idx == 2) {
            final campaignBloc = _descendantContext!.read<CampaignBloc>();
            campaignBloc.add(const LoadCampaignFeed());
            campaignBloc.add(const LoadMyCampaigns());
            campaignBloc.add(const LoadCampaignCompletions());
            campaignBloc.add(const LoadCampaignStatus());
          } else if (_idx == 3) {
            _descendantContext!.read<ExploreBloc>().add(const LoadExplore());
          } else if (_idx == 4) {
            _descendantContext!.read<ProfileBloc>().add(const LoadProfileStats());
          }
        }
      }
    });
    _startVpnDnsCheck();
  }

  @override
  void dispose() {
    _vpnDnsCheckTimer?.cancel();
    if (_isDialogShowing && _dialogContext != null) {
      try {
        Navigator.of(_dialogContext!).pop();
      } catch (_) {}
    }
    super.dispose();
  }

  void _startVpnDnsCheck() {
    _vpnDnsCheckTimer?.cancel();
    _vpnDnsCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      final allowDns = MobileConfigManager.instance.config.allowDns;
      if (allowDns != "1") {
        if (_isDialogShowing && _dialogContext != null) {
          try {
            Navigator.of(_dialogContext!).pop();
          } catch (_) {}
          _isDialogShowing = false;
          _dialogContext = null;
        }
        return;
      }

      final isVpn = await VpnDnsChecker.isVpnActive();
      final isDns = await VpnDnsChecker.isPrivateDnsActive();

      if (isVpn || isDns) {
        if (!_isDialogShowing && mounted) {
          _showVpnDnsDialog(isVpn, isDns);
        }
      } else {
        if (_isDialogShowing && _dialogContext != null) {
          try {
            Navigator.of(_dialogContext!).pop();
          } catch (_) {}
          _isDialogShowing = false;
          _dialogContext = null;
        }
      }
    });
  }

  void _showVpnDnsDialog(bool isVpn, bool isDns) {
    _isDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        _dialogContext = dialogCtx;
        final cs = Theme.of(context).colorScheme;

        List<String> reasons = [];
        if (isVpn) reasons.add("VPN");
        if (isDns) reasons.add("Private DNS");
        final reasonText = reasons.join(" & ");
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: cs.error.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            title: Row(
              children: [
                Icon(Icons.gpp_bad_rounded, color: cs.error, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Security Alert',
                  style: getBoldStyle(fontSize: 18, color: cs.onSurface),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We detected an active $reasonText connection.',
                  style: getBoldStyle(fontSize: 15, color: cs.onSurface),
                ),
                const SizedBox(height: 12),
                Text(
                  'To protect the ad network integrity, VPN and Private DNS usage is not allowed. Please disable them to resume using the app.',
                  style: getRegularStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Waiting for disconnection...',
                        style: getMediumStyle(fontSize: 13, color: cs.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isDialogShowing = false;
      _dialogContext = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final linkRepo = context.read<LinkRepository>();

    final pages = [
      FeedScreen(isActive: _idx == 0),
      const MyLinksScreen(),
      CampaignScreen(isTab: true, isActive: _idx == 2),
      const ExploreScreen(),
      const ProfileScreen(),
    ];

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => FeedBloc(linkRepository: linkRepo),
        ),
        BlocProvider(
          create: (_) => LinkBloc(linkRepository: linkRepo),
        ),
        BlocProvider(
          create: (_) => ExploreBloc(userRepository: context.read<UserRepository>()),
        ),
        BlocProvider(
          create: (_) => NoticeBloc(noticeRepository: NoticeRepository()),
        ),
      ],
      child: Builder(
        builder: (context) {
          _descendantContext = context;
          return Scaffold(
            backgroundColor: cs.surface,
            drawer: Drawer(
              backgroundColor: cs.surface,
              child: SafeArea(
                child: BlocBuilder<ProfileBloc, ProfileState>(
                  builder: (context, profileState) {
                    final user = profileState.currentUser;
                    return Column(
                      children: [
                        // ── Premium gradient header ──
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isDark
                                  ? [
                                      cs.primary.withValues(alpha: .2),
                                      cs.surface,
                                    ]
                                  : [
                                      cs.primary.withValues(alpha: .08),
                                      cs.surface,
                                    ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [cs.primary, cs.secondary],
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cs.surface,
                                  ),
                                  child: UserAvatar(
                                    username: user?.username ?? 'User',
                                    radius: 32,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                user?.username ?? 'User',
                                style: getBoldStyle(
                                  fontSize: 18,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (user?.bio != null)
                                Text(
                                  user!.bio!,
                                  style: getRegularStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: .5),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    '${user?.followersCount ?? 0}',
                                    style: getBoldStyle(
                                      fontSize: 14,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  Text(
                                    ' Followers',
                                    style: getRegularStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(alpha: .5),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    '${user?.followingCount ?? 0}',
                                    style: getBoldStyle(
                                      fontSize: 14,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  Text(
                                    ' Following',
                                    style: getRegularStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(alpha: .5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // ── Scrollable Menu Items ──
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: [
                                const SizedBox(height: 8),
                                ...List.generate(
                                  5,
                                  (i) => _Item(
                                    icon: _icons[i],
                                    label: _labels[i],
                                    active: _idx == i,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (i == 0) {
                                        final campaignState = context.read<CampaignBloc>().state;
                                        final hasAvailableCampaigns = campaignState.campaignStatus?.campaignsAvailable ?? false;
                                        if (hasAvailableCampaigns) {
                                          _showCampaignLockDialog(context);
                                          return;
                                        }
                                        context.read<FeedBloc>().add(const RefreshFeed());
                                        context.read<NoticeBloc>().add(const LoadNotices());
                                        setState(() => _idx = 0);
                                      } else if (i == 3) {
                                        context.read<ExploreBloc>().add(const RefreshExplore());
                                        setState(() => _idx = 3);
                                      } else {
                                        setIndex(i);
                                      }
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                  child: Divider(
                                    color: cs.onSurface.withValues(alpha: .06),
                                  ),
                                ),
                                _Item(
                                  icon: Icons.query_stats_rounded,
                                  label: 'Stats',
                                  active: false,
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.pushNamed(context, '/stats');
                                  },
                                ),
                                _Item(
                                  icon: Icons.settings_rounded,
                                  label: 'Settings',
                                  active: false,
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.pushNamed(context, '/settings');
                                  },
                                ),
                                // Admin panel — visible for admin and moderator users
                                if (user?.role == 'admin' ||
                                    user?.role == 'moderator')
                                  _Item(
                                    icon: Icons.admin_panel_settings_rounded,
                                    label: 'Admin Panel',
                                    active: false,
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.pushNamed(context, '/admin');
                                    },
                                  ),
                                // Admin only options
                                if (user?.role == 'admin') ...[
                                  _Item(
                                    icon: Icons.subscriptions_rounded,
                                    label: 'Manage Subscriptions',
                                    active: false,
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.pushNamed(
                                        context,
                                        '/admin/subscriptions',
                                      );
                                    },
                                  ),
                                  _Item(
                                    icon: Icons.account_balance_wallet_rounded,
                                    label: 'Finance',
                                    active: false,
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.pushNamed(
                                        context,
                                        '/admin/finance',
                                      );
                                    },
                                  ),
                                  _Item(
                                    icon: Icons.campaign_rounded,
                                    label: 'Manage Notices',
                                    active: false,
                                    onTap: () async {
                                      Navigator.pop(context);
                                      await Navigator.pushNamed(
                                        context,
                                        '/admin/notices',
                                      );
                                      if (context.mounted) {
                                        context.read<NoticeBloc>().add(
                                          const LoadNotices(),
                                        );
                                      }
                                    },
                                  ),
                                ],
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                        // Logout
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 12,
                            right: 12,
                            bottom: 12,
                          ),
                          child: Material(
                            color: cs.error.withValues(
                              alpha: isDark ? .1 : .06,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                await TokenStorage.instance.setManualLogout(
                                  true,
                                );
                                await TokenStorage.instance.clearAll();
                                if (context.mounted) {
                                  context.read<ProfileBloc>().add(
                                    const ClearProfile(),
                                  );
                                  Navigator.pop(context);
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    '/login',
                                    (_) => false,
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.logout_rounded,
                                      size: 22,
                                      color: cs.error,
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      'Log Out',
                                      style: getMediumStyle(
                                        fontSize: 14,
                                        color: cs.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Text(
                            'Ad Network v1.0.14',
                            style: getRegularStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: .25),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            body: SafeArea(
              top: false,
              bottom: false,
              left: false,
              right: false,
              child: ValueListenableBuilder<bool>(
                valueListenable: isPipModeNotifier,
                builder: (context, isPip, child) {
                  return Stack(
                    children: [
                      // Offstage keeps the feed screen, BLoC subscriptions, and AutoPlay engine
                      // alive in the background while in PIP mode.
                      Offstage(
                        offstage: isPip,
                        child: SafeArea(
                          child: Column(
                            children: [
                              // Main content
                              Expanded(
                                child: IndexedStack(
                                  index: _idx,
                                  children: pages,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: LinkQueueOverlay(
                          key: const ValueKey('active_link_queue_overlay'),
                          isPipMode: isPip,
                          onPauseAutoPlay: () {
                            LinkQueueManager.instance.requestPauseAutoPlay();
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Item({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: active ? cs.primary.withValues(alpha: .1) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: .55),
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: getMediumStyle(
                    fontSize: 14,
                    color: active
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: .75),
                  ),
                ),
                if (active) ...[
                  const Spacer(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
