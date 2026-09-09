import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:adnetwork/core/services/link_queue_manager.dart';
import 'package:adnetwork/core/services/pip_service.dart';
import 'package:adnetwork/config/theme/styles_manager.dart';

/// Global notifier for the real-time blur intensity (sigma from 0.0 to 30.0).
final ValueNotifier<double> webViewBlurIntensityNotifier = ValueNotifier(12.0);

/// Full-Display WebView Overlay that appears when a user likes a link or during AutoPlay.
/// Displays the loaded web page with a real-time countdown timer bar at the top,
/// hardware-accelerated CSS blur, and a bottom customization panel for the user to adjust blur in real-time.
class LinkQueueOverlay extends StatelessWidget {
  final bool isPipMode;
  final VoidCallback? onPauseAutoPlay;

  const LinkQueueOverlay({
    super.key,
    this.isPipMode = false,
    this.onPauseAutoPlay,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveViewSession?>(
      valueListenable: LinkQueueManager.instance.activeSessionNotifier,
      builder: (context, session, _) {
        if (session == null) {
          if (isPipMode) {
            return const _PipIdleOverlay();
          }
          return const SizedBox.shrink();
        }

        return _FullDisplayWebView(
          key: ValueKey('full_display_${session.sessionId}'),
          session: session,
          isPipMode: isPipMode,
          onPauseAutoPlay: onPauseAutoPlay,
        );
      },
    );
  }
}

class _PipIdleOverlay extends StatefulWidget {
  const _PipIdleOverlay();

