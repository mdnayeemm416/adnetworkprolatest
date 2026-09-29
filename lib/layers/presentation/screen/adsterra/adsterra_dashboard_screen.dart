import 'dart:ui';
import 'package:adnetwork/config/theme/routes_config.dart';
import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/core/services/adsterra_storage.dart';
import 'package:adnetwork/layers/data/model/adsterra_models.dart';
import 'package:adnetwork/layers/data/model/adsterra_payout_calculator.dart';
import 'package:adnetwork/layers/data/repo/remote/adsterra_repository.dart';
import 'package:adnetwork/layers/presentation/widget/adsterra_api_key_dialog.dart';
import 'package:adnetwork/layers/presentation/widget/show_toast.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

enum StatFilter { today, yesterday, last7Days, thisMonth }

class AdsterraDashboardScreen extends StatefulWidget {
  const AdsterraDashboardScreen({super.key});

  @override
  State<AdsterraDashboardScreen> createState() =>
      _AdsterraDashboardScreenState();
}

class _AdsterraDashboardScreenState extends State<AdsterraDashboardScreen>
    with SingleTickerProviderStateMixin {
  final AdsterraRepository _repo = AdsterraRepository();

  bool _isLoading = true;
  String? _error;
  String? _apiKey;

  AdsterraBalanceModel? _balance;
  List<AdsterraStatItem> _stats = [];
  PayoutEstimate? _payoutEstimate;

  StatFilter _selectedFilter = StatFilter.thisMonth;
  DateTime? _lastSyncDate;
  int _lastSyncCount = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final key = await AdsterraStorage.instance.getApiKey();
    _apiKey = key;
    _lastSyncDate = await AdsterraStorage.instance.getLastSyncDate();
    _lastSyncCount = await AdsterraStorage.instance.getLastSyncCount();

    if (key == null || key.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'No Adsterra API Key configured.';
      });
      return;
    }

    try {
      final now = DateTime.now();
      final DateFormat apiFmt = DateFormat('yyyy-MM-dd');

      // 1. Fetch 30-day balance
      final balanceFuture = _repo
          .getBalance(key)
          .catchError((_) => AdsterraBalanceModel(balance: 0.0));

      // 2. Stats for last 30 days
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final recentStatsFuture = _repo
          .getStats(
            key,
            startDate: apiFmt.format(thirtyDaysAgo),
            finishDate: apiFmt.format(now),
          )
          .catchError((_) => <AdsterraStatItem>[]);

      // 3. Previous month stats (for payout forecast)
      final prevMonthStart = DateTime(now.year, now.month - 1, 1);
      final prevMonthEnd = DateTime(now.year, now.month, 0);
      final prevMonthStatsFuture = _repo
          .getStats(
            key,
            startDate: apiFmt.format(prevMonthStart),
            finishDate: apiFmt.format(prevMonthEnd),
          )
          .catchError((_) => <AdsterraStatItem>[]);

      final results = await Future.wait([
        balanceFuture,
        recentStatsFuture,
        prevMonthStatsFuture,
      ]);

      final balance = results[0] as AdsterraBalanceModel;
      final recentStats = results[1] as List<AdsterraStatItem>;
      final prevStats = results[2] as List<AdsterraStatItem>;

      final curMonthStats = recentStats.where((s) {
        if (s.date == null) return false;
        final d = DateTime.tryParse(s.date!);
        return d != null && d.year == now.year && d.month == now.month;
      }).toList();

      final payout = AdsterraPayoutCalculator.calculate(
        currentMonthItems: curMonthStats,
        prevMonthItems: prevStats,
        now: now,
      );

      if (mounted) {
        setState(() {
          _balance = balance;
          _stats = recentStats;
          _payoutEstimate = payout;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load Adsterra data: $e';
        });
      }
    }
  }

  void _openKeySetupDialog() {
    AdsterraApiKeyDialog.show(
      context,
      isDismissible: true,
      onSuccess: () {
        showToast(
          context: context,
          message: 'Smartlinks synced successfully!',
          toastificationType: ToastificationType.success,
        );
        _loadData();
      },
    );
  }

  Map<String, num> _computeFilteredStats() {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(
      now.subtract(const Duration(days: 1)),
    );
    final last7DaysStart = now.subtract(const Duration(days: 7));

    List<AdsterraStatItem> filtered = [];

    switch (_selectedFilter) {
      case StatFilter.today:
        filtered = _stats.where((s) => s.date == todayStr).toList();
        break;
      case StatFilter.yesterday:
        filtered = _stats.where((s) => s.date == yesterdayStr).toList();
        break;
      case StatFilter.last7Days:
        filtered = _stats.where((s) {
          if (s.date == null) return false;
          final d = DateTime.tryParse(s.date!);
          return d != null && d.isAfter(last7DaysStart);
        }).toList();
        break;
      case StatFilter.thisMonth:
        filtered = _stats.where((s) {
          if (s.date == null) return false;
          final d = DateTime.tryParse(s.date!);
          return d != null && d.year == now.year && d.month == now.month;
        }).toList();
        break;
    }

    int impressions = 0;
    int clicks = 0;
    double revenue = 0.0;

    for (final item in filtered) {
      impressions += item.impressions;
      clicks += item.clicks;
      revenue += item.revenue;
    }

    final double cpm = impressions > 0 ? (revenue / impressions) * 1000 : 0.0;

    return {
      'impressions': impressions,
      'clicks': clicks,
      'revenue': revenue,
      'cpm': cpm,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgGradientColors = isDark
        ? [
            const Color(0xFF0D0F18),
            const Color(0xFF131726),
            const Color(0xFF090A10),
          ]
        : [
            const Color(0xFFF6F8FC),
            const Color(0xFFEDF2F9),
            const Color(0xFFFFFFFF),
          ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              backgroundColor: (isDark ? const Color(0xFF0D0F18) : Colors.white)
                  .withValues(alpha: 0.75),
              elevation: 0,
              centerTitle: false,
              titleSpacing: 0,
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 19,
                  color: cs.onSurface,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00ADB5), Color(0xFF6C5CE7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00ADB5).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Adsterra Publisher',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: getBoldStyle(fontSize: 16, color: cs.onSurface),
                        ),
                        Text(
                          'Traffic Analytics',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: getRegularStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                _buildAppBarActionBtn(
                  icon: Icons.emoji_events_rounded,
                  tooltip: 'Leaderboard',
                  onTap: () => Navigator.pushNamed(context, Routes.leaderboard),
                  isDark: isDark,
                  cs: cs,
                ),
                const SizedBox(width: 6),
                _buildAppBarActionBtn(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh Stats',
                  onTap: _loadData,
                  isDark: isDark,
                  cs: cs,
                ),
                const SizedBox(width: 6),
                _buildAppBarActionBtn(
                  icon: Icons.vpn_key_rounded,
                  tooltip: 'Update Token',
                  onTap: _openKeySetupDialog,
                  isDark: isDark,
                  cs: cs,
                  highlight: true,
                ),
                const SizedBox(width: 12),
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
            colors: bgGradientColors,
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? _buildLoadingState(cs)
              : _error != null
                  ? _buildErrorView(cs)
                  : RefreshIndicator(
                      color: const Color(0xFF00ADB5),
                      onRefresh: _loadData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Hero Balance Card ──
                            _buildHeroBalanceCard(cs, isDark),
                            const SizedBox(height: 20),

                            // ── Net-15 Payout Forecast Card ──
                            if (_payoutEstimate != null) ...[
                              _buildPayoutCard(cs, isDark),
                              const SizedBox(height: 22),
                            ],

                            // ── Interactive Performance Section ──
                            _buildPerformanceSection(cs, isDark),
                            const SizedBox(height: 24),

                            // ── Last 7 Days Chronological Breakdown ──
                            _buildLast7DaysStatsSection(cs, isDark),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildAppBarActionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
    required ColorScheme cs,
    bool highlight = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF00ADB5).withValues(alpha: 0.15)
            : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
        shape: BoxShape.circle,
        border: Border.all(
          color: highlight
              ? const Color(0xFF00ADB5).withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: 19,
          color: highlight ? const Color(0xFF00ADB5) : cs.onSurface,
        ),
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        padding: EdgeInsets.zero,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF00ADB5).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF00ADB5),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Syncing Adsterra Live Data...',
            style: getBoldStyle(
              fontSize: 15,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Calculating last 30 days balance & statistics',
            style: getRegularStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, color: cs.error, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'Connection Issue',
              style: getBoldStyle(fontSize: 18, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: getRegularStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openKeySetupDialog,
              icon: const Icon(Icons.vpn_key_rounded, size: 18),
              label: const Text('Setup Adsterra API Token'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00ADB5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 1. Hero Balance Card ──
  Widget _buildHeroBalanceCard(ColorScheme cs, bool isDark) {
    final balanceVal = _balance?.balance ?? 0.0;
    final currency = _balance?.currency ?? 'USD';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF161B2E),
                  const Color(0xFF0F1322),
                  const Color(0xFF1A1528),
                ]
              : [
                  Colors.white,
                  const Color(0xFFF1F5FB),
                  const Color(0xFFEBF0FA),
                ],
        ),
        border: Border.all(
          color: const Color(0xFF00ADB5).withValues(alpha: isDark ? 0.35 : 0.2),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00ADB5).withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle decorative top-right glow
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00ADB5).withValues(alpha: isDark ? 0.25 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Header & Live Pulsing Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00ADB5).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Color(0xFF00ADB5),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Publisher Balance',
                          style: getBoldStyle(
                            fontSize: 14,
                            color: cs.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                    FadeTransition(
                      opacity: _pulseAnimation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF00E676).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
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
                            const SizedBox(width: 5),
                            Text(
                              'LIVE SYNC',
                              style: getBoldStyle(
                                fontSize: 10,
                                color: const Color(0xFF00E676),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Large Main Balance Figure
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '\$${balanceVal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: cs.onSurface,
                        fontFamily: 'sans-serif',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        currency,
                        style: getBoldStyle(
                          fontSize: 12,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ── Bangla Helper Banner ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00ADB5).withValues(alpha: isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF00ADB5).withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.history_toggle_off_rounded,
                        size: 15,
                        color: Color(0xFF00ADB5),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'এটি আপনার বিগত ৩০ দিনের মোট উপার্জিত ব্যালেন্স',
                          style: getBoldStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF80ECEF) : const Color(0xFF00757B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                Divider(
                  height: 1,
                  color: cs.onSurface.withValues(alpha: 0.08),
                ),
                const SizedBox(height: 14),

                // Footer Row: Sync Info & Re-Sync Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.link_rounded,
                                size: 14,
                                color: const Color(0xFF00ADB5),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '$_lastSyncCount Smartlinks Active in Feed',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: getBoldStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          if (_apiKey != null && _apiKey!.length > 8)
                            Text(
                              'Key: ${_apiKey!.substring(0, 4)}••••${_apiKey!.substring(_apiKey!.length - 4)}'
                              '${_lastSyncDate != null ? ' • ${DateFormat('dd MMM, hh:mm a').format(_lastSyncDate!)}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: cs.onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _openKeySetupDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00ADB5), Color(0xFF0984E3)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00ADB5).withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.sync_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Re-Sync',
                              style: getBoldStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Net-15 Payout Forecast Card ──
  Widget _buildPayoutCard(ColorScheme cs, bool isDark) {
    final payout = _payoutEstimate!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141724) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: cs.onSurface.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.event_available_rounded,
                      color: Color(0xFFFFB300),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Net-15 Payout Schedule',
                    style: getBoldStyle(fontSize: 14, color: cs.onSurface),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Bi-Weekly Cycle',
                  style: getRegularStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Two Payout Forecast Tiles
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF282012),
                              const Color(0xFF1A160F),
                            ]
                          : [
                              const Color(0xFFFFF9EE),
                              const Color(0xFFFFF3DB),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'NEXT PAYOUT',
                            style: getBoldStyle(
                              fontSize: 10,
                              color: const Color(0xFFFFB300),
                            ),
                          ),
                          const Icon(
                            Icons.hourglass_top_rounded,
                            size: 14,
                            color: Color(0xFFFFB300),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$${payout.nextPayoutAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          fontFamily: 'sans-serif',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 12,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              payout.nextPayoutDate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: getBoldStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF0F2228),
                              const Color(0xFF0B171B),
                            ]
                          : [
                              const Color(0xFFF0FBFC),
                              const Color(0xFFE2F7F9),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00ADB5).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ACCUMULATING',
                            style: getBoldStyle(
                              fontSize: 10,
                              color: const Color(0xFF00ADB5),
                            ),
                          ),
                          const Icon(
                            Icons.trending_up_rounded,
                            size: 14,
                            color: Color(0xFF00ADB5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$${payout.pendingPayoutAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          fontFamily: 'sans-serif',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.update_rounded,
                            size: 12,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              payout.pendingPayoutDate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: getBoldStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '• Adsterra pays twice a month: 1st–15th on ~3rd, 16th–end on ~16th.',
            style: getRegularStyle(
              fontSize: 10.5,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Performance Analytics Section ──
  Widget _buildPerformanceSection(ColorScheme cs, bool isDark) {
    final statsData = _computeFilteredStats();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_rounded,
                  color: const Color(0xFF6C5CE7),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Performance Analytics',
                  style: getBoldStyle(fontSize: 16, color: cs.onSurface),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Sleek Frosted Timeframe Filter Bar
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141724) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              _buildFilterSegment('This Month', StatFilter.thisMonth, cs),
              _buildFilterSegment('Last 7 Days', StatFilter.last7Days, cs),
              _buildFilterSegment('Yesterday', StatFilter.yesterday, cs),
              _buildFilterSegment('Today', StatFilter.today, cs),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4 KPI Glowing Tiles
        Row(
          children: [
            Expanded(
              child: _buildGlowingMetricTile(
                title: 'Total Revenue',
                value: '\$${(statsData['revenue'] as double).toStringAsFixed(3)}',
                icon: Icons.monetization_on_rounded,
                accentColor: const Color(0xFF00E676),
                cs: cs,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGlowingMetricTile(
                title: 'Average CPM',
                value: '\$${(statsData['cpm'] as double).toStringAsFixed(2)}',
                icon: Icons.trending_up_rounded,
                accentColor: const Color(0xFF00ADB5),
                cs: cs,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildGlowingMetricTile(
                title: 'Impressions',
                value: NumberFormat.decimalPattern().format(statsData['impressions']),
                icon: Icons.visibility_rounded,
                accentColor: const Color(0xFF0984E3),
                cs: cs,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGlowingMetricTile(
                title: 'Total Clicks',
                value: NumberFormat.decimalPattern().format(statsData['clicks']),
                icon: Icons.ads_click_rounded,
                accentColor: const Color(0xFFFF7675),
                cs: cs,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterSegment(String label, StatFilter filter, ColorScheme cs) {
    final isSelected = _selectedFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = filter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF00ADB5), Color(0xFF6C5CE7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00ADB5).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: getBoldStyle(
              fontSize: 11.5,
              color: isSelected ? Colors.white : cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlowingMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required ColorScheme cs,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141724) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: isDark ? 0.22 : 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.06 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: getRegularStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              fontFamily: 'sans-serif',
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. Last 7 Days Chronological Activity ──
  Widget _buildLast7DaysStatsSection(ColorScheme cs, bool isDark) {
    final now = DateTime.now();

    final List<Map<String, dynamic>> daysData = [];
    for (int i = 0; i < 7; i++) {
      final targetDate = now.subtract(Duration(days: i));
      final dateKey = DateFormat('yyyy-MM-dd').format(targetDate);

      final stat = _stats.firstWhere(
        (s) => s.date == dateKey,
        orElse: () => AdsterraStatItem(date: dateKey),
      );

      String dayLabel;
      if (i == 0) {
        dayLabel = 'Today';
      } else if (i == 1) {
        dayLabel = 'Yesterday';
      } else {
        dayLabel = DateFormat('EEEE').format(targetDate);
      }

      daysData.add({
        'dayLabel': dayLabel,
        'formattedDate': DateFormat('dd MMM yyyy').format(targetDate),
        'stat': stat,
        'isToday': i == 0,
        'isYesterday': i == 1,
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_edu_rounded,
                  color: const Color(0xFF00ADB5),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Last 7 Days Performance',
                  style: getBoldStyle(fontSize: 16, color: cs.onSurface),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00ADB5).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00ADB5).withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                'Today at top',
                style: getBoldStyle(
                  fontSize: 11,
                  color: const Color(0xFF00ADB5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: daysData.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final day = daysData[index];
            final stat = day['stat'] as AdsterraStatItem;
            final isToday = day['isToday'] as bool;
            final isYesterday = day['isYesterday'] as bool;
            final label = day['dayLabel'] as String;
            final formattedDate = day['formattedDate'] as String;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141724) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isToday
                      ? const Color(0xFF00ADB5).withValues(alpha: 0.6)
                      : isYesterday
                          ? const Color(0xFF6C5CE7).withValues(alpha: 0.3)
                          : cs.onSurface.withValues(alpha: 0.07),
                  width: isToday ? 1.6 : 1.0,
                ),
                boxShadow: isToday
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00ADB5).withValues(alpha: isDark ? 0.12 : 0.05),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? const Color(0xFF00E676).withValues(alpha: 0.15)
                                  : isYesterday
                                      ? const Color(0xFF6C5CE7).withValues(alpha: 0.14)
                                      : cs.onSurface.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isToday) ...[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF00E676),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  label,
                                  style: getBoldStyle(
                                    fontSize: 12,
                                    color: isToday
                                        ? const Color(0xFF00E676)
                                        : isYesterday
                                            ? const Color(0xFF6C5CE7)
                                            : cs.onSurface.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formattedDate,
                            style: getRegularStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF00E676).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          '\$${stat.revenue.toStringAsFixed(4)}',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: isDark ? const Color(0xFF69F0AE) : const Color(0xFF00A352),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: cs.onSurface.withValues(alpha: 0.06),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDayStatPill(
                        'Impressions',
                        '${stat.impressions}',
                        Icons.visibility_outlined,
                        const Color(0xFF0984E3),
                        cs,
                      ),
                      _buildDayStatPill(
                        'Clicks',
                        '${stat.clicks}',
                        Icons.touch_app_rounded,
                        const Color(0xFFFF7675),
                        cs,
                      ),
                      _buildDayStatPill(
                        'CPM',
                        '\$${stat.cpm.toStringAsFixed(2)}',
                        Icons.trending_up_rounded,
                        const Color(0xFF00ADB5),
                        cs,
                      ),
                      _buildDayStatPill(
                        'CTR',
                        '${stat.ctr.toStringAsFixed(2)}%',
                        Icons.percent_rounded,
                        const Color(0xFF6C5CE7),
                        cs,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDayStatPill(
    String label,
    String value,
    IconData icon,
    Color color,
    ColorScheme cs,
  ) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: getRegularStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: getBoldStyle(
            fontSize: 12.5,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
