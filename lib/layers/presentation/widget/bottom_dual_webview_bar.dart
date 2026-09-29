import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:adnetwork/core/services/link_queue_manager.dart';
import 'package:adnetwork/config/theme/styles_manager.dart';

/// Bottom Dual-Stacked WebView Bar (Expandable Bottom Sheet with Dual-Tab Switching).
///
/// Features:
/// - Default Collapsed Mode: Compact mini-bars (~76px per slot) stacked at the bottom
///   of the feed page so user browsing is not interrupted.
/// - Expandable Bottom Sheet: Tapping the "Expand" button (⤢) smoothly animates the sheet
///   to full mobile display (~85% screen height).
/// - Dual-Tab Switcher in Expanded Mode: When 2 slots are active concurrently, displays
///   sleek dual tabs [Slot 1 • XXs] and [Slot 2 • XXs].
/// - Zero Reparenting / Persistent State: Both WebViews remain permanently mounted in the
///   widget tree (via Offstage), so countdowns, JavaScript execution, and DOM state
///   continue concurrently without reloading or losing scroll position.
/// - Unobstructed rendering: Real mobile viewport in expanded mode, eliminating IVT/bot flags.
class BottomDualWebViewBar extends StatefulWidget {
  final VoidCallback? onPauseAutoPlay;
  final ValueChanged<bool>? onExpandedChanged;

  const BottomDualWebViewBar({
    super.key,
    this.onPauseAutoPlay,
    this.onExpandedChanged,
  });

  @override
  State<BottomDualWebViewBar> createState() => _BottomDualWebViewBarState();
}

class _BottomDualWebViewBarState extends State<BottomDualWebViewBar> {
  bool _isExpanded = false;
  int _selectedTab = 1;

  final ValueNotifier<int> _slot1RemainingNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _slot2RemainingNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> _slot1ProgressNotifier = ValueNotifier<double>(
    0.0,
  );
  final ValueNotifier<double> _slot2ProgressNotifier = ValueNotifier<double>(
    0.0,
  );

  @override
  void dispose() {
    _slot1RemainingNotifier.dispose();
    _slot2RemainingNotifier.dispose();
    _slot1ProgressNotifier.dispose();
    _slot2ProgressNotifier.dispose();
    super.dispose();
  }

  void _toggleExpanded({int? targetTab}) {
    setState(() {
      if (targetTab != null) {
        _selectedTab = targetTab;
        _isExpanded = true;
      } else {
        _isExpanded = !_isExpanded;
      }
    });
    if (_isExpanded) {
      widget.onPauseAutoPlay?.call();
    }
    widget.onExpandedChanged?.call(_isExpanded);
  }

  void _collapse() {
    if (!_isExpanded) return;
    setState(() {
      _isExpanded = false;
    });
    widget.onExpandedChanged?.call(false);
  }

  void _closeActiveSlot({ActiveViewSession? s1, ActiveViewSession? s2}) {
    if (_selectedTab == 1 && s1 != null) {
      LinkQueueManager.instance.onSlotFinished(1, s1.linkId);
      if (s2 != null) {
        setState(() => _selectedTab = 2);
      }
    } else if (_selectedTab == 2 && s2 != null) {
      LinkQueueManager.instance.onSlotFinished(2, s2.linkId);
      if (s1 != null) {
        setState(() => _selectedTab = 1);
      }
    }
  }

