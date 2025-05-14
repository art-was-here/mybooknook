import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateService {
  final String owner;
  final String repo;

  UpdateService({
    required this.owner,
    required this.repo,
  });

  Future<Map<String, dynamic>?> checkForUpdates() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Fetch latest release from GitHub
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final latestRelease = json.decode(response.body);
        final latestVersion =
            latestRelease['tag_name'].toString().replaceAll('v', '');

        // Compare versions
        if (_isNewerVersion(currentVersion, latestVersion)) {
          return latestRelease;
        }
      }
      return null;
    } catch (e) {
      print('Error checking for updates: $e');
      return null;
    }
  }

  bool _isNewerVersion(String currentVersion, String latestVersion) {
    final current = currentVersion.split('.').map(int.parse).toList();
    final latest = latestVersion.split('.').map(int.parse).toList();

    // Compare major, minor, patch versions
    for (int i = 0; i < 3; i++) {
      final currentPart = current.length > i ? current[i] : 0;
      final latestPart = latest.length > i ? latest[i] : 0;

      if (latestPart > currentPart) {
        return true;
      } else if (latestPart < currentPart) {
        return false;
      }
    }

    return false; // Versions are equal
  }

  Future<void> showUpdateDialog(
      BuildContext context, Map<String, dynamic> release) async {
    final version = release['tag_name'];
    final releaseNotes = release['body'];

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Available'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Version $version is now available.'),
              const SizedBox(height: 16),
              Text('Release Notes:'),
              const SizedBox(height: 8),
              Text(releaseNotes ?? 'No release notes available'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Later'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _downloadAndInstallUpdate(context, release);
            },
            child: Text('Update Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstallUpdate(
      BuildContext context, Map<String, dynamic> release) async {
    // Request storage permission
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Storage permission is required to download updates')),
      );
      return;
    }

    try {
      // Find APK asset
      final assets = release['assets'] as List;
      Map<String, dynamic>? apkAsset;

      try {
        apkAsset = assets.firstWhere(
          (asset) => asset['name'].toString().endsWith('.apk'),
        ) as Map<String, dynamic>;
      } catch (e) {
        apkAsset = null;
      }

      if (apkAsset == null) {
        // If no APK found, open the release page in browser
        final url = Uri.parse(release['html_url']);
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
        }
        return;
      }

      final downloadUrl = apkAsset['browser_download_url'];
      final fileName = apkAsset['name'];

      // Show download progress
      final progressDialog = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Downloading Update'),
          content: LinearProgressIndicator(),
        ),
      );

      // Get download directory
      final directory = await getExternalStorageDirectory();
      final filePath = '${directory!.path}/$fileName';

      // Download file
      final dio = Dio();
      await dio.download(
        downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            // Update progress dialog if needed
          }
        },
      );

      // Close progress dialog
      Navigator.pop(context);

      // Install APK
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not install update: ${result.message}')),
        );
      }
    } catch (e) {
      print('Error downloading/installing update: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error installing update: $e')),
      );
    }
  }
}
