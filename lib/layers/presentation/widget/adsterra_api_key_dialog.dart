import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/core/services/adsterra_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdsterraApiKeyDialog extends StatefulWidget {
  final bool isDismissible;
  final VoidCallback? onSuccess;

  const AdsterraApiKeyDialog({
    super.key,
    this.isDismissible = false,
    this.onSuccess,
  });

  static Future<bool?> show(
    BuildContext context, {
    bool isDismissible = false,
    VoidCallback? onSuccess,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: isDismissible,
      builder: (context) => PopScope(
        canPop: isDismissible,
        child: AdsterraApiKeyDialog(
          isDismissible: isDismissible,
          onSuccess: onSuccess,
        ),
      ),
    );
  }

  @override
  State<AdsterraApiKeyDialog> createState() => _AdsterraApiKeyDialogState();
}

class _AdsterraApiKeyDialogState extends State<AdsterraApiKeyDialog> {
  final TextEditingController _keyController = TextEditingController();
  bool _isLoading = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _keyController.text = data.text!.trim();
      });
    }
  }

  Future<void> _startSync() async {
    final apiKey = _keyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _isError = true;
        _statusMessage = 'Please enter your Adsterra API Key.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isError = false;
      _statusMessage = 'Validating key & purging previous links...';
    });

    final result = await AdsterraSyncService.instance.syncSmartlinks(apiKey);

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _isLoading = false;
        _isError = false;
        _statusMessage = result.message;
      });

      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      Navigator.of(context).pop(true);
      widget.onSuccess?.call();
    } else {
      setState(() {
        _isLoading = false;
        _isError = true;
        _statusMessage = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A24) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.vpn_key_rounded,
                    color: cs.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Adsterra API Key',
                        style: getBoldStyle(
                          fontSize: 18,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Setup publisher token & smartlinks',
                        style: getRegularStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isDismissible)
                  IconButton(
                    icon: Icon(Icons.close, color: cs.onSurface.withValues(alpha: 0.6)),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // Instruction Note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Entering your API key will clear your previous links and import up to 20 direct smartlinks from your Adsterra account into your feed.',
                      style: getRegularStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // API Key Input Field
            TextField(
              controller: _keyController,
              enabled: !_isLoading,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'Paste Adsterra API Token...',
                hintStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontSize: 13,
                  fontFamily: 'sans-serif',
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF12121A)
                    : const Color(0xFFF4F6F9),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: cs.onSurface.withValues(alpha: 0.15),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  tooltip: 'Paste from clipboard',
                  onPressed: _isLoading ? null : _pasteFromClipboard,
                ),
              ),
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _isError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 16,
                      color: _isError ? Colors.redAccent : Colors.greenAccent,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: getRegularStyle(
                        fontSize: 12,
                        color: _isError ? Colors.redAccent : (_isLoading ? cs.primary : Colors.greenAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _startSync,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.sync_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Save & Import Smartlinks',
                            style: getBoldStyle(
                              fontSize: 14,
                              color: Colors.white,
                            ),
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
}
