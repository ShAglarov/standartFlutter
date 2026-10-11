/// Приведение имени файла к виду, допустимому во всех ОС.
///
/// ЗАЧЕМ
///   Windows запрещает в пути символы `\ / : * ? " < > |`, а macOS и Linux
///   их спокойно принимают. Из-за этого имя с двоеточием (например из
///   `DateTime.toIso8601String()` — «2026-10-08T14:30») работало на Mac и
///   iOS, а на Windows падало с «Invalid argument(s): Illegal character in
///   path». Имена приходят и с сервера (заголовок Content-Disposition),
///   поэтому чистить их нужно всегда, а не надеяться на источник.
library;

/// Символы, запрещённые в именах файлов Windows.
final RegExp _illegal = RegExp(r'[\\/:*?"<>|]');

/// Управляющие символы — недопустимы во всех файловых системах.
final RegExp _control = RegExp(r'[\x00-\x1f\x7f]');

/// Зарезервированные имена устройств Windows: файл с таким именем создать
/// нельзя, даже с расширением (CON.txt тоже запрещён).
const _reserved = <String>{
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Возвращает безопасное имя файла.
///
/// Кириллица, пробелы, дефисы и точки сохраняются — имена вроде
/// «Лицевые счета 20261008_1430.xlsx» остаются читаемыми.
///
/// [fallback] используется, если после чистки ничего не осталось.
String safeFileName(String? name, {String fallback = 'file'}) {
  var result = (name ?? '').trim();

  // Отрезаем путь, если он просочился: сервер мог прислать
  // «../../etc/passwd» или «C:\Windows\x.xlsx» в Content-Disposition.
  final lastSlash = result.lastIndexOf(RegExp(r'[\\/]'));
  if (lastSlash >= 0) result = result.substring(lastSlash + 1);

  result = result.replaceAll(_control, '').replaceAll(_illegal, '_');

  // Windows молча отбрасывает точки и пробелы в конце имени, из-за чего
  // путь, который мы создали, и путь, который получился, расходятся.
  result = result.replaceAll(RegExp(r'[. ]+$'), '');

  if (result.isEmpty || result == '.' || result == '..') {
    return fallback;
  }

  // Зарезервированное имя — добавляем подчёркивание к основе.
  final dot = result.lastIndexOf('.');
  final stem = dot > 0 ? result.substring(0, dot) : result;
  final ext = dot > 0 ? result.substring(dot) : '';
  if (_reserved.contains(stem.toUpperCase())) {
    result = '${stem}_$ext';
  }

  // Ограничение файловых систем — 255 байт на элемент пути. Режем основу,
  // расширение сохраняем: по нему открывается нужная программа.
  const maxLength = 120;
  if (result.length > maxLength) {
    final keep = maxLength - ext.length;
    result = (keep > 0 ? stem.substring(0, keep) : stem.substring(0, maxLength)) + ext;
  }

  return result;
}

/// Метка времени для имени файла: `20261008_1430`.
///
/// Намеренно без двоеточий, в отличие от `toIso8601String()`.
String fileTimeStamp([DateTime? moment]) {
  final d = moment ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
}