  void _closeSlot(int slotIndex, ActiveViewSession session) {
    LinkQueueManager.instance.onSlotFinished(slotIndex, session.linkId);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final targetExpandedHeight = (screenHeight * 0.85).clamp(420.0, 780.0);
    const double expandedHeaderHeight = 52.0;
    final double bodyHeight = targetExpandedHeight - expandedHeaderHeight;

    return ValueListenableBuilder<ActiveViewSession?>(
      valueListenable: LinkQueueManager.instance.slot1SessionNotifier,
      builder: (context, session1, _) {
        return ValueListenableBuilder<ActiveViewSession?>(
          valueListenable: LinkQueueManager.instance.slot2SessionNotifier,
          builder: (context, session2, _) {
            if (session1 == null && session2 == null) {
              if (_isExpanded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _isExpanded) {
                    setState(() => _isExpanded = false);
                    widget.onExpandedChanged?.call(false);
                  }
                });
              }
              return const SizedBox.shrink();
            }

            // Adjust active tab if selected tab's session completed
            if (_selectedTab == 2 && session2 == null && session1 != null) {
              _selectedTab = 1;
            } else if (_selectedTab == 1 &&
                session1 == null &&
                session2 != null) {
              _selectedTab = 2;
            }

            double collapsedHeight = 0.0;
            if (session2 != null) collapsedHeight += 76.0;
            if (session1 != null) collapsedHeight += 76.0;

            final currentHeight = _isExpanded
                ? targetExpandedHeight
                : collapsedHeight;
            final activeSession = _selectedTab == 1 ? session1 : session2;
            final activeColor = _selectedTab == 1
                ? const Color(0xFF6366F1)
                : const Color(0xFF10B981);
            final activeProgressNotifier = _selectedTab == 1
                ? _slot1ProgressNotifier
                : _slot2ProgressNotifier;

            return PopScope(
              canPop: !_isExpanded,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && _isExpanded) {
                  _collapse();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                height: currentHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: _isExpanded
                      ? const BorderRadius.vertical(top: Radius.circular(16))
                      : BorderRadius.zero,
                  border: Border(
                    top: BorderSide(
                      color: _isExpanded
                          ? activeColor.withValues(alpha: 0.6)
                          : (session2 != null
                                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                : const Color(
                                    0xFF6366F1,
                                  ).withValues(alpha: 0.4)),
                      width: _isExpanded ? 1.5 : 1.0,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isExpanded ? 0.55 : 0.35,
                      ),
                      blurRadius: _isExpanded ? 16 : 6,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: currentHeight,
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      height: _isExpanded
                          ? targetExpandedHeight
                          : collapsedHeight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Top Header (Only in expanded mode) ──
                          if (_isExpanded)
                            _buildExpandedHeader(
                              session1: session1,
                              session2: session2,
                              activeSession: activeSession,
                              activeColor: activeColor,
                              activeProgressNotifier: activeProgressNotifier,
                            ),

                          // ── Slot 2 (Top in collapsed mode) ──
                          if (session2 != null)
                            Offstage(
                              offstage: _isExpanded && _selectedTab != 2,
                              child: SizedBox(
                                height: _isExpanded ? bodyHeight : 76.0,
                                child: _SingleSlotBar(
                                  key: ValueKey('slot2_${session2.sessionId}'),
                                  slotIndex: 2,
                                  session: session2,
                                  accentColor: const Color(0xFF10B981),
                                  isExpanded: _isExpanded,
                                  onExpand: () => _toggleExpanded(targetTab: 2),
                                  onClose: () => _closeSlot(2, session2),
                                  onProgressUpdate: (remaining, progress) {
                                    _slot2RemainingNotifier.value = remaining;
                                    _slot2ProgressNotifier.value = progress;
                                  },
                                ),
                              ),
                            ),

                          // ── Slot 1 (Bottom in collapsed mode) ──
                          if (session1 != null)
                            Offstage(
                              offstage: _isExpanded && _selectedTab != 1,
                              child: SizedBox(
                                height: _isExpanded ? bodyHeight : 76.0,
                                child: _SingleSlotBar(
                                  key: ValueKey('slot1_${session1.sessionId}'),
                                  slotIndex: 1,
                                  session: session1,
                                  accentColor: const Color(0xFF6366F1),
                                  isExpanded: _isExpanded,
                                  onExpand: () => _toggleExpanded(targetTab: 1),
                                  onClose: () => _closeSlot(1, session1),
                                  onProgressUpdate: (remaining, progress) {
                                    _slot1RemainingNotifier.value = remaining;
                                    _slot1ProgressNotifier.value = progress;
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExpandedHeader({
    required ActiveViewSession? session1,
    required ActiveViewSession? session2,
    required ActiveViewSession? activeSession,
    required Color activeColor,
    required ValueNotifier<double> activeProgressNotifier,
  }) {
    return Container(
      height: 52.0,
      color: const Color(0xFF1E293B),
      child: Column(
        children: [
          // ── Top drag handle pill ──
          GestureDetector(
            onVerticalDragUpdate: (details) {
              if ((details.primaryDelta ?? 0) > 6) {
                _collapse();
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              alignment: Alignment.center,
              child: Container(
                width: 38,
                height: 3.5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // ── Controls Row ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  // Collapse / Minimize Button
                  GestureDetector(
                    onTap: _collapse,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Center Content: Dual-Tab Switcher OR Single Slot info
                  Expanded(
                    child: (session1 != null && session2 != null)
                        ? _buildDualTabSwitcher(
                            session1: session1,
                            session2: session2,
                          )
                        : (activeSession != null
                              ? _buildSingleSlotHeaderInfo(
                                  session: activeSession,
                                  slotIndex: _selectedTab,
                                  accentColor: activeColor,
                                  remainingNotifier: _selectedTab == 1
                                      ? _slot1RemainingNotifier
                                      : _slot2RemainingNotifier,
                                )
                              : const SizedBox.shrink()),
                  ),

                  const SizedBox(width: 8),

                  // Close / Skip Button
                  GestureDetector(
                    onTap: () => _closeActiveSlot(s1: session1, s2: session2),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Active Slot Micro-Progress Line (2.5px) ──
          ValueListenableBuilder<double>(
            valueListenable: activeProgressNotifier,
            builder: (context, progress, _) {
              return SizedBox(
                height: 2.5,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDualTabSwitcher({
    required ActiveViewSession session1,
    required ActiveViewSession session2,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTabChip(
              slotIndex: 1,
              label: 'Slot 1',
              accentColor: const Color(0xFF6366F1),
              isSelected: _selectedTab == 1,
              remainingNotifier: _slot1RemainingNotifier,
              url: session1.url,
              onTap: () => setState(() => _selectedTab = 1),
            ),
            const SizedBox(width: 4),
            _buildTabChip(
              slotIndex: 2,
              label: 'Slot 2',
              accentColor: const Color(0xFF10B981),
              isSelected: _selectedTab == 2,
              remainingNotifier: _slot2RemainingNotifier,
              url: session2.url,
              onTap: () => setState(() => _selectedTab = 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip({
    required int slotIndex,
    required String label,
    required Color accentColor,
    required bool isSelected,
    required ValueNotifier<int> remainingNotifier,
    required String url,
    required VoidCallback onTap,
  }) {
    final host = Uri.tryParse(url)?.host ?? '';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6.5,
              height: 6.5,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: getSemiBoldStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : Colors.white70,
              ),
            ),
            const SizedBox(width: 5),
            ValueListenableBuilder<int>(
              valueListenable: remainingNotifier,
              builder: (context, remaining, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.5,
                    vertical: 0.5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${remaining}s',
                    style: getBoldStyle(fontSize: 9.5, color: Colors.white),
                  ),
                );
              },
            ),
            if (host.isNotEmpty) ...[
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 80),
                child: Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: getRegularStyle(
                    fontSize: 9,
                    color: isSelected ? Colors.white70 : Colors.white38,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSingleSlotHeaderInfo({
    required ActiveViewSession session,
    required int slotIndex,
    required Color accentColor,
    required ValueNotifier<int> remainingNotifier,
  }) {
    final host = Uri.tryParse(session.url)?.host ?? session.url;
    final queueLength = LinkQueueManager.instance.queueLength;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'Slot $slotIndex',
                style: getSemiBoldStyle(fontSize: 11, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<int>(
          valueListenable: remainingNotifier,
          builder: (context, remaining, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${remaining}s',
                style: getBoldStyle(fontSize: 11, color: Colors.white),
              ),
            );
          },
        ),
        if (queueLength > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$queueLength queued',
              style: getRegularStyle(fontSize: 10, color: Colors.white70),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: getRegularStyle(fontSize: 10.5, color: Colors.white60),
          ),
        ),
      ],
    );
  }
}

class _SingleSlotBar extends StatefulWidget {
  final int slotIndex;
  final ActiveViewSession session;
  final Color accentColor;
  final bool isExpanded;
  final VoidCallback onExpand;
  final VoidCallback onClose;
  final void Function(int remainingSeconds, double progress)? onProgressUpdate;

  const _SingleSlotBar({
    super.key,
    required this.slotIndex,
    required this.session,
    required this.accentColor,
    required this.isExpanded,
    required this.onExpand,
    required this.onClose,
    this.onProgressUpdate,
  });

  @override
  State<_SingleSlotBar> createState() => _SingleSlotBarState();
}

class _SingleSlotBarState extends State<_SingleSlotBar> {
  late final WebViewController _controller;
  late final Widget _webViewWidget;
  Timer? _countdownTicker;
  Timer? _loadTimeoutTimer;
  Timer? _masterTimeoutTimer;

  int _remainingSeconds = 0;
  bool _isLoading = true;
  bool _isPageReady = false;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.session.durationSeconds;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setOnJavaScriptAlertDialog((request) async {})
      ..setOnJavaScriptConfirmDialog((request) async => true)
      ..setOnJavaScriptTextInputDialog((request) async => '')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted && !_isPageReady) {
              setState(() {
                _isLoading = true;
              });
            }
            _injectAdViewability();
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _injectAdViewability();
            _handlePageLoaded(url);
          },
          onWebResourceError: (error) {
            debugPrint(
              '[BottomBar] ⚠️ Web resource notice (${error.errorCode}): ${error.description} on ${error.url}',
            );
            if (error.isForMainFrame == true &&
                !_isPageReady &&
                !_isCompleted) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
              _startCountdown();
            }
          },
          onHttpError: (error) {
            debugPrint(
              '[BottomBar] ⚠️ HTTP error ${error.response?.statusCode} on ${error.request?.uri}',
            );
            if ((error.response?.statusCode ?? 0) >= 400 &&
                !_isPageReady &&
                !_isCompleted) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
              _startCountdown();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            final scheme = uri.scheme.toLowerCase();
            if (scheme == 'http' ||
                scheme == 'https' ||
                scheme == 'about' ||
                scheme == 'data' ||
                scheme == 'blob') {
              return NavigationDecision.navigate;
            }

            // Silently block all external app intent/scheme launches (intent, market, tel, etc.)
            return NavigationDecision.prevent;
          },
        ),
      );

    if (Platform.isAndroid) {
      if (_controller.platform is AndroidWebViewController) {
        final androidController =
            _controller.platform as AndroidWebViewController;
        androidController.setMixedContentMode(MixedContentMode.alwaysAllow);
        androidController.setMediaPlaybackRequiresUserGesture(false);
        androidController.setOnPlatformPermissionRequest(
          (request) => request.deny(),
        );
        androidController.setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (request) async =>
              const GeolocationPermissionsResponse(allow: false, retain: false),
        );

        final cookieManager = WebViewCookieManager();
        if (cookieManager.platform is AndroidWebViewCookieManager) {
          (cookieManager.platform as AndroidWebViewCookieManager)
              .setAcceptThirdPartyCookies(androidController, true);
        }
      }
    }

    if (Platform.isAndroid) {
      _webViewWidget = WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: _controller.platform,
          displayWithHybridComposition: false,
        ),
        key: ValueKey('slot_${widget.slotIndex}_${widget.session.sessionId}'),
      );
    } else {
      _webViewWidget = WebViewWidget(
        key: ValueKey('slot_${widget.slotIndex}_${widget.session.sessionId}'),
        controller: _controller,
      );
    }

    _notifyProgress();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant _SingleSlotBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.session.linkId != widget.session.linkId ||
        oldWidget.session.url != widget.session.url) {
      _remainingSeconds = widget.session.durationSeconds;
      _notifyProgress();
      _startLoad();
    }
  }

  void _notifyProgress() {
    if (!mounted) return;
    final totalDuration = widget.session.durationSeconds;
    final double progress = totalDuration > 0
        ? (1.0 - (_remainingSeconds / totalDuration)).clamp(0.0, 1.0)
        : 1.0;
    widget.onProgressUpdate?.call(_remainingSeconds, progress);
  }

  static String? _cachedCleanUserAgent;

  Future<void> _applyCleanUserAgent() async {
    try {
      if (_cachedCleanUserAgent != null) {
        await _controller.setUserAgent(_cachedCleanUserAgent);
        return;
      }
      final rawUa = await _controller.getUserAgent();
      if (rawUa != null && rawUa.isNotEmpty) {
        final cleanUa = rawUa
            .replaceAll('; wv', '')
            .replaceAll(RegExp(r'Version\/4\.0\s*'), '');
        _cachedCleanUserAgent = cleanUa;
        await _controller.setUserAgent(cleanUa);
        debugPrint('[BottomBar] 🌐 Cleaned Mobile Chrome UA applied: $cleanUa');
      }
    } catch (e) {
      debugPrint('[BottomBar] ⚠️ Could not apply clean UA: $e');
    }
  }

  void _startLoad() async {
    _isLoading = true;
    _isPageReady = false;
    _isCompleted = false;
    _remainingSeconds = widget.session.durationSeconds;

    _loadTimeoutTimer?.cancel();
    _masterTimeoutTimer?.cancel();
    _countdownTicker?.cancel();

    // ── Hard Master Timeout (40s max) ──
    _masterTimeoutTimer = Timer(const Duration(seconds: 40), () {
      if (!_isCompleted && mounted) {
        _onSlotFinished();
      }
    });

    // ── Page load fallback (12s) ──
    _loadTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (!_isPageReady && !_isCompleted && mounted) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        _startCountdown();
      }
    });

    try {
      await _applyCleanUserAgent();
      final uri = Uri.parse(widget.session.url);
      _controller.loadRequest(uri);
    } catch (e) {
      _onSlotError();
    }
  }

  void _injectAdViewability() {
    try {
      _controller
          .runJavaScript('''
(function() {
  try {
    // Force visibility state to active so ad auction/scripts execute cleanly
    Object.defineProperty(document, 'hidden', { get: () => false, configurable: true });
    Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
    Object.defineProperty(document, 'webkitVisibilityState', { get: () => 'visible', configurable: true });
    Object.defineProperty(document, 'webkitHidden', { get: () => false, configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('focus'));
  } catch (e) {}
})();
''')
          .catchError((_) {});
    } catch (_) {}
  }

  void _handlePageLoaded(String url) {
    if (_isCompleted) return;
    if (url == 'about:blank') return;

    _injectAdViewability();
    _loadTimeoutTimer?.cancel();
    _startCountdown();
  }

  void _startCountdown() {
    if (_isPageReady || _isCompleted) return;
    _isPageReady = true;

    _countdownTicker?.cancel();
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isCompleted) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds--;
        });
        _notifyProgress();
      } else {
        setState(() {
          _remainingSeconds = 0;
        });
        _notifyProgress();
        timer.cancel();
        _onSlotFinished();
      }
    });
  }