  @override
  State<_PipIdleOverlay> createState() => _PipIdleOverlayState();
}

class _PipIdleOverlayState extends State<_PipIdleOverlay> {
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!LinkQueueManager.instance.hasQueuedLinks) {
        _autoCloseTimer = Timer(const Duration(seconds: 2), () {
          try {
            PipService.instance.exitPip();
          } catch (_) {}
        });
      }
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasLinks = LinkQueueManager.instance.hasQueuedLinks;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasLinks) ...[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF6366F1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Next link loading...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
              ] else ...[
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 26,
                ),
                const SizedBox(height: 6),
                const Text(
                  'All links viewed!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Closing PiP...',
                  style: TextStyle(
                    fontSize: 8.5,
                    color: Colors.white54,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FullDisplayWebView extends StatefulWidget {
  final ActiveViewSession session;
  final bool isPipMode;
  final VoidCallback? onPauseAutoPlay;

  const _FullDisplayWebView({
    super.key,
    required this.session,
    required this.isPipMode,
    this.onPauseAutoPlay,
  });

  @override
  State<_FullDisplayWebView> createState() => _FullDisplayWebViewState();
}

class _FullDisplayWebViewState extends State<_FullDisplayWebView> {
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
    _loadSavedBlur();

    webViewBlurIntensityNotifier.addListener(_onBlurChanged);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted && !_isPageReady) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _handlePageLoaded(url);
          },
          onWebResourceError: (error) {
            debugPrint(
              '[FullWebView] ⚠️ Web resource notice (${error.errorCode}): ${error.description}',
            );
            // Only trigger countdown fallback if the main document failed,
            // not for blocked trackers, missing favicons, or sub-assets.
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
              '[FullWebView] ⚠️ HTTP error ${error.response?.statusCode} on ${error.request?.uri}',
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
            if (scheme == 'http' || scheme == 'https') {
              return NavigationDecision.navigate;
            }

            // Cleanly launch external application schemes (intent, market, whatsapp, etc.)
            _launchExternalUri(uri);
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
        key: ValueKey('webview_${widget.session.sessionId}'),
      );
    } else {
      _webViewWidget = WebViewWidget(
        key: ValueKey('webview_${widget.session.sessionId}'),
        controller: _controller,
      );
    }

    _startLoad();
  }

  Future<void> _launchExternalUri(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[FullWebView] ⚠️ Could not launch external URI: $uri ($e)');
    }
  }

  @override
  void didUpdateWidget(covariant _FullDisplayWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.session.linkId != widget.session.linkId ||
        oldWidget.session.url != widget.session.url) {
      _remainingSeconds = widget.session.durationSeconds;
      _startLoad();
    }
    if (oldWidget.isPipMode != widget.isPipMode) {
      if (widget.isPipMode) {
        _injectPipViewport();
      }
      _applyBlur(webViewBlurIntensityNotifier.value);
    }
  }

  Future<void> _loadSavedBlur() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBlur = prefs.getDouble('webview_blur_intensity') ?? 12.0;
    webViewBlurIntensityNotifier.value = savedBlur;
  }

  void _onBlurChanged() {
    _applyBlur(webViewBlurIntensityNotifier.value);
  }

  void _applyBlur(double blurSigma) {
    if (!mounted) return;
    if (widget.isPipMode || blurSigma <= 0.1) {
      _controller
          .runJavaScript(
            "if (document.documentElement) { document.documentElement.style.filter = 'none'; }",
          )
          .catchError((_) {});
    } else {
      _controller
          .runJavaScript(
            "if (document.documentElement) { document.documentElement.style.filter = 'blur(${blurSigma.toStringAsFixed(1)}px)'; }",
          )
          .catchError((_) {});
    }
  }

  void _injectPipViewport() {
    _controller
        .runJavaScript('''
      (function() {
        try {
          var meta = document.querySelector('meta[name="viewport"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
          }
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0';
          
          var style = document.getElementById('pip-dark-style');
          if (style) {
            style.remove();
          }
        } catch (e) {}
      })();
    ''')
        .catchError((_) {});
  }

  void _startLoad() {
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
        debugPrint('[FullWebView] 🛡️ Master timeout (40s) triggered');
        _onSessionFinished();
      }
    });

    // ── Page load timeout (12s) ──
    _loadTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (!_isPageReady && !_isCompleted && mounted) {
        debugPrint(
          '[FullWebView] ⏰ Load timed out after 12s — starting countdown anyway',
        );
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        _startCountdown();
      }
    });

    try {
      final uri = Uri.parse(widget.session.url);
      _controller.loadRequest(uri);
    } catch (e) {
      debugPrint('[FullWebView] ❌ Invalid URL: ${widget.session.url}');
      _onSessionError();
    }
  }

  void _handlePageLoaded(String url) async {
    if (_isCompleted) return;
    if (url == 'about:blank') return;

    _loadTimeoutTimer?.cancel();

    if (widget.isPipMode) {
      _injectPipViewport();
    }

    _applyBlur(webViewBlurIntensityNotifier.value);
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
      } else {
        setState(() {
          _remainingSeconds = 0;
        });
        timer.cancel();
        _onSessionFinished();
      }
    });
  }

  void _onSessionFinished() {
    if (_isCompleted) return;
    _isCompleted = true;
    _countdownTicker?.cancel();
    _loadTimeoutTimer?.cancel();
    _masterTimeoutTimer?.cancel();

    LinkQueueManager.instance.onSessionFinished();
  }

  void _onSessionError() {
    if (_isCompleted) return;
    _isCompleted = true;
    _countdownTicker?.cancel();
    _loadTimeoutTimer?.cancel();
    _masterTimeoutTimer?.cancel();

    LinkQueueManager.instance.onSessionError();
  }

  void _onCloseManually() {
    _isCompleted = true;
    _countdownTicker?.cancel();
    _loadTimeoutTimer?.cancel();
    _masterTimeoutTimer?.cancel();

    if (widget.session.isAutoPlay) {
      widget.onPauseAutoPlay?.call();
      LinkQueueManager.instance.requestPauseAutoPlay();
    }
    LinkQueueManager.instance.cancelViewing(completeLike: false);
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _loadTimeoutTimer?.cancel();
    _masterTimeoutTimer?.cancel();
    webViewBlurIntensityNotifier.removeListener(_onBlurChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalDuration = widget.session.durationSeconds;
    final double progress = totalDuration > 0
        ? (1.0 - (_remainingSeconds / totalDuration)).clamp(0.0, 1.0)
        : 1.0;

    final mainStack = Stack(
      fit: StackFit.expand,
      children: [
        // ── Main WebView Viewport (Occupies 100% in PIP mode) ──
        Positioned.fill(
          top: widget.isPipMode ? 0 : 60,
          child: Container(
            color: const Color(0xFF0F172A),
            child: _webViewWidget,
          ),
        ),

        // ── Privacy Scrim Layer (Replaces broken BackdropFilter on PlatformView) ──
        if (!widget.isPipMode)
          Positioned.fill(
            top: 60,
            child: ValueListenableBuilder<double>(
              valueListenable: webViewBlurIntensityNotifier,
              builder: (context, blurSigma, _) {
                if (blurSigma <= 0.1) {
                  return const SizedBox.shrink();
                }
                final alpha = ((blurSigma / 30.0) * 0.45).clamp(0.05, 0.55);
                return IgnorePointer(
                  child: Container(
                    color: const Color(0xFF0F172A).withValues(alpha: alpha),
                  ),
                );
              },
            ),
          ),

        // ── Loading Indicator ──
        if (_isLoading)
          widget.isPipMode
              ? Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Loading...',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Positioned.fill(
                  top: 60,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              cs.primary,
                            ),
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Loading page...',
                            style: getMediumStyle(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

        // ── PIP Mode Floating Mini Header & Progress ──
        if (widget.isPipMode) ...[
          // Linear Progress at very top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2.5,
              backgroundColor: Colors.black38,
              valueColor: AlwaysStoppedAnimation<Color>(
                _remainingSeconds <= 3 ? Colors.redAccent : cs.primary,
              ),
            ),
          ),
          // Floating Timer Chip
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _remainingSeconds <= 3 ? Colors.redAccent : cs.primary,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _remainingSeconds <= 3 ? Colors.redAccent : cs.primary,
                      ),
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_remainingSeconds}s',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (!widget.isPipMode)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 60,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // ── Status Badge ──
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.session.isAutoPlay
                                    ? Colors.orange.withValues(alpha: 0.2)
                                    : cs.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: widget.session.isAutoPlay
                                      ? Colors.orange
                                      : cs.primary,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.session.isAutoPlay
                                        ? Icons.play_circle_fill_rounded
                                        : Icons.link_rounded,
                                    size: 14,
                                    color: widget.session.isAutoPlay
                                        ? Colors.orange
                                        : cs.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      widget.session.isAutoPlay
                                          ? 'P${widget.session.pageIndex} • ${widget.session.totalLinks} remaining'
                                          : 'Viewing',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: getBoldStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          const Spacer(),

                          // ── Countdown Timer Pill ──
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _remainingSeconds <= 3
                                  ? Colors.red.withValues(alpha: 0.25)
                                  : cs.primary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _remainingSeconds <= 3
                                    ? Colors.redAccent
                                    : cs.primary,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _remainingSeconds <= 3
                                          ? Colors.redAccent
                                          : cs.primary,
                                    ),
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_remainingSeconds}s',
                                  style: getBoldStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // // ── Pause / Stop AutoPlay Button ──
                          // if (widget.session.isAutoPlay) ...[
                          //   const SizedBox(width: 6),
                          //   IconButton(
                          //     icon: const Icon(
                          //       Icons.pause_circle_filled_rounded,
                          //       color: Colors.orange,
                          //       size: 22,
                          //     ),
                          //     tooltip: 'Pause AutoPlay',
                          //     padding: EdgeInsets.zero,
                          //     constraints: const BoxConstraints(),
                          //     onPressed: () {
                          //       widget.onPauseAutoPlay?.call();
                          //       _onCloseManually();
                          //     },
                          //   ),
                          // ],

                          // const SizedBox(width: 6),

                          // ── Close (X) Button ──
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                            tooltip: 'Close',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _onCloseManually,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Animated Linear Progress Bar ──
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _remainingSeconds <= 3 ? Colors.redAccent : cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Bottom Side Controls (PIP on left, Blur Customizer on right/full) ──
        if (!widget.isPipMode) ...[
          // Floating PIP Button (Bottom-Left)
          const Positioned(left: 16, bottom: 16, child: _PipFloatingButton()),

          // Runtime Blur Customizer (Bottom-Right / Full-Width when expanded)
          const Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _BlurCustomizerBottomBar(),
          ),
        ],
      ],
    );

    return Container(
      color: const Color(0xFF0F172A),
      child: widget.isPipMode ? mainStack : SafeArea(child: mainStack),
    );
  }
}

