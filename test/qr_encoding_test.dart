import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:teploservice_flutter/utils/cp1251.dart';

/// Проверка, что в QR уходят именно CP1251-байты.
///
/// Прямо прочитать матрицу QR в тесте нельзя, но можно сравнить объём
/// данных: кириллица в UTF-8 занимает вдвое больше байтов, и это
/// меняется `typeNumber` (версию) кода. Если версии совпали — значит
/// кодирование снова UTF-8.
void main() {
  const qrString =
      'ST00011|Name=ООО Теплосервис Дагестан|PersonalAcc=40702810500000001234'
      '|BankName=ОТДЕЛЕНИЕ №8590 СБЕРБАНКА|BIC=048209615'
      '|CorrespAcc=30101810500000000615|PersAcc=7-15|PaymPeriod=08.2026'
      '|Sum=124805|Purpose=Оплата ЖКУ л/с 7-15 за Август 2026';

  test('CP1251-байты дают меньший QR, чем UTF-8 строка', () {
    final cp = QrCode.fromUint8List(
      data: cp1251Encode(qrString),
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    // Так работает QrImageView(data: ...) — через utf8.encode.
    final utf = QrCode.fromData(
      data: qrString,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );

    expect(cp.typeNumber, lessThan(utf.typeNumber),
        reason: 'версии равны — значит кодирование не CP1251');
  });

  test('число байтов совпадает с длиной строки (1 байт на символ)', () {
    // В CP1251 каждый символ — ровно один байт. Это и есть признак,
    // что кириллица не раздулась в UTF-8.
    expect(cp1251Encode(qrString).length, qrString.runes.length);
  });

  test('QR строится без исключений и валиден', () {
    final qr = QrCode.fromUint8List(
      data: cp1251Encode(qrString),
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    expect(qr.moduleCount, greaterThan(0));
    // Матрица действительно считается — исключение здесь означало бы,
    // что строка не влезла в QR.
    expect(() => QrImage(qr), returnsNormally);
  });
}