  void _onSlotFinished() {
    if (_isCompleted) return;
    _isCompleted = true;
    _countdownTicker?.cancel();
    _loadTimeoutTimer?.cancel();
    _masterTimeoutTimer?.cancel();

    LinkQueueManager.instance.onSlotFinished(
      widget.slotIndex,
      widget.session.linkId,
    );
  }

  void _onSlotError() {
    if (_isCompleted) return;
    _isCompleted = true;
    _countdownTicker?.cancel();
    _loadTimeoutTimer?.cancel();
    _masterTimeoutTimer?.cancel();

    LinkQueueManager.instance.onSlotError(
      widget.slotIndex,
      widget.session.linkId,
    );
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _loadTimeoutTimer?.cancel();
    _masterTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isExpanded) {
      // ── Expanded Mode: 100% Unobstructed Full Display WebView ──
      return Container(color: Colors.white, child: _webViewWidget);
    }

    // ── Collapsed Mini-Bar Mode: 76px Banner Slot ──
    final mediaQuery = MediaQuery.of(context);
    final deviceWidth = mediaQuery.size.width > 0
        ? mediaQuery.size.width
        : 390.0;
    final deviceViewportHeight =
        (mediaQuery.size.height - mediaQuery.padding.top - 56.0).clamp(
          600.0,
          1000.0,
        );

