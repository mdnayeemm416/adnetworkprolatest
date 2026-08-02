import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/layers/data/model/user_model.dart';
import 'package:adnetwork/layers/data/repo/remote/admin_repository.dart';
import 'package:adnetwork/layers/presentation/controller/admin/admin_bloc.dart';
import 'package:adnetwork/layers/presentation/widget/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AdminSubscriptionsScreen extends StatelessWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          AdminBloc(adminRepository: AdminRepository())
            ..add(const LoadAllUsers()),
      child: const _AdminSubscriptionsScreenBody(),
    );
  }
}

enum SubscriptionTab {
  all,
  nonSubscribe,
  subscribe,
  free,
}

class _TabItem {
  final SubscriptionTab type;
  final String label;
  final IconData icon;

  const _TabItem(this.type, this.label, this.icon);
}

class _AdminSubscriptionsScreenBody extends StatefulWidget {
  const _AdminSubscriptionsScreenBody();

  @override
  State<_AdminSubscriptionsScreenBody> createState() =>
      _AdminSubscriptionsScreenBodyState();
}

class _AdminSubscriptionsScreenBodyState
    extends State<_AdminSubscriptionsScreenBody> {
  SubscriptionTab _selectedTab = SubscriptionTab.all;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<AdminBloc, AdminState>(
      listenWhen: (prev, curr) =>
          prev.successMessage != curr.successMessage ||
          prev.errorMessage != curr.errorMessage,
      listener: (context, state) {
        if (state.successMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage),
              backgroundColor: cs.secondary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          context.read<AdminBloc>().add(const ClearMessages());
        }
        if (state.errorMessage.isNotEmpty &&
            state.status == AdminStatus.loaded) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E2E) : cs.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: cs.error.withValues(alpha: .2)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: .1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.error_outline_rounded, color: cs.error, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Operation Failed',
                    style: getBoldStyle(fontSize: 16, color: cs.onSurface),
                  ),
                ],
              ),
              content: Text(
                state.errorMessage,
                style: getRegularStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .8)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: getBoldStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          );
          context.read<AdminBloc>().add(const ClearMessages());
        }
      },
      builder: (context, state) {
        final filteredUsers = state.allUsers.where((u) {
          // 1. Tab filter
          switch (_selectedTab) {
            case SubscriptionTab.all:
              break;
            case SubscriptionTab.nonSubscribe:
              if (u.autolike == 1) return false;
              break;
            case SubscriptionTab.subscribe:
              if (u.autolike != 1) return false;
              break;
            case SubscriptionTab.free:
              if (u.isFreeSubscription != 1 && u.role != 'admin' && u.role != 'moderator') return false;
              break;
          }

          // 2. Search filter
          if (state.searchQuery.isEmpty) return true;
          final q = state.searchQuery.toLowerCase();
          final n = u.username?.toLowerCase() ?? '';
          final e = u.email?.toLowerCase() ?? '';
          return n.contains(q) || e.contains(q);
        }).toList();

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.secondary],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.subscriptions_rounded,
                    size: 18,
                    color: cs.onPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Manage Subscriptions',
                  style: getBoldStyle(fontSize: 18, color: cs.onSurface),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),

                // ── 5 Filtering Tabs ──
                _buildTabs(context, cs, isDark),
                const SizedBox(height: 12),

                // ── Search Bar ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? cs.onSurface.withValues(alpha: .05)
                          : cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: isDark ? .1 : .06),
                      ),
                    ),
                    child: TextField(
                      onChanged: (v) =>
                          context.read<AdminBloc>().add(SearchUsers(v)),
                      decoration: InputDecoration(
                        hintText: 'Search by name or email...',
                        hintStyle: getRegularStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: .35),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: cs.primary.withValues(alpha: .5),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Statistics Dashboard ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [cs.primary.withValues(alpha: .15), cs.secondary.withValues(alpha: .05)]
                            : [cs.primary.withValues(alpha: .05), cs.secondary.withValues(alpha: .02)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: isDark ? .2 : .1),
                        width: 1,
                      ),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(
                            color: cs.primary.withValues(alpha: .03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          context,
                          title: 'Total Users',
                          value: '${state.allUsers.length}',
                          icon: Icons.people_rounded,
                          color: cs.primary,
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: cs.onSurface.withValues(alpha: .1),
                        ),
                        _buildStatItem(
                          context,
                          title: 'Subscribed',
                          value: '${state.allUsers.where((u) => u.autolike == 1).length}',
                          icon: Icons.thumb_up_alt_rounded,
                          color: cs.secondary,
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: cs.onSurface.withValues(alpha: .1),
                        ),
                        _buildStatItem(
                          context,
                          title: 'Filtered',
                          value: '${filteredUsers.length}',
                          icon: Icons.filter_list_rounded,
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Expanded(child: _buildContent(context, state, filteredUsers, cs, isDark)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabs(BuildContext context, ColorScheme cs, bool isDark) {
    final tabs = [
      _TabItem(SubscriptionTab.all, 'All', Icons.people_outline_rounded),
      _TabItem(
        SubscriptionTab.nonSubscribe,
        'Non Subscribe',
        Icons.unsubscribe_outlined,
      ),
      _TabItem(
        SubscriptionTab.subscribe,
        'Subscribe',
        Icons.thumb_up_alt_outlined,
      ),
      _TabItem(SubscriptionTab.free, 'Free', Icons.card_giftcard_rounded),
    ];

    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isSelected = _selectedTab == tab.type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedTab = tab.type;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              cs.primary,
                              cs.primary.withValues(alpha: 0.85),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isSelected
                        ? null
                        : (isDark
                            ? cs.onSurface.withValues(alpha: .04)
                            : cs.primaryContainer),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : cs.primary.withValues(
                              alpha: isDark ? .12 : .08,
                            ),
                    ),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: cs.primary.withValues(alpha: .25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab.icon,
                        size: 16,
                        color: isSelected
                            ? cs.onPrimary
                            : cs.onSurface.withValues(alpha: .6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab.label,
                        style: getMediumStyle(
                          fontSize: 12,
                          color: isSelected
                              ? cs.onPrimary
                              : cs.onSurface.withValues(alpha: .75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AdminState state,
    List<UserModel> users,
    ColorScheme cs,
    bool isDark,
  ) {
    if (state.status == AdminStatus.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Loading users...',
              style: getRegularStyle(
                fontSize: 14,
                color: cs.onSurface.withValues(alpha: .5),
              ),
            ),
          ],
        ),
      );
    }

    if (state.status == AdminStatus.error && state.allUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: cs.error.withValues(alpha: .6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load users',
              style: getMediumStyle(
                fontSize: 16,
                color: cs.onSurface.withValues(alpha: .6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.errorMessage,
              style: getRegularStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: .4),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () =>
                  context.read<AdminBloc>().add(const LoadAllUsers()),
              icon: Icon(Icons.refresh_rounded, color: cs.primary),
              label: Text(
                'Retry',
                style: getMediumStyle(fontSize: 14, color: cs.primary),
              ),
            ),
          ],
        ),
      );
    }

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: .06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_off_rounded,
                size: 48,
                color: cs.primary.withValues(alpha: .4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              state.searchQuery.isNotEmpty
                  ? 'No matching users'
                  : 'No users available',
              style: getMediumStyle(
                fontSize: 16,
                color: cs.onSurface.withValues(alpha: .5),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<AdminBloc>().add(const LoadAllUsers());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return TweenAnimationBuilder<double>(
            key: ValueKey(user.id),
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300 + (index * 40).clamp(0, 300)),
            curve: Curves.easeOutCubic,
            builder: (ctx, val, child) => Opacity(
              opacity: val,
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - val)),
                child: child,
              ),
            ),
            child: _UserManagementCard(
              user: user,
              state: state,
              cs: cs,
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  USER MANAGEMENT CARD
// ══════════════════════════════════════════════════════════
class _UserManagementCard extends StatelessWidget {
  final UserModel user;
  final AdminState state;
  final ColorScheme cs;
  final bool isDark;

  const _UserManagementCard({
    required this.user,
    required this.state,
    required this.cs,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = state.actionUserId == user.id;
    final isBlocked = user.isBlocked == 1;
    final isAdmin = user.role == 'admin';
    final isAutoLikeEnabled = user.autolike == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark
            ? cs.onSurface.withValues(alpha: .04)
            : cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAutoLikeEnabled
              ? cs.primary.withValues(alpha: .2)
              : cs.onSurface.withValues(alpha: .05),
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
      child: Column(
        children: [
          // ── User Info Row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                // Avatar with status ring
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isBlocked
                              ? cs.error
                              : isAdmin
                              ? cs.secondary
                              : cs.primary,
                          width: 2,
                        ),
                      ),
                      child: UserAvatar(
                        username: user.username ?? '',
                        radius: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Name, email, meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.username ?? 'Unknown',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: getSemiBoldStyle(
                                fontSize: 14,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusBadge(user: user, cs: cs),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: getRegularStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: .45),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.subscriptions_rounded,
                            size: 11,
                            color: isAutoLikeEnabled
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: .3),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isAutoLikeEnabled
                                ? 'Auto-Like Enabled'
                                : 'Auto-Like Disabled',
                            style: getMediumStyle(
                              fontSize: 10,
                              color: isAutoLikeEnabled
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: .35),
                            ),
                          ),
                        ],
                      ),
                      if (user.subscriptionStartedAt != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 11,
                              color: cs.onSurface.withValues(alpha: .3),
                            ),
                            const SizedBox(width: 4),
                            Builder(
                              builder: (context) {
                                final expiryDate = user.subscriptionStartedAt!.add(const Duration(days: 30));
                                final difference = expiryDate.difference(DateTime.now());
                                final daysRemaining = (difference.inSeconds / 86400).ceil();
                                final hasExpired = difference.isNegative || daysRemaining <= 0;
                                return Text(
                                  hasExpired ? 'Expired' : '$daysRemaining days remaining',
                                  style: getMediumStyle(
                                    fontSize: 10,
                                    color: hasExpired
                                        ? cs.error
                                        : cs.primary,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Loading indicator or expand
                if (isLoading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: cs.primary,
                    ),
                  )
                else
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: cs.onSurface.withValues(alpha: .4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    color: isDark ? const Color(0xFF2A2A3A) : cs.surface,
                    elevation: 8,
                    onSelected: (val) => _handleAction(context, val),
                    itemBuilder: (_) => _buildMenuItems(cs),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, String action) {
    final bloc = context.read<AdminBloc>();
    final id = user.id ?? '';
    switch (action) {
      case 'enable-autolike':
        showDialog(
          context: context,
          builder: (ctx) => _UserSubConfigDialog(
            userId: id,
            username: user.username ?? '',
            bloc: bloc,
          ),
        );
        break;
      case 'disable-autolike':
        bloc.add(UpdateSubscription(id, 0));
        break;
    }
  }

  List<PopupMenuEntry<String>> _buildMenuItems(ColorScheme cs) {
    final items = <PopupMenuEntry<String>>[];

    if (user.autolike == 1) {
      items.add(
        _menuItem(
          'disable-autolike',
          Icons.subscriptions_outlined,
          'Disable Auto-Like',
          cs.error,
        ),
      );
    } else {
      items.add(
        _menuItem(
          'enable-autolike',
          Icons.subscriptions_rounded,
          'Enable Auto-Like',
          cs.primary,
        ),
      );
    }

    return items;
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: getMediumStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  STATUS BADGE
// ══════════════════════════════════════════════════════════
class _StatusBadge extends StatelessWidget {
  final UserModel user;
  final ColorScheme cs;

  const _StatusBadge({required this.user, required this.cs});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;

    if (user.isBlocked == 1) {
      label = 'Blocked';
      color = cs.error;
    } else if (user.isApproved == 0) {
      label = 'Pending';
      color = cs.tertiary;
    } else if (user.role == 'admin') {
      label = 'Admin';
      color = cs.secondary;
    } else if (user.role == 'moderator') {
      label = 'Moderator';
      color = Colors.orange;
    } else {
      label = 'Active';
      color = cs.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(label, style: getMediumStyle(fontSize: 9, color: color)),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  STATISTICS ITEM WIDGET
// ══════════════════════════════════════════════════════════
Widget _buildStatItem(
  BuildContext context, {
  required String title,
  required String value,
  required IconData icon,
  required Color color,
}) {
  final cs = Theme.of(context).colorScheme;
  return Column(
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: getBoldStyle(fontSize: 16, color: cs.onSurface),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        title,
        style: getRegularStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .5)),
      ),
    ],
  );
}

// ══════════════════════════════════════════════════════════
//  USER SUB CONFIGURATION DIALOG
// ══════════════════════════════════════════════════════════
class _UserSubConfigDialog extends StatefulWidget {
  final String userId;
  final String username;
  final AdminBloc bloc;

  const _UserSubConfigDialog({
    required this.userId,
    required this.username,
    required this.bloc,
  });

  @override
  State<_UserSubConfigDialog> createState() => _UserSubConfigDialogState();
}

class _UserSubConfigDialogState extends State<_UserSubConfigDialog> {
  bool _isFree = false;
  String _selectedMethod = 'bkash';
  final _customMethodCtrl = TextEditingController();
  final _txidCtrl = TextEditingController();

  final List<String> _paymentMethods = [
    'bkash',
    'nagad',
    'roket',
    'upay',
    'cash',
    'free',
    'other'
  ];

  @override
  void dispose() {
    _customMethodCtrl.dispose();
    _txidCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Configure Subscription',
        style: getBoldStyle(fontSize: 18, color: cs.onSurface),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configure subscription options for ${widget.username}',
              style: getRegularStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .5)),
            ),
            const SizedBox(height: 16),

            // Free Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Free Subscription',
                  style: getBoldStyle(fontSize: 14, color: cs.onSurface),
                ),
                Switch(
                  value: _isFree,
                  activeColor: cs.primary,
                  onChanged: (val) {
                    setState(() {
                      _isFree = val;
                      if (val) {
                        _selectedMethod = 'free';
                      } else {
                        _selectedMethod = 'bkash';
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Payment Method selector
            Text(
              'Payment Method',
              style: getBoldStyle(fontSize: 13, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? cs.onSurface.withValues(alpha: .04) : cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.onSurface.withValues(alpha: .05)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMethod,
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF2A2A3A) : cs.surface,
                  items: _paymentMethods.map((m) {
                    return DropdownMenuItem<String>(
                      value: m,
                      child: Text(
                        m.toUpperCase(),
                        style: getBoldStyle(fontSize: 13, color: cs.onSurface),
                      ),
                    );
                  }).toList(),
                  onChanged: _isFree
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _selectedMethod = val);
                          }
                        },
                ),
              ),
            ),

            if (_selectedMethod == 'other') ...[
              const SizedBox(height: 12),
              Text(
                'Specify Payment Method',
                style: getBoldStyle(fontSize: 12, color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? cs.onSurface.withValues(alpha: .04) : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.onSurface.withValues(alpha: .05)),
                ),
                child: TextField(
                  controller: _customMethodCtrl,
                  style: getMediumStyle(fontSize: 13, color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: 'e.g. Bank Transfer',
                    hintStyle: getRegularStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .35)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),
            Text(
              'Transaction ID (TxID) *',
              style: getBoldStyle(fontSize: 13, color: cs.onSurface),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: isDark ? cs.onSurface.withValues(alpha: .04) : cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.onSurface.withValues(alpha: .05)),
              ),
              child: TextField(
                controller: _txidCtrl,
                style: getMediumStyle(fontSize: 13, color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'Enter Transaction ID',
                  hintStyle: getRegularStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .35)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: getBoldStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: .5))),
        ),
        ElevatedButton(
          onPressed: () {
            final txid = _txidCtrl.text.trim();
            if (txid.isEmpty) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: isDark ? const Color(0xFF1E1E2E) : cs.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: cs.error.withValues(alpha: .2)),
                  ),
                  title: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: cs.error),
                      const SizedBox(width: 8),
                      Text('Validation Error', style: getBoldStyle(fontSize: 16, color: cs.onSurface)),
                    ],
                  ),
                  content: Text(
                    'Transaction ID (TxID) is compulsory to enable auto-like.',
                    style: getRegularStyle(fontSize: 13, color: cs.onSurface),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('OK', style: getBoldStyle(fontSize: 13, color: cs.primary)),
                    ),
                  ],
                ),
              );
              return;
            }

            final method = _selectedMethod == 'other'
                ? _customMethodCtrl.text.trim()
                : _selectedMethod;

            widget.bloc.add(
              UpdateSubscription(
                widget.userId,
                1,
                isFree: _isFree ? 1 : 0,
                paymentMethod: method.isEmpty ? 'other' : method,
                txid: txid,
              ),
            );
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Enable', style: getBoldStyle(fontSize: 14, color: Colors.white)),
        ),
      ],
    );
  }
}

