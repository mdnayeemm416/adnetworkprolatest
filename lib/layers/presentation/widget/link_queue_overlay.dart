import 'dart:async';

import 'package:adnetwork/core/services/link_queue_manager.dart';
import 'package:adnetwork/layers/presentation/screen/feed/feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// WebView instances loading URLs directly as top-level pages.
class LinkQueueOverlay extends StatelessWidget {
  final bool isPipMode;

  const LinkQueueOverlay({super.key, this.isPipMode = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActiveLink?>>(
      stream: LinkQueueManager.instance.slotsStream,
      initialData: LinkQueueManager.instance.slots,
      builder: (context, snapshot) {
        final slots = snapshot.data ?? [];
        final activeCount = slots.where((s) => s != null).length;

        // Keep the WebViews in the tree but offstage when there is no work
        return Offstage(
          offstage: activeCount == 0,
          child: RepaintBoundary(
            child: isPipMode
                ? Column(
                    children: [
                      for (int i = 0; i < LinkQueueManager.maxSlots; i++)
                        _SlotWrapper(
                          slotIndex: i,
                          isPipMode: true,
                          activeLink: slots.length > i ? slots[i] : null,
                        ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < LinkQueueManager.maxSlots; i++)
                        _SlotWrapper(
                          slotIndex: i,
                          isPipMode: false,
                          activeLink: slots.length > i ? slots[i] : null,
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _SlotWrapper extends StatelessWidget {
  final int slotIndex;
  final bool isPipMode;
  final ActiveLink? activeLink;

  const _SlotWrapper({
    required this.slotIndex,
    required this.isPipMode,
    required this.activeLink,
  });

  @override
  Widget build(BuildContext context) {
    if (activeLink == null) {
      return const SizedBox.shrink();
    }

    final String linkKeyStr =
        'slot_${slotIndex}_${activeLink?.linkId ?? activeLink?.url}';

    final Widget overlayWidget = ValueListenableBuilder<double>(
      valueListenable: webViewOverlayOpacityNotifier,
      builder: (context, opacity, child) {
        if (opacity <= 0) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(color: Colors.white.withValues(alpha: opacity)),
          ),
        );
      },
    );

    if (isPipMode) {
      return Expanded(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height - 120,
            child: Stack(
              children: [
                _SlotWebView(
                  key: ValueKey(linkKeyStr),
                  slotIndex: slotIndex,
                  activeLink: activeLink,
                ),
                overlayWidget,
              ],
            ),
          ),
        ),
      );
    } else {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 75,
        height: 142,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.5),
          child: Stack(
            children: [
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height - 120,
                  child: Stack(
                    children: [
                      _SlotWebView(
                        key: ValueKey(linkKeyStr),
                        slotIndex: slotIndex,
                        activeLink: activeLink,
                      ),
                      overlayWidget,
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Slot ${slotIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}

class _SlotWebView extends StatefulWidget {
  final int slotIndex;
  final ActiveLink? activeLink;

  const _SlotWebView({
    super.key,
    required this.slotIndex,
    required this.activeLink,
  });

  @override
  State<_SlotWebView> createState() => _SlotWebViewState();
}

class _SlotWebViewState extends State<_SlotWebView> {
  late final WebViewController _controller;
  Timer? _viewTimer;
  Timer? _timeoutTimer;
  Timer? _masterTimeout; // Safety-net: guarantees slot is freed no matter what
  bool _isLoading = false;
  bool _finished = false;
  String? _loadedUrl;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
            // Cancel any pending view timer on new page loads/redirects
            _viewTimer?.cancel();
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _onPageFinished(url);
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _onWebResourceError(error);
          },
          onHttpError: (HttpResponseError error) {
            // Ignore subresource HTTP errors (like 404/500 tracking scripts) to avoid closing prematurely.
            debugPrint(
              '[LinkQueue] Slot ${widget.slotIndex} Subresource HTTP Error: ${error.response?.statusCode} on ${error.request?.uri}',
            );
          },
        ),
      );

    _checkAndLoad();
  }

  @override
  void didUpdateWidget(covariant _SlotWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeLink?.url != oldWidget.activeLink?.url ||
        widget.activeLink?.retryCount != oldWidget.activeLink?.retryCount ||
        widget.activeLink?.displayedAt != oldWidget.activeLink?.displayedAt) {
      _checkAndLoad();
    }
  }

  void _checkAndLoad() {
    final link = widget.activeLink;
    if (link == null) {
      // Slot became idle, load about:blank to release resources and stop audio/video
      if (_loadedUrl != null && _loadedUrl != 'about:blank') {
        _loadedUrl = 'about:blank';
        _finished = true;
        _isLoading = false;
        _viewTimer?.cancel();
        _timeoutTimer?.cancel();
        _masterTimeout?.cancel();
        try {
          _controller.loadRequest(Uri.parse('about:blank'));
        } catch (_) {}
      }
      return;
    }

    _loadedUrl = link.url;
    _finished = false;
    _isLoading = true;

    _viewTimer?.cancel();
    _timeoutTimer?.cancel();
    _masterTimeout?.cancel();

    // ── MASTER SAFETY-NET: 45s hard cap from the moment we start loading ──
    // This runs immediately so it covers ALL phases: initial load, redirects,
    // blank-screen loops, and re-hits. Even if every other timeout gets
    // cancelled/reset, this one guarantees the slot is freed within 45s.
    _masterTimeout = Timer(const Duration(seconds: 45), () {
      if (!_finished && mounted) {
        debugPrint(
          '[LinkQueue] 🛡️ Slot ${widget.slotIndex} master timeout (45s from load start) — force-finishing: ${link.url}',
        );
        _finished = true;
        _viewTimer?.cancel();
        _timeoutTimer?.cancel();
        LinkQueueManager.instance.onSlotError(widget.slotIndex);
      }
    });

    try {
      final uri = Uri.parse(link.url);
      _controller.loadRequest(uri);
    } catch (e) {
      debugPrint(
        '[LinkQueue] ❌ Slot ${widget.slotIndex} Invalid URL: ${link.url}',
      );
      _finished = true;
      _isLoading = false;
      _masterTimeout?.cancel();
      // Mark as error immediately so it's removed from queue
      WidgetsBinding.instance.addPostFrameCallback((_) {
        LinkQueueManager.instance.onSlotError(widget.slotIndex);
      });
    }

    debugPrint('[LinkQueue] ▶ Slot ${widget.slotIndex} loading: ${link.url}');

    // ── HARD TIMEOUT: 20s max to receive onPageFinished ──
    _timeoutTimer = Timer(const Duration(seconds: 20), () {
      if (!_finished && mounted) {
        debugPrint(
          '[LinkQueue] ⏰ Slot ${widget.slotIndex} load timed out (20s): ${link.url}',
        );
        _finished = true;
        _viewTimer?.cancel();
        _masterTimeout?.cancel();
        LinkQueueManager.instance.onSlotError(widget.slotIndex);
      }
    });
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    _timeoutTimer?.cancel();
    _masterTimeout?.cancel();
    if (!_finished && widget.activeLink != null) {
      final slotIndex = widget.slotIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        LinkQueueManager.instance.onSlotError(slotIndex);
      });
    }
    super.dispose();
  }

  /// Page loaded — check if it's an actual page or an error page.
  void _onPageFinished(String url) async {
    if (_finished) return;
    if (url == 'about:blank') return;

    // Cancel the load timeout — page has started responding.
    // The master timeout (started at load begin) is still running as a hard cap.
    _timeoutTimer?.cancel();
    _viewTimer?.cancel();

    _checkPageLoaded(url);
  }

  /// Check if the page has rendered actual contents (not a blank/white screen)
  void _checkPageLoaded(String url) async {
    if (_finished) return;
    if (widget.activeLink == null) return;

    try {
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          var title = (document.title || '').toLowerCase();
          var body = (document.body ? document.body.innerText || '' : '').substring(0, 500).toLowerCase();
          var combined = title + ' ' + body;
          if (
            combined.indexOf('not found') !== -1 ||
            combined.indexOf('404') !== -1 ||
            combined.indexOf('err_') !== -1 ||
            combined.indexOf('cannot be reached') !== -1 ||
            combined.indexOf('connection refused') !== -1 ||
            combined.indexOf('dns_probe') !== -1 ||
            combined.indexOf('web page not available') !== -1 ||
            combined.indexOf('this site can') !== -1 ||
            combined.indexOf('page not found') !== -1
          ) {
            return 'error';
          }
          return 'ok';
        })();
      ''');

      final status = result.toString().replaceAll('"', '');

      if (status == 'error') {
        debugPrint(
          '[LinkQueue] ❌ Slot ${widget.slotIndex} error page detected: $url',
        );
        _finished = true;
        _viewTimer?.cancel();
        _masterTimeout?.cancel();
        LinkQueueManager.instance.onSlotError(widget.slotIndex);
        return;
      }
    } catch (_) {
      // JS execution failed (e.g. cross-origin iframe security issues on runJavaScriptReturningResult)
      // Treat as success so we don't get stuck in a loop.
    }

    final duration = LinkQueueManager.instance.randomViewDuration;
    debugPrint(
      '[LinkQueue] ✅ Slot ${widget.slotIndex} loaded content: $url (viewing for ${duration.inSeconds}s)',
    );
    _viewTimer = Timer(duration, () {
      if (!_finished && mounted) {
        debugPrint(
          '[LinkQueue] ✅ Slot ${widget.slotIndex} view time elapsed — marking finished: $url',
        );
        _finished = true;
        _masterTimeout?.cancel();
        LinkQueueManager.instance.onSlotFinished(widget.slotIndex);
      }
    });
  }

  /// Network-level error (DNS, connection refused, etc.)
  void _onWebResourceError(WebResourceError error) {
    if (_finished) return;
    if (error.isForMainFrame ?? false) {
      debugPrint(
        '[LinkQueue] ❌ Slot ${widget.slotIndex} main-frame error: ${error.description}',
      );
      _finished = true;
      _viewTimer?.cancel();
      _timeoutTimer?.cancel();
      _masterTimeout?.cancel();
      LinkQueueManager.instance.onSlotError(widget.slotIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