    final totalDuration = widget.session.durationSeconds;
    final double progress = totalDuration > 0
        ? (1.0 - (_remainingSeconds / totalDuration)).clamp(0.0, 1.0)
        : 1.0;
    final remainingInQueue = LinkQueueManager.instance.queueLength;

    return Container(
      height: 76,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(
          top: BorderSide(
            color: widget.accentColor.withValues(alpha: 0.4),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          // ── Top Micro-Progress Line (2px) ──
          SizedBox(
            height: 2.0,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
            ),
          ),

          // ── Dedicated Status Bar Strip (20px) ──
          Container(
            height: 20,
            color: const Color(0xFF1E293B),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (_isLoading)
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: widget.accentColor,
                    ),
                  )
                else
                  Text(
                    '${_remainingSeconds}s',
                    style: getBoldStyle(fontSize: 11, color: Colors.white),
                  ),

                const SizedBox(width: 6),

                // Slot badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 0.5,
                  ),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'S${widget.slotIndex}',
                    style: getBoldStyle(fontSize: 8.5, color: Colors.white),
                  ),
                ),

                const SizedBox(width: 6),

                // Queue Counter Badge (only on first slot to prevent clutter)
                if (widget.slotIndex == 1 && remainingInQueue > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.0,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$remainingInQueue queued',
                      style: getMediumStyle(
                        fontSize: 9.0,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),

                const Spacer(),

                // URL Domain Hint (tap to expand)
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: widget.onExpand,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      Uri.tryParse(widget.session.url)?.host ??
                          widget.session.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: getRegularStyle(
                        fontSize: 9.5,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // ── Expand Full Display Button (⤢) ──
                GestureDetector(
                  onTap: widget.onExpand,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                    ),
                    child: const Icon(
                      Icons.open_in_full_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Close / Skip Button (✕)
                GestureDetector(
                  onTap: widget.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 10,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Live Unobstructed WebView Widget (Full 390x750 Virtual Viewport) ──
          Expanded(
            child: GestureDetector(
              onTap: widget.onExpand,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(color: Colors.white),
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: deviceWidth,
                    height: deviceViewportHeight,
                    child: AbsorbPointer(child: _webViewWidget),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
