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
        return;
      }
      final authService = ref.read(residentAuthServiceProvider);
      final profile = await authService.getMyProfile();
      ref.read(residentProfileProvider.notifier).set(profile);
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
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
                      if (_profile!.accountNumber != null && _profile!.accountNumber!.isNotEmpty)
                        _infoCard(theme, Icons.receipt_long_outlined, 'Лицевой счёт', _profile!.accountNumber!),
                      _infoCard(theme, Icons.email_outlined, 'Email', _profile!.email),
                      if (_profile!.phoneNumber != null && _profile!.phoneNumber!.isNotEmpty)
                        _infoCard(theme, Icons.phone_outlined, 'Телефон', _profile!.phoneNumber!),

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
}
