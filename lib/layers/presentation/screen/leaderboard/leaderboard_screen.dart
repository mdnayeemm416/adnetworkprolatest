import 'dart:ui';
import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/layers/data/model/leaderboard_model.dart';
import 'package:adnetwork/layers/data/repo/remote/leaderboard_repository.dart';
import 'package:adnetwork/layers/presentation/widget/adsterra_api_key_dialog.dart';
import 'package:adnetwork/layers/presentation/widget/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum LeaderboardCategory { ecpm, revenue, impressions }

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final LeaderboardRepository _repo = LeaderboardRepository();

  bool _isLoading = true;
  String? _error;
  HourlyLeaderboardResponse? _data;
  LeaderboardCategory _selectedCategory = LeaderboardCategory.ecpm;

  DateTime _selectedDate = DateTime.now().toUtc();
  int _selectedHour = DateTime.now().toUtc().hour;

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final res = await _repo.getHourlyLeaderboard(
        date: dateStr,
        hour: _selectedHour,
      );

      if (mounted) {
        if (res.isSuccess && res.data != null) {
          setState(() {
            _data = res.data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = res.message ?? 'Failed to load leaderboard';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error connecting to leaderboard: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _shiftHour(int delta) {
    var newTime = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedHour,
    ).add(Duration(hours: delta));

    final nowUtc = DateTime.now().toUtc();
    if (newTime.isAfter(nowUtc)) {
      newTime = nowUtc;
    }

    setState(() {
      _selectedDate = newTime;
      _selectedHour = newTime.hour;
    });

    _fetchLeaderboard();
  }

  List<LeaderboardEntry> _getActiveList() {
    if (_data == null) return [];
    switch (_selectedCategory) {
      case LeaderboardCategory.ecpm:
        return _data!.ecpmLeaderboard;
      case LeaderboardCategory.revenue:
        return _data!.revenueLeaderboard;
      case LeaderboardCategory.impressions:
        return _data!.impressionsLeaderboard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColors = isDark
        ? [const Color(0xFF0C0E17), const Color(0xFF121524), const Color(0xFF0A0C14)]
        : [const Color(0xFFF7F9FD), const Color(0xFFEDF2F9), Colors.white];

    final activeList = _getActiveList();
    final topThree = activeList.take(3).toList();
    final restList = activeList.length > 3 ? activeList.sublist(3) : <LeaderboardEntry>[];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              backgroundColor: (isDark ? const Color(0xFF0C0E17) : Colors.white).withValues(alpha: 0.8),
              elevation: 0,
              centerTitle: false,
              titleSpacing: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: cs.onSurface),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB300), Color(0xFFFF5252)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB300).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hourly Leaderboard',
                        style: getBoldStyle(fontSize: 17, color: cs.onSurface),
                      ),
                      Text(
                        'Adsterra Publisher Rankings',
                        style: getRegularStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Refresh',
                  onPressed: _fetchLeaderboard,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: bgColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Hour Navigator Bar ──
              _buildHourNavigator(cs, isDark),

              // ── 3-Way Category Segmented Tabs ──
              _buildCategoryTabs(cs, isDark),

              // ── Main Content Area ──
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00ADB5)))
                    : _error != null
                        ? _buildErrorView(cs)
                        : RefreshIndicator(
                            color: const Color(0xFF00ADB5),
                            onRefresh: _fetchLeaderboard,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Network Summary Bar
                                  if (_data != null) _buildSummaryBar(_data!.summary, cs, isDark),
                                  const SizedBox(height: 18),

                                  if (activeList.isEmpty)
                                    _buildEmptyState(cs, isDark)
                                  else ...[
                                    // Top 3 Podium
                                    if (topThree.isNotEmpty) _buildTopThreePodium(topThree, cs, isDark),
                                    const SizedBox(height: 20),

                                    // Rank 4+ List
                                    if (restList.isNotEmpty) ...[
                                      Text(
                                        'All Publishers (${activeList.length})',
                                        style: getBoldStyle(fontSize: 14, color: cs.onSurface),
                                      ),
                                      const SizedBox(height: 10),
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: restList.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                                        itemBuilder: (context, idx) {
                                          return _buildLeaderboardTile(restList[idx], cs, isDark);
                                        },
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
              ),

              // ── Sticky Current User Rank Bar (if available) ──
              if (_data != null && _data!.currentUser != null)
                _buildCurrentUserStickyBar(_data!.currentUser!, cs, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hour Selector ──
  Widget _buildHourNavigator(ColorScheme cs, bool isDark) {
    final label = _data?.hourLabel ?? '$_selectedHour:00 - ${_selectedHour + 1}:00 UTC';
    final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141726) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            onPressed: () => _shiftHour(-1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF00E676),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: getBoldStyle(fontSize: 13, color: cs.onSurface),
                  ),
                ],
              ),
              Text(
                dateStr,
                style: getRegularStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
            onPressed: () => _shiftHour(1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ── Category Tabs ──
  Widget _buildCategoryTabs(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _buildCategoryTabItem(
            category: LeaderboardCategory.ecpm,
            title: 'Top eCPM',
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF00ADB5),
            cs: cs,
          ),
          const SizedBox(width: 8),
          _buildCategoryTabItem(
            category: LeaderboardCategory.revenue,
            title: 'Top Revenue',
            icon: Icons.monetization_on_rounded,
            color: const Color(0xFF00E676),
            cs: cs,
          ),
          const SizedBox(width: 8),
          _buildCategoryTabItem(
            category: LeaderboardCategory.impressions,
            title: 'Top Views',
            icon: Icons.visibility_rounded,
            color: const Color(0xFF6C5CE7),
            cs: cs,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabItem({
    required LeaderboardCategory category,
    required String title,
    required IconData icon,
    required Color color,
    required ColorScheme cs,
  }) {
    final isSelected = _selectedCategory == category;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = category),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.16) : cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : cs.onSurface.withValues(alpha: 0.08),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isSelected ? color : cs.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 5),
              Text(
                title,
                style: getBoldStyle(
                  fontSize: 12,
                  color: isSelected ? color : cs.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Network Summary ──
  Widget _buildSummaryBar(LeaderboardSummary summary, ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141726) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Total Revenue', '\$${summary.totalRevenue.toStringAsFixed(2)}', cs),
          _buildSummaryItem('Impressions', NumberFormat.compact().format(summary.totalImpressions), cs),
          _buildSummaryItem('Clicks', NumberFormat.compact().format(summary.totalClicks), cs),
          _buildSummaryItem('Avg eCPM', '\$${summary.avgEcpm.toStringAsFixed(2)}', cs),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, ColorScheme cs) {
    return Column(
      children: [
        Text(
          label,
          style: getRegularStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: getBoldStyle(fontSize: 13, color: cs.onSurface),
        ),
      ],
    );
  }

  // ── Top 3 Podium ──
  Widget _buildTopThreePodium(List<LeaderboardEntry> topThree, ColorScheme cs, bool isDark) {
    final LeaderboardEntry first = topThree[0];
    final LeaderboardEntry? second = topThree.length > 1 ? topThree[1] : null;
    final LeaderboardEntry? third = topThree.length > 2 ? topThree[2] : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF181C2E), const Color(0xFF121422)]
              : [Colors.white, const Color(0xFFF7F8FC)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd Place
          if (second != null)
            Expanded(child: _buildPodiumColumn(second, 2, const Color(0xFFB0BEC5), 115, cs, isDark))
          else
            const Spacer(),

          // 1st Place
          Expanded(child: _buildPodiumColumn(first, 1, const Color(0xFFFFB300), 140, cs, isDark)),

          // 3rd Place
          if (third != null)
            Expanded(child: _buildPodiumColumn(third, 3, const Color(0xFFCD7F32), 100, cs, isDark))
          else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPodiumColumn(
    LeaderboardEntry entry,
    int rank,
    Color medalColor,
    double height,
    ColorScheme cs,
    bool isDark,
  ) {
    String metricValue = '';
    switch (_selectedCategory) {
      case LeaderboardCategory.ecpm:
        metricValue = '\$${entry.ecpm.toStringAsFixed(2)} eCPM';
        break;
      case LeaderboardCategory.revenue:
        metricValue = '\$${entry.revenue.toStringAsFixed(2)}';
        break;
      case LeaderboardCategory.impressions:
        metricValue = '${NumberFormat.compact().format(entry.impressions)} Imp';
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Crown for 1st
        if (rank == 1)
          const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFB300), size: 24),
        const SizedBox(height: 2),

        // Avatar with medal border
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: medalColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: medalColor.withValues(alpha: 0.25),
                blurRadius: 8,
              ),
            ],
          ),
          child: UserAvatar(
            username: entry.username,
            radius: rank == 1 ? 26 : 22,
          ),
        ),
        const SizedBox(height: 6),

        Text(
          entry.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: getBoldStyle(fontSize: 12, color: cs.onSurface),
        ),
        Text(
          metricValue,
          style: getBoldStyle(fontSize: 11, color: medalColor),
        ),
        const SizedBox(height: 8),

        // Stepped Podium Base
        Container(
          height: rank == 1 ? 48 : (rank == 2 ? 36 : 28),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: medalColor.withValues(alpha: isDark ? 0.16 : 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: medalColor.withValues(alpha: 0.35)),
          ),
          child: Text(
            '#$rank',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: medalColor,
            ),
          ),
        ),
      ],
    );
  }

  // ── Rank 4+ Tile ──
  Widget _buildLeaderboardTile(LeaderboardEntry entry, ColorScheme cs, bool isDark) {
    String primaryMetric = '';
    String subMetric = '';

    switch (_selectedCategory) {
      case LeaderboardCategory.ecpm:
        primaryMetric = '\$${entry.ecpm.toStringAsFixed(2)} eCPM';
        subMetric = '\$${entry.revenue.toStringAsFixed(2)} rev • ${entry.impressions} views';
        break;
      case LeaderboardCategory.revenue:
        primaryMetric = '\$${entry.revenue.toStringAsFixed(2)}';
        subMetric = '\$${entry.ecpm.toStringAsFixed(2)} eCPM • ${entry.impressions} views';
        break;
      case LeaderboardCategory.impressions:
        primaryMetric = '${NumberFormat.compact().format(entry.impressions)} Views';
        subMetric = '\$${entry.revenue.toStringAsFixed(2)} rev • \$${entry.ecpm.toStringAsFixed(2)} eCPM';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141726) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${entry.rank}',
              style: getBoldStyle(fontSize: 12, color: cs.primary),
            ),
          ),
          const SizedBox(width: 12),

          UserAvatar(username: entry.username, radius: 18),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: getBoldStyle(fontSize: 13, color: cs.onSurface),
                ),
                Text(
                  subMetric,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: getRegularStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          Text(
            primaryMetric,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF00ADB5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Current User Sticky Bottom Bar ──
  Widget _buildCurrentUserStickyBar(
    CurrentUserLeaderboardStatus userStatus,
    ColorScheme cs,
    bool isDark,
  ) {
    if (!userStatus.hasKey) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141724) : Colors.white,
          border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.1))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Connect your Adsterra API Key to view your live rank!',
                style: getRegularStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () {
                AdsterraApiKeyDialog.show(
                  context,
                  isDismissible: true,
                  onSuccess: _fetchLeaderboard,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00ADB5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: const Text('Connect Key'),
            ),
          ],
        ),
      );
    }

    CurrentUserRankDetail? rankDetail;
    String label = '';
    switch (_selectedCategory) {
      case LeaderboardCategory.ecpm:
        rankDetail = userStatus.ecpm;
        label = 'eCPM Rank';
        break;
      case LeaderboardCategory.revenue:
        rankDetail = userStatus.revenue;
        label = 'Revenue Rank';
        break;
      case LeaderboardCategory.impressions:
        rankDetail = userStatus.impressions;
        label = 'Views Rank';
        break;
    }

    final rank = rankDetail?.rank ?? 0;
    final val = rankDetail?.value ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141828) : Colors.white,
        border: Border(
          top: BorderSide(color: const Color(0xFF00ADB5).withValues(alpha: 0.3), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00ADB5).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF00ADB5), Color(0xFF6C5CE7)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_pin_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Your Status',
                        style: getBoldStyle(fontSize: 13, color: cs.onSurface),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF00E676),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$label: ${rank > 0 ? '#$rank' : 'Unranked'}',
                    style: getBoldStyle(fontSize: 12, color: const Color(0xFF00ADB5)),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _selectedCategory == LeaderboardCategory.impressions
                  ? '${val.toInt()} Views'
                  : '\$${val.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFF69F0AE) : const Color(0xFF00A352),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.leaderboard_outlined, size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'No stats recorded for this hour yet',
            style: getBoldStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 4),
          Text(
            'Use the arrows above to browse previous hours',
            style: getRegularStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, color: cs.error, size: 40),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: getRegularStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchLeaderboard,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00ADB5),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