/// Floating button on the bottom left of the WebView overlay to enter Picture-in-Picture mode.
class _PipFloatingButton extends StatelessWidget {
  const _PipFloatingButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          try {
            final isSupported = await PipService.instance.isSupported();
            if (isSupported) {
              await PipService.instance.enterPip();
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('PIP is not supported on this device'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Failed to start PIP: $e');
          }
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.blueAccent.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_in_picture_alt_rounded,
                color: Colors.blueAccent,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'PIP Mode',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive floating bottom bar allowing the user to customize blur intensity at runtime.
class _BlurCustomizerBottomBar extends StatefulWidget {
  const _BlurCustomizerBottomBar();

  @override
  State<_BlurCustomizerBottomBar> createState() =>
      _BlurCustomizerBottomBarState();
}

class _BlurCustomizerBottomBarState extends State<_BlurCustomizerBottomBar> {
  bool _isExpanded = false;
  Timer? _debounceTimer;

  void _saveBlurDebounced(double val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('webview_blur_intensity', val);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<double>(
      valueListenable: webViewBlurIntensityNotifier,
      builder: (context, blurVal, _) {
        if (!_isExpanded) {
          // ── Collapsed Floating Pill ──
          return Align(
            alignment: Alignment.bottomRight,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _isExpanded = true),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        blurVal > 0.1
                            ? Icons.blur_on_rounded
                            : Icons.blur_off_rounded,
                        color: cs.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        blurVal > 0.1
                            ? 'Blur ${blurVal.round()}px'
                            : 'Blur Off',
                        style: getBoldStyle(fontSize: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.tune_rounded,
                        color: Colors.white70,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // ── Expanded Customization Card ──
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header Row ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.blur_on_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Customize Blur Intensity',
                        style: getBoldStyle(fontSize: 13, color: Colors.white),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          blurVal <= 0.1 ? 'OFF' : '${blurVal.round()}px',
                          style: getBoldStyle(fontSize: 12, color: cs.primary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _isExpanded = false),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Quick Preset Chips ──
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _PresetChip(
                      label: 'Off',
                      value: 0.0,
                      current: blurVal,
                      onSelected: (v) {
                        webViewBlurIntensityNotifier.value = v;
                        _saveBlurDebounced(v);
                      },
                    ),
                    _PresetChip(
                      label: 'Low (6px)',
                      value: 6.0,
                      current: blurVal,
                      onSelected: (v) {
                        webViewBlurIntensityNotifier.value = v;
                        _saveBlurDebounced(v);
                      },
                    ),
                    _PresetChip(
                      label: 'Med (12px)',
                      value: 12.0,
                      current: blurVal,
                      onSelected: (v) {
                        webViewBlurIntensityNotifier.value = v;
                        _saveBlurDebounced(v);
                      },
                    ),
                    _PresetChip(
                      label: 'High (20px)',
                      value: 20.0,
                      current: blurVal,
                      onSelected: (v) {
                        webViewBlurIntensityNotifier.value = v;
                        _saveBlurDebounced(v);
                      },
                    ),
                    _PresetChip(
                      label: 'Max (30px)',
                      value: 30.0,
                      current: blurVal,
                      onSelected: (v) {
                        webViewBlurIntensityNotifier.value = v;
                        _saveBlurDebounced(v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Smooth Live Slider ──
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: cs.primary,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: cs.primary,
                  overlayColor: cs.primary.withValues(alpha: 0.2),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                ),
                child: Slider(
                  value: blurVal.clamp(0.0, 30.0),
                  min: 0.0,
                  max: 30.0,
                  divisions: 30,
                  onChanged: (newVal) {
                    webViewBlurIntensityNotifier.value = newVal;
                    _saveBlurDebounced(newVal);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final double value;
  final double current;
  final ValueChanged<double> onSelected;

  const _PresetChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = (current - value).abs() < 1.0;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(value),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primary
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? cs.primary
                    : Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              label,
              style: getBoldStyle(
                fontSize: 10.5,
                color: isSelected ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
