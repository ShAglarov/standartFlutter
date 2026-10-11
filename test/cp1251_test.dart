import 'package:flutter_test/flutter_test.dart';
import 'package:teploservice_flutter/utils/cp1251.dart';

/// Эталон — вывод Python `str.encode('cp1251', errors='replace')`.
/// Если эти байты разойдутся, банк снова покажет каракули.
void main() {
  test('QR-строка кодируется побайтово как в Python cp1251', () {
    const input =
        'ST00011|Name=ООО Теплосервис Дагестан|BankName=ОТДЕЛЕНИЕ №8590 '
        'СБЕРБАНКА|Purpose=Оплата ЖКУ л/с 7-15 за Август 2026|Ёё«»';

    // python3 -c "...encode('cp1251')...hex(' ')"
    const expectedHex =
        '53 54 30 30 30 31 31 7c 4e 61 6d 65 3d ce ce ce 20 d2 e5 ef eb ee '
        'f1 e5 f0 e2 e8 f1 20 c4 e0 e3 e5 f1 f2 e0 ed 7c 42 61 6e 6b 4e 61 '
        '6d 65 3d ce d2 c4 c5 cb c5 cd c8 c5 20 b9 38 35 39 30 20 d1 c1 c5 '
        'd0 c1 c0 cd ca c0 7c 50 75 72 70 6f 73 65 3d ce ef eb e0 f2 e0 20 '
        'c6 ca d3 20 eb 2f f1 20 37 2d 31 35 20 e7 e0 20 c0 e2 e3 f3 f1 f2 '
        '20 32 30 32 36 7c a8 b8 ab bb';

    final expected = expectedHex
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => int.parse(s, radix: 16))
        .toList();

    expect(cp1251Encode(input), equals(expected));
  });

  test('кириллица уходит в 0xC0..0xFF, а не в UTF-8', () {
    // «Дагестан» в CP1251 — 8 байт. В UTF-8 было бы 16, и именно это
    // давало каракули «Р”Р°РіРµСЃС‚Р°РЅ».
    final bytes = cp1251Encode('Дагестан');
    expect(bytes.length, 8);
    expect(bytes.first, 0xC4); // Д
    expect(bytes.every((b) => b >= 0xC0), isTrue);
  });

  test('ASCII не меняется', () {
    expect(cp1251Encode('ST00011|Sum=124805'),
        equals('ST00011|Sum=124805'.codeUnits));
  });

  test('символ вне CP1251 теряется как «?», строка остаётся читаемой', () {
    final bytes = cp1251Encode('ООО 🏠 Дом');
    expect(bytes.length, 9);
    expect(bytes[4], 0x3F); // emoji → '?'
    // Остальное на месте: реквизиты читаются, платёж пройдёт.
    expect(bytes.sublist(0, 3), equals([0xCE, 0xCE, 0xCE]));
  });
}
