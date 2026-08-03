import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:adnetwork/core/models/app_update_model.dart';
import 'package:adnetwork/layers/data/repo/remote/app_update_repository.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/material.dart';

class AppUpdateService {
  static bool _shouldUpdate(
    String currentVersion,
    String newVersion,
  ) {
    try {
      final currentParts = currentVersion
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      final newParts = newVersion
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();

      final maxLength = currentParts.length > newParts.length
          ? currentParts.length
          : newParts.length;
      for (int i = 0; i < maxLength; i++) {
        final c = i < currentParts.length ? currentParts[i] : 0;
        final n = i < newParts.length ? newParts[i] : 0;
        if (n > c) return true;
        if (c > n) return false;
      }
    } catch (_) {}

    return false;
  }

  static Future<void> checkAndShowUpdate(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final updateRepo = AppUpdateRepository();
      final response = await updateRepo.checkUpdate('adnetworkpro');

      if (response.success == true && response.data != null) {
        final updateData = response.data!;
        final newVersion = updateData.version ?? currentVersion;

        debugPrint('[AppUpdate] Current Version: "$currentVersion", Remote Version: "$newVersion"');
        debugPrint('[AppUpdate] Should update? ${_shouldUpdate(currentVersion, newVersion)}');

        if (_shouldUpdate(currentVersion, newVersion)) {
          if (!context.mounted) return;
          showUpdateDialog(context, updateData);
        }
      }
    } catch (e) {
      debugPrint('[AppUpdate] Background check failed: $e');
    }
  }

  static void showUpdateDialog(BuildContext context, AppUpdateModel updateData) {
    final isMandatory = updateData.isMandatory == 1;
    double progress = 0.0;
    bool isDownloading = false;
    bool isDownloaded = false;
    String savedFilePath = '';
    CancelToken? cancelToken;

    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return PopScope(
              canPop: !isMandatory && !isDownloading,
              child: AlertDialog(
                title: const Text('Update Available'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A new version (${updateData.version}) is available. Please update to continue.',
                    ),
                    if (updateData.releaseNotes != null &&
                        updateData.releaseNotes!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Release Notes:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(updateData.releaseNotes!),
                    ],
                    if (isDownloading || isDownloaded)
                      const SizedBox(height: 20),
                    if (isDownloading) ...[
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.withValues(alpha: 0.2),
                        color: Theme.of(dialogContext).primaryColor,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Downloading: ${(progress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    if (isDownloaded)
                      const Center(
                        child: Text(
                          'Download complete! Ready to install.',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                actions: [
                  if (!isMandatory && !isDownloading)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('Later'),
                    ),
                  if (isDownloading)
                    TextButton(
                      onPressed: () {
                        cancelToken?.cancel();
                        setState(() {
                          isDownloading = false;
                          progress = 0.0;
                        });
                      },
                      child: const Text('Cancel'),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDownloaded
                            ? Colors.green
                            : Theme.of(dialogContext).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        if (isDownloaded) {
                          OpenFilex.open(
                            savedFilePath,
                            type: 'application/vnd.android.package-archive',
                          );
                          return;
                        }

                        if (updateData.downloadUrl == null) return;

                        setState(() {
                          isDownloading = true;
                          progress = 0.0;
                        });

                        final cleanUrl = updateData.downloadUrl!.replaceAll(
                          RegExp(r'\s+'),
                          '',
                        );
                        cancelToken = CancelToken();

                        try {
                          final dir = Platform.isAndroid
                              ? (await getExternalStorageDirectory() ??
                                  await getTemporaryDirectory())
                              : await getApplicationSupportDirectory();
                          savedFilePath =
                              '${dir.path}/update_${updateData.version}.apk';

                          await Dio().download(
                            cleanUrl,
                            savedFilePath,
                            cancelToken: cancelToken,
                            onReceiveProgress: (received, total) {
                              if (total != -1) {
                                setState(() {
                                  progress = received / total;
                                });
                              }
                            },
                          );

                          setState(() {
                            isDownloading = false;
                            isDownloaded = true;
                          });

                          OpenFilex.open(
                            savedFilePath,
                            type: 'application/vnd.android.package-archive',
                          );
                        } catch (e) {
                          if (e is DioException && CancelToken.isCancel(e)) {
                            // User cancelled
                          } else {
                            setState(() {
                              isDownloading = false;
                              progress = 0.0;
                            });
                            debugPrint('Download failed: $e');
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Download failed. Please check your connection and try again.',
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },
                      child: Text(
                        isDownloaded ? 'Install Update' : 'Update Now',
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
