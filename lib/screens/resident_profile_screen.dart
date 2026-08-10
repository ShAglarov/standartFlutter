import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';
import '../services/resident_auth_service.dart';
import '../models/resident_models.dart';
import '../utils/app_theme.dart';
import 'resident_home_screen.dart';

class ResidentProfileScreen extends ConsumerStatefulWidget {
  const ResidentProfileScreen({super.key});

  @override
  ConsumerState<ResidentProfileScreen> createState() => _ResidentProfileScreenState();
}

class _ResidentProfileScreenState extends ConsumerState<ResidentProfileScreen> {
  ResidentResponse? _profile;
  Map<String, dynamic>? _managementCompany;
  List<Map<String, dynamic>>? _accounts;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      // Try cached profile first
      final cached = ref.read(residentProfileProvider);
      if (cached != null) {
        setState(() {
          _profile = cached;
          _isLoading = false;
        });
      }

      final authService = ref.read(residentAuthServiceProvider);

      // Load profile if not cached
      if (_profile == null) {
        final profile = await authService.getMyProfile();
        ref.read(residentProfileProvider.notifier).set(profile);
        if (mounted) {
          setState(() {
            _profile = profile;
            _isLoading = false;
          });
        }
      }

      // Load management company info
      final mc = await authService.getMyManagementCompany();
      if (mounted) {
        setState(() {
          _managementCompany = mc;
        });
      }

      // Load account info
      final accounts = await authService.getMyAccount();
      if (mounted) {
        setState(() {
          _accounts = accounts;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой профиль'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('Не удалось загрузить профиль'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: AppTheme.primaryBlue.withAlpha(40),
                        child: Text(
                          _initials(_profile!.fullName),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Name
                      Text(
                        _profile!.fullName,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${_profile!.username}',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withAlpha(140),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Info cards
                      _infoCard(theme, Icons.home_outlined, 'Адрес', _profile!.displayAddress),
                      _infoCard(theme, Icons.email_outlined, 'Email', _profile!.email),
                      if (_profile!.phoneNumber != null && _profile!.phoneNumber!.isNotEmpty)
                        _infoCard(theme, Icons.phone_outlined, 'Телефон', _profile!.phoneNumber!),

                      // Management Company section
                      if (_managementCompany != null) ...[
                        const SizedBox(height: 28),
                        _buildManagementCompanySection(theme),
                      ],

                      // Accounts section
                      if (_accounts != null && _accounts!.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _buildAccountsSection(theme),
                      ],

                      const SizedBox(height: 40),

                      // Logout
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Выход'),
                                content: const Text('Вы уверены, что хотите выйти?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Отмена'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Выйти', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref.read(authProvider.notifier).logout();
                              if (context.mounted) {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              }
                            }
                          },
                          icon: const Icon(Icons.logout, color: Colors.red),
                          label: const Text('Выйти', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Секция «Управляющая компания»
  Widget _buildManagementCompanySection(ThemeData theme) {
    final mc = _managementCompany!;
    final name = mc['name'] as String? ?? '';
    final phone = mc['phone'] as String? ?? '';
    final email = mc['email'] as String? ?? '';
    final address = mc['address'] as String? ?? '';
    final director = mc['director'] as String? ?? '';
    final housesCount = mc['houses_count'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.business_outlined, color: AppTheme.primaryBlue, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Управляющая компания',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // MC name card (highlighted)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryBlue.withAlpha(20),
                AppTheme.primaryBlue.withAlpha(8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryBlue.withAlpha(40)),
          ),
          child: Row(
            children: [
              const Icon(Icons.domain, size: 22, color: AppTheme.primaryBlue),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Название',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(140)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name.isNotEmpty ? name : 'Не указано',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Director
        if (director.isNotEmpty)
          _infoCard(theme, Icons.person_outline, 'Руководитель', director),

        // Phone
        if (phone.isNotEmpty)
          _infoCard(theme, Icons.phone_outlined, 'Телефон УК', phone),

        // Email
        if (email.isNotEmpty)
          _infoCard(theme, Icons.email_outlined, 'Email УК', email),

        // Address
        if (address.isNotEmpty)
          _infoCard(theme, Icons.location_on_outlined, 'Адрес УК', address),

        // Houses count stat
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.onSurface.withAlpha(30)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$housesCount',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Домов в обслуживании',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(140)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _housesCountText(housesCount),
                      style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Секция «Лицевой счёт»
  Widget _buildAccountsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_long_outlined, color: Colors.teal, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Лицевой счёт',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Account cards
        for (final acc in _accounts!) ...[
          _buildAccountCard(theme, acc),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildAccountCard(ThemeData theme, Map<String, dynamic> acc) {
    final accountNumber = acc['account_number'] as String? ?? '';
    final fio = acc['fio'] as String? ?? '';
    final address = acc['address'] as String? ?? '';
    final area = acc['area'] as num?;
    final serviceType = acc['service_type'] as String? ?? '';
    final accStatus = acc['status'] as String? ?? '';
    final phone = acc['phone'] as String? ?? '';
    final email = acc['email'] as String? ?? '';
    final jku = acc['jku_identifier'] as String? ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account number (highlighted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.teal.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tag, size: 16, color: Colors.teal),
                const SizedBox(width: 6),
                Text(
                  accountNumber.isNotEmpty ? accountNumber : '—',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (fio.isNotEmpty)
            _accountRow(Icons.person_outline, 'ФИО', fio),
          if (address.isNotEmpty)
            _accountRow(Icons.location_on_outlined, 'Адрес', address),
          if (area != null && area > 0)
            _accountRow(Icons.square_foot, 'Площадь', '${area.toStringAsFixed(1)} м²'),
          if (serviceType.isNotEmpty)
            _accountRow(Icons.build_outlined, 'Услуга', serviceType),
          if (accStatus.isNotEmpty)
            _accountRow(Icons.info_outline, 'Статус', accStatus),
          if (phone.isNotEmpty)
            _accountRow(Icons.phone_outlined, 'Телефон', phone),
          if (email.isNotEmpty)
            _accountRow(Icons.email_outlined, 'Email', email),
          if (jku.isNotEmpty)
            _accountRow(Icons.qr_code, 'ЖКУ', jku),
        ],
      ),
    );
  }

  Widget _accountRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.teal.withAlpha(180)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 1),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(ThemeData theme, IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.primaryBlue),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(140))),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final second = parts.length > 1 ? parts[1][0] : '';
    return '$first$second'.toUpperCase();
  }

  String _housesCountText(int count) {
    if (count % 100 >= 11 && count % 100 <= 19) return '$count домов';
    final lastDigit = count % 10;
    if (lastDigit == 1) return '$count дом';
    if (lastDigit >= 2 && lastDigit <= 4) return '$count дома';
    return '$count домов';
  }
}
