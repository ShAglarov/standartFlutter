import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/resident_auth_service.dart';
import '../widgets/receipt_view.dart';

/// Экран задолженности — красный, на весь экран.
///
/// ЗАЧЕМ ТАКОЙ ЗАМЕТНЫЙ
///     Долг — главное, что жильцу нужно узнать при входе. Карточку
///     среди заявок он пролистывает мимо, поэтому экран перекрывает
///     всё: сумма, за какие месяцы и кнопка получить чек с QR.
///
/// НЕ БЛОКИРУЕТ ПРИЛОЖЕНИЕ
///     Снизу выход в «Мой дом»: заявка на аварию нужна и должнику, а
///     чек — это как раз то, по чему он заплатит. Блокировать их
///     значит мешать оплате.
class ResidentDebtScreen extends ConsumerStatefulWidget {
  final ResidentDebt debt;

  /// Куда уйти по кнопке «Мой дом».
  final VoidCallback onContinue;

  const ResidentDebtScreen({
    super.key,
    required this.debt,
    required this.onContinue,
  });

  @override
  ConsumerState<ResidentDebtScreen> createState() =>
      _ResidentDebtScreenState();
}

class _ResidentDebtScreenState extends ConsumerState<ResidentDebtScreen> {
  bool _busy = false;

  /// Сумма с разделителями: «12 480,50».
  String _money(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return '$buffer,${parts[1]}';
  }

  Future<void> _openReceipt() async {
    final docId = widget.debt.lastDocId;
    if (docId == null) {
      _toast('Чек недоступен: по счёту нет платёжных документов');
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await ref
          .read(residentAuthServiceProvider)
          .getMyReceipt(docId);
      if (!mounted) return;
      // Тот же чек, что выдаёт касса: виджет перенесён целиком.
      await ReceiptView.show(context, receiptData: data);
    } catch (e) {
      _toast('Не удалось получить чек: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debt = widget.debt;
    final address = [
      debt.address,
      if ((debt.apartment ?? '').isNotEmpty) 'кв. ${debt.apartment}',
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return Scaffold(
      // Красный фон на весь экран, а не баннер: это главное сообщение.
      backgroundColor: const Color(0xFFC62828),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 72, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'У ВАС ЗАДОЛЖЕННОСТЬ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '${_money(debt.debt)} ₽',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (debt.debtPeriodLabel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Долг за: ${debt.debtPeriodLabel}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, color: Colors.white),
                  ),
                ],
                const SizedBox(height: 24),
                if (address.isNotEmpty)
                  Text(
                    address,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: Colors.white.withAlpha(220)),
                  ),
                if ((debt.accountNumber ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Лицевой счёт ${debt.accountNumber}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: Colors.white.withAlpha(200)),
                  ),
                ],
                const SizedBox(height: 32),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      height: 2,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white24,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                // Чек с QR — это и есть способ заплатить, поэтому
                // кнопка главная и белая.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _openReceipt,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFC62828),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text(
                      'Получить чек',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : widget.onContinue,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.home_outlined, size: 20),
                    label: const Text('Мой дом'),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Чек содержит QR-код: отсканируйте его в приложении '
                  'банка, чтобы оплатить.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withAlpha(190)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
