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
class ShareExportFileSink implements ExportFileSink {
  const ShareExportFileSink();

  @override
  Future<ExportDeliveryStatus> deliver(List<ExportArtifact> files, {String? subject, Rect? origin}) async {
    if (files.isEmpty) return ExportDeliveryStatus.unknown;
    final xfiles = <XFile>[];
    if (kIsWeb) {
      for (final f in files) {
        xfiles.add(XFile.fromData(f.bytes, mimeType: f.mimeType, name: f.fileName, length: f.bytes.length));
      }
    } else {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}${Platform.pathSeparator}finn_export');
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
    final result = await SharePlus.instance.share(ShareParams(
      files: xfiles,
      subject: subject,
      title: subject,
      fileNameOverrides: kIsWeb ? [for (final f in files) f.fileName] : null,
      sharePositionOrigin: origin,
    ));
    return switch (result.status) {
      ShareResultStatus.success => ExportDeliveryStatus.delivered,
      ShareResultStatus.dismissed => ExportDeliveryStatus.dismissed,
      ShareResultStatus.unavailable => ExportDeliveryStatus.unknown,
    };
  }
}
