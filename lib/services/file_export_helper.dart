import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/safe_filename.dart';

/// Кроссплатформенный экспорт файлов.
/// На десктопе (Windows/Linux/macOS) — диалог "Сохранить как".
/// На мобильных — share sheet.
class FileExportHelper {
  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Экспорт файла: на десктопе — "Сохранить как", на мобильных — share.
  /// [sourceFile] — уже записанный файл во временной папке.
  /// [fileName] — имя файла для диалога сохранения.
  /// [mimeType] — MIME-тип файла.
  /// [subject] — тема для share на мобильных.
  ///
  /// Возвращает путь сохранённого файла (десктоп) или null (мобильный share).
  static Future<String?> exportFile({
    required File sourceFile,
    required String fileName,
    String? mimeType,
    String? subject,
  }) async {
    if (_isDesktop) {
      return _saveFileDesktop(sourceFile, fileName);
    } else {
      await _shareMobile(sourceFile, mimeType, subject);
      return null;
    }
  }

  /// Десктоп: диалог "Сохранить как" через FilePicker.
  static Future<String?> _saveFileDesktop(File sourceFile, String fileName) async {
    // Имя чистим и здесь: оно попадает в диалог «Сохранить как», и
    // Windows отклоняет запрещённые символы \ / : * ? " < > |.
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Сохранить отчёт',
      fileName: safeFileName(fileName),
    );

    if (outputPath == null) return null; // Пользователь отменил

    final outputFile = File(outputPath);
    await sourceFile.copy(outputFile.path);

    // На Windows — открываем проводник с выделением файла
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', outputFile.path]);
    }

    return outputFile.path;
  }

  /// Мобильный: share sheet.
  /// sharePositionOrigin нужен для iPad — без него crash.
  static Future<void> _shareMobile(File sourceFile, String? mimeType, String? subject) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(sourceFile.path, mimeType: mimeType)],
        subject: subject,
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
      ),
    );
  }
}
