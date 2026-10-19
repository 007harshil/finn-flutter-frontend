import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'export_service.dart';

/// How the user responded to the share sheet.
enum ExportDeliveryStatus {
  /// Shared or saved to a destination.
  delivered,

  /// The share sheet was closed without choosing a destination.
  dismissed,

  /// The platform cannot report the outcome (files were still offered).
  unknown,
}

/// Hands generated files to the user. Swappable in tests and for future
/// destinations (e.g. a "Save to Files" picker).
abstract interface class ExportFileSink {
  Future<ExportDeliveryStatus> deliver(List<ExportArtifact> files, {String? subject, Rect? origin});
}

/// Writes files to the app's temporary directory and opens the system
/// share sheet. On the web the files are shared from memory (download).
///
/// Exported files never outlive the share: the copy written here is deleted
/// once the share sheet closes, and [purge] removes anything left behind
/// (run at launch and on sign-out).
class ShareExportFileSink implements ExportFileSink {
  const ShareExportFileSink();

  static const _dirName = 'finn_export';

  /// share_plus copies shared files here on Android (`cacheDir/share_plus`)
  /// and only empties it on the next share.
  static const _pluginDirName = 'share_plus';

  /// Deletes exported files left on this device. Never throws.
  static Future<void> purge() async {
    if (kIsWeb) return;
    try {
      final tmp = await getTemporaryDirectory();
      for (final name in const [_dirName, _pluginDirName]) {
        final dir = Directory('${tmp.path}${Platform.pathSeparator}$name');
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Could not remove exported files: $e');
    }
  }

  static Future<void> _deleteDir(Directory? dir) async {
    if (dir == null) return;
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Could not remove exported files: $e');
    }
  }

  @override
  Future<ExportDeliveryStatus> deliver(List<ExportArtifact> files, {String? subject, Rect? origin}) async {
    if (files.isEmpty) return ExportDeliveryStatus.unknown;
    final xfiles = <XFile>[];
    Directory? written;
    if (kIsWeb) {
      for (final f in files) {
        xfiles.add(XFile.fromData(f.bytes, mimeType: f.mimeType, name: f.fileName, length: f.bytes.length));
      }
    } else {
      final tmp = await getTemporaryDirectory();
      final dir = written = Directory('${tmp.path}${Platform.pathSeparator}$_dirName');
      if (dir.existsSync()) {
        // Remove files from earlier exports so private data does not linger.
        for (final old in dir.listSync()) {
          try {
            old.deleteSync(recursive: true);
          } catch (_) {}
        }
      } else {
        await dir.create(recursive: true);
      }
      for (final f in files) {
        final file = File('${dir.path}${Platform.pathSeparator}${f.fileName}');
        await file.writeAsBytes(f.bytes, flush: true);
        xfiles.add(XFile(file.path, mimeType: f.mimeType, name: f.fileName));
      }
    }
    final ShareResult result;
    try {
      result = await SharePlus.instance.share(ShareParams(
        files: xfiles,
        subject: subject,
        title: subject,
        fileNameOverrides: kIsWeb ? [for (final f in files) f.fileName] : null,
        sharePositionOrigin: origin,
      ));
    } finally {
      // The sheet has closed: iOS has handed the file over, and Android
      // shares share_plus's own copy. Desktop share targets may read the
      // file later, so there it waits for [purge].
      if (written != null && (Platform.isAndroid || Platform.isIOS)) await _deleteDir(written);
    }
    return switch (result.status) {
      ShareResultStatus.success => ExportDeliveryStatus.delivered,
      ShareResultStatus.dismissed => ExportDeliveryStatus.dismissed,
      ShareResultStatus.unavailable => ExportDeliveryStatus.unknown,
    };
  }
}
