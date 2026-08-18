import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/incident_models.dart';
import '../models/location_models.dart';
import '../models/user_role.dart';
import '../providers/incident_form_controller.dart';
import '../providers/map_providers.dart';
import '../services/user_service.dart';
import '../utils/app_theme.dart';
import 'package:image_picker/image_picker.dart';

class HouseIncidentFormDialog extends ConsumerStatefulWidget {
  final SavedLocationResponse house;

  const HouseIncidentFormDialog({super.key, required this.house});

  @override
  ConsumerState<HouseIncidentFormDialog> createState() => _HouseIncidentFormDialogState();
}

class _HouseIncidentFormDialogState extends ConsumerState<HouseIncidentFormDialog> {
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(incidentFormControllerProvider(null).notifier);
      if (widget.house.boilerHouseId != null) {
        controller.updateTitle('Инцидент по дому: ${widget.house.name}');
        controller.updateBoilerHouse(widget.house.boilerHouseId!);
        controller.toggleHouse(widget.house.id);
        controller.updateStopHeating(true);
        controller.updateStopHotWater(true);
      } else {
        // This will immediately fail validation if they try to save without selecting one
        controller.setError('Этот дом не привязан к котельной. Выберите котельную на основном экране инцидентов.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(incidentFormControllerProvider(null));
    final controller = ref.read(incidentFormControllerProvider(null).notifier);
    final usersAsync = ref.watch(usersProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 500, // Matching other dialog widths
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface.withAlpha(140)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'Новый инцидент',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  state.isSaving
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : TextButton(
                          onPressed: () async {
                            if (_formKey.currentState?.validate() ?? false) {
                              final success = await controller.save();
                              if (success && mounted) {
                                Navigator.pop(context, true);
                              }
                            }
                          },
                          child: Text('Сохранить', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                        ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16.0),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.errorRed.withOpacity(0.1),
                            border: Border.all(color: AppTheme.errorRed),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppTheme.errorRed),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.errorMessage!, 
                                  style: const TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold)
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildSectionTitle('Основная информация'),
                      _buildContainer(
                        child: Column(
                          children: [
                            _buildRow(
                              'Тип',
                              state.title.isEmpty ? 'Инцидент' : state.title,
                              icon: Icons.list,
                              trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(97), size: 20),
                              onTap: () => _showTypeSelector(context, state, controller),
                            ),
                            _buildDivider(),
                            _buildDropdownRow<IncidentStatus>(
                              'Статус',
                              state.status,
                              IncidentStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.title, style: const TextStyle(color: AppTheme.errorRed)))).toList(),
                              (v) { if (v != null) controller.updateStatus(v); },
                              icon: Icons.flag,
                            ),
                            _buildDivider(),
                            _buildDropdownRow<String>(
                              'Серьёзность',
                              state.severity,
                              ['1', '2', '3'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Color(0xFFFFA726))))).toList(),
                              (v) { if (v != null) controller.updateSeverity(v); },
                              icon: Icons.warning_amber_rounded,
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      _buildSectionTitle('Сроки'),
                      _buildContainer(
                        child: Column(
                          children: [
                            // ─── Начало (startedAt) — может быть в будущем для запланированных ───
                            _buildRow(
                              'Начало', 
                              state.startedAt != null 
                                ? DateFormat('dd.MM.yyyy HH:mm').format(state.startedAt!)
                                : DateFormat('dd.MM.yyyy HH:mm').format(state.createdAt),
                              icon: Icons.play_arrow_rounded,
                              onTap: () async {
                                final initialDate = state.startedAt ?? state.createdAt;
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: initialDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (date != null && mounted) {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(initialDate),
                                  );
                                  if (time != null) {
                                    controller.updateStartedAt(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                                  }
                                }
                              },
                            ),
                            _buildDivider(),
                            // ─── Окончание (finishedAt) — опционально ───
                            InkWell(
                              onTap: () async {
                                final initialDate = state.finishedAt ?? state.startedAt?.add(const Duration(hours: 1)) ?? DateTime.now().add(const Duration(hours: 1));
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: initialDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (date != null && mounted) {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(initialDate),
                                  );
                                  if (time != null) {
                                    controller.updateFinishedAt(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                                  }
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(Icons.stop_rounded, color: Theme.of(context).colorScheme.onSurface.withAlpha(140), size: 20),
                                    const SizedBox(width: 12),
                                    Text('Окончание', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        state.finishedAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(state.finishedAt!) : '—',
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(128), fontSize: 15),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                    if (state.finishedAt != null) ...[
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () => controller.updateFinishedAt(null),
                                        child: const Icon(Icons.clear, color: Colors.red, size: 18),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            _buildDivider(),
                            // ─── Тумблер авто-завершения ───
                            _buildToggleRow(
                              state.autoResolveOnFinish 
                                ? 'Авто-завершение' 
                                : 'Авто-завершение',
                              Icons.check_circle_outline, 
                              state.autoResolveOnFinish ? Colors.green : Colors.grey, 
                              state.autoResolveOnFinish, 
                              (value) {
                                // Если включают автозавершение и нет finishedAt — предлагаем задать
                                if (value && state.finishedAt == null) {
                                  controller.updateAutoResolveOnFinish(value);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Задайте "Окончание" для авто-завершения'), duration: Duration(seconds: 2)),
                                  );
                                } else {
                                  controller.updateAutoResolveOnFinish(value);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      _buildSectionTitle('Затронутые ресурсы и дома'),
                      _buildContainer(
                        child: Column(
                          children: [
                            _buildToggleRow('Остановить ГВС', Icons.water_drop, Colors.blue, state.stopHotWater, controller.updateStopHotWater),
                            _buildDivider(),
                            _buildToggleRow('Остановить отопление', Icons.local_fire_department, Colors.red, state.stopHeating, controller.updateStopHeating),
                            _buildDivider(),
                            _buildRow(
                              'Затронутые дома',
                              'выбрано: ${state.affectedHouseIds.length}',
                              icon: Icons.business,
                              trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(97), size: 20),
                              onTap: () => _showHouseSelector(context, ref, state, controller),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      // ─── СОСТОЯНИЕ КОТЛОВ ───
                      _buildBoilerSection(context, state, controller),
                      
                      const SizedBox(height: 16),
                      _buildSectionTitle('Назначение и уведомления'),
                      _buildContainer(
                        child: Column(
                          children: [
                            usersAsync.when(
                              data: (users) {
                                final assignedUserName = users.where((u) => u.id == state.assignedTo).map((u) => u.formattedDisplayName.split(' • ').first).firstOrNull ?? 'Не назначен';
                                return _buildDropdownRow<int?>(
                                  'Исполнитель',
                                  state.assignedTo,
                                  [
                                    DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('Не назначен', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(180))),
                                    ),
                                    ...users.map((u) {
                                      final label = u.formattedDisplayName.split(' • ').first;
                                      return DropdownMenuItem<int?>(
                                        value: u.id,
                                        child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                                      );
                                    }),
                                  ],
                                  (v) => controller.updateAssignedTo(v),
                                  icon: Icons.person_outline,
                                );
                              },
                              loading: () => const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                              error: (e, st) => Text('Ошибка: $e', style: const TextStyle(color: Colors.red)),
                            ),
                            _buildDivider(),
                            _buildDropdownRow<AudienceType>(
                              'Уведомить (Пуш)',
                              state.notificationConfig?.type ?? AudienceType.broadcast,
                              [
                                DropdownMenuItem(value: AudienceType.broadcast, child: Text('Всем пользователям', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                                DropdownMenuItem(value: AudienceType.roleBased, child: Text('По ролям', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                                DropdownMenuItem(value: AudienceType.userBased, child: Text('По пользователям', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                              ],
                              (v) {
                                if (v != null) {
                                  controller.updateNotificationConfig(NotificationConfig(type: v, userIds: state.notificationConfig?.userIds));
                                }
                              },
                              icon: Icons.notifications_none,
                            ),
                            if (state.notificationConfig?.type == AudienceType.userBased) ...[
                              _buildDivider(),
                              _buildRow(
                                'Выбрать получателей',
                                'выбрано: ${state.notificationConfig?.userIds?.length ?? 0}',
                                icon: Icons.group_add,
                                trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(97), size: 20),
                                onTap: () => _showUserSelector(context, ref, state, controller),
                              ),
                            ],
                            if (state.notificationConfig?.type == AudienceType.roleBased) ...[
                              _buildDivider(),
                              _buildRow(
                                'Выбрать роли',
                                'выбрано: ${state.notificationConfig?.roleIds?.length ?? 0}',
                                icon: Icons.admin_panel_settings,
                                trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(97), size: 20),
                                onTap: () => _showRoleSelector(context, ref, state, controller),
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      _buildSectionTitle('Сведения'),
                      _buildContainer(
                        padding: EdgeInsets.zero,
                        child: TextFormField(
                          initialValue: state.description,
                          maxLines: 4,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Описание инцидента...',
                            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(77)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          onChanged: controller.updateDescription,
                        ),
                      ),

                      const SizedBox(height: 16),
                      _buildSectionTitle('Фотографии'),
                      _buildPhotosSection(state, controller),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildContainer({required Widget child, EdgeInsets padding = const EdgeInsets.all(0)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Theme.of(context).colorScheme.onSurface.withAlpha(13), indent: 48, endIndent: 16);
  }

  Widget _buildRow(String title, String value, {required IconData icon, Widget? trailing, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurface.withAlpha(140), size: 20),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(128), fontSize: 15),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(String title, IconData icon, Color iconColor, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.surface,
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow<T>(
    String title, 
    T value, 
    List<DropdownMenuItem<T>> items, 
    ValueChanged<T?> onChanged, 
    {required IconData icon}
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurface.withAlpha(140), size: 20),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                isExpanded: true,
                alignment: AlignmentDirectional.centerEnd,
                value: value,
                items: items,
                onChanged: onChanged,
                dropdownColor: Theme.of(context).colorScheme.surface,
                icon: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(97), size: 20),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTypeSelector(BuildContext context, IncidentFormState state, IncidentFormController controller) {
    final List<String> incidentTypes = [
      // Основные (частые)
      'Авария котла',
      'Ремонт труб',
      'Плановые работы',
      'Отключение электричества',
      'Отключение газоснабжения',
      // Аварийные
      'Прорыв трубопровода',
      'Утечка газа',
      'Замерзание трубопровода',
      'Авария на теплотрассе',
      'Авария насосного оборудования',
      // Отключения ресурсов
      'Отключение водоснабжения',
      'Отключение канализации',
      'Низкое давление в сети',
      'Перебои с водоснабжением',
      // Техническое обслуживание
      'Замена оборудования',
      'Промывка системы отопления',
      'Опрессовка системы',
      'Ремонт запорной арматуры',
      // Внешние факторы
      'Долг за коммунальные услуги',
      'Предписание надзорного органа',
      'Стихийное бедствие',
      // Всегда последним
      'Свой вариант',
    ];

    // Если текущий тип не в списке стандартных — это кастомный
    final isCurrentCustom = state.title.isNotEmpty &&
        !incidentTypes.where((t) => t != 'Свой вариант').contains(state.title);

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Тип инцидента', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: incidentTypes.length,
                  itemBuilder: (context, index) {
                    final type = incidentTypes[index];
                    final bool isSelected;
                    if (type == 'Свой вариант') {
                      isSelected = isCurrentCustom;
                    } else {
                      isSelected = state.title == type && !isCurrentCustom;
                    }

                    return ListTile(
                      title: Text(
                        type == 'Свой вариант' && isCurrentCustom
                            ? 'Свой вариант: ${state.title}'
                            : type,
                        style: TextStyle(
                          color: isSelected
                              ? AppTheme.primaryBlue
                              : type == 'Свой вариант'
                                  ? AppTheme.primaryBlue
                                  : Theme.of(context).colorScheme.onSurface,
                          fontWeight: type == 'Свой вариант' ? FontWeight.w600 : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      trailing: isSelected ? Icon(Icons.check, color: AppTheme.primaryBlue, size: 20) : null,
                      onTap: () {
                        if (type == 'Свой вариант') {
                          Navigator.pop(context);
                          _showCustomTypeInput(context, state, controller);
                        } else {
                          controller.updateTitle(type);
                          Navigator.pop(context);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCustomTypeInput(BuildContext context, IncidentFormState state, IncidentFormController controller) {
    final textController = TextEditingController(text: state.title.isNotEmpty ? state.title : '');
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Свой вариант'),
          content: TextField(
            controller: textController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Введите тип инцидента',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final text = textController.text.trim();
                if (text.isNotEmpty) {
                  controller.updateTitle(text);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Готово'),
            ),
          ],
        );
      },
    );
  }

  void _showUserSelector(
    BuildContext context,
    WidgetRef ref,
    IncidentFormState state,
    IncidentFormController controller,
  ) {
    final usersAsync = ref.read(usersProvider);
    final users = usersAsync.value ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, modalRef, child) {
            final modalState = modalRef.watch(incidentFormControllerProvider(null));
            final selectedUserIds = Set<int>.from(modalState.notificationConfig?.userIds ?? []);

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ВЫБОР ПОЛЬЗОВАТЕЛЕЙ',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              final allIds = users.map((u) => u.id).toList();
                              final allIncluded = allIds.every((id) => selectedUserIds.contains(id));
                              if (allIncluded) {
                                controller.updateNotificationConfig(NotificationConfig(type: AudienceType.userBased, userIds: []));
                              } else {
                                controller.updateNotificationConfig(NotificationConfig(type: AudienceType.userBased, userIds: allIds));
                              }
                            },
                            child: const Text('Выбрать всех', style: TextStyle(color: Colors.blue)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final isSelected = selectedUserIds.contains(user.id);
                          return CheckboxListTile(
                            title: Text(user.formattedDisplayName.split(' • ').first, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                            subtitle: Text(user.role.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(140), fontSize: 12)),
                            value: isSelected,
                            onChanged: (v) {
                              if (v == true) {
                                selectedUserIds.add(user.id);
                              } else {
                                selectedUserIds.remove(user.id);
                              }
                              controller.updateNotificationConfig(
                                NotificationConfig(type: AudienceType.userBased, userIds: selectedUserIds.toList()),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showRoleSelector(
    BuildContext context,
    WidgetRef ref,
    IncidentFormState state,
    IncidentFormController controller,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, modalRef, child) {
            final modalState = modalRef.watch(incidentFormControllerProvider(null));
            final selectedRoles = Set<String>.from(modalState.notificationConfig?.roleIds ?? []);

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ВЫБОР РОЛЕЙ',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              final allRoles = UserRole.values.map((r) => r.serverValue).toList();
                              final allIncluded = allRoles.every((r) => selectedRoles.contains(r));
                              if (allIncluded) {
                                controller.updateNotificationRoles([]);
                              } else {
                                controller.updateNotificationRoles(allRoles);
                              }
                            },
                            child: const Text('Выбрать все', style: TextStyle(color: Colors.blue)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: UserRole.values.length,
                        itemBuilder: (context, index) {
                          final role = UserRole.values[index];
                          final isSelected = selectedRoles.contains(role.serverValue);
                          return CheckboxListTile(
                            title: Text(role.title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                            value: isSelected,
                            onChanged: (v) {
                              if (v == true) {
                                selectedRoles.add(role.serverValue);
                              } else {
                                selectedRoles.remove(role.serverValue);
                              }
                              controller.updateNotificationRoles(selectedRoles.toList());
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ─── СЕКЦИЯ ФОТОГРАФИЙ ────────────────────────────────────
  // ═══════════════════════════════════════════════════════════

  Widget _buildPhotosSection(IncidentFormState state, IncidentFormController controller) {
    return _buildContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Кнопка добавления фото
          InkWell(
            onTap: () => _pickPhoto(controller),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.add_a_photo, color: Colors.blue.withOpacity(0.7), size: 20),
                  const SizedBox(width: 12),
                  Text('Добавить фото', style: TextStyle(color: Colors.blue, fontSize: 15, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  if (state.pendingPhotoPaths.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${state.pendingPhotoPaths.length}',
                        style: const TextStyle(color: Colors.blue, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(97), size: 20),
                ],
              ),
            ),
          ),
          // Превью выбранных фото
          if (state.pendingPhotoPaths.isNotEmpty) ...[
            _buildDivider(),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: state.pendingPhotoPaths.length,
                itemBuilder: (context, index) {
                  final path = state.pendingPhotoPaths[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            io.File(path),
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  color: Colors.grey[800],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.broken_image, color: Colors.grey, size: 32),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => controller.removePhoto(index),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickPhoto(IncidentFormController controller) async {
    final picker = ImagePicker();
    
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('Галерея', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text('Камера', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final image = await picker.pickImage(
        source: source,
        imageQuality: 70,
      );
      if (image != null) {
        controller.addPhoto(image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора фото: $e')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ─── СЕКЦИЯ СОСТОЯНИЯ КОТЛОВ (идентично iOS) ──────────────
  // ═══════════════════════════════════════════════════════════

  Widget _buildBoilerSection(
    BuildContext context,
    IncidentFormState state,
    IncidentFormController controller,
  ) {
    final mapData = ref.watch(mapDataProvider);
    final selectedBh = state.boilerHouseId != null
        ? mapData.boilerHouses.where((b) => b.id == state.boilerHouseId).firstOrNull
        : null;
    final totalBoilers = selectedBh?.totalBoilersCount ?? 0;

    if (totalBoilers == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Состояние котлов'),
        _buildContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Чипы котлов ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(totalBoilers, (index) {
                    final boilerNumber = index + 1;
                    final isInactive = state.inactiveBoilers.contains(boilerNumber);
                    // Чипы ВСЕГДА кликабельны
                    return GestureDetector(
                      onTap: () => controller.toggleBoiler(boilerNumber, totalBoilers: totalBoilers),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isInactive
                              ? Colors.red.shade900.withAlpha(60)
                              : Colors.green.shade900.withAlpha(60),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isInactive
                                ? Colors.red.shade600
                                : Colors.green.shade600,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          'Котёл $boilerNumber',
                          style: TextStyle(
                            color: isInactive
                                    ? Colors.red.shade300
                                    : Colors.green.shade400,
                            fontSize: 13,
                            fontWeight: isInactive ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              _buildDivider(),

              // ── Тумблер «Услуги поступают» (инверсный) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      state.supplyFullyStopped
                          ? Icons.cancel_outlined
                          : Icons.check_circle_outline,
                      color: state.supplyFullyStopped ? Colors.red : Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Услуги поступают',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15),
                    ),
                    const Spacer(),
                    Switch(
                      value: !state.supplyFullyStopped,
                      onChanged: (state.inactiveBoilers.length >= totalBoilers && totalBoilers > 0)
                          ? null
                          : (value) => controller.updateSupplyFullyStopped(!value, totalBoilers: totalBoilers),
                      activeColor: Theme.of(context).colorScheme.surface,
                      activeTrackColor: Colors.green,
                      inactiveThumbColor: Colors.red.shade400,
                      inactiveTrackColor: Colors.red.shade900.withAlpha(100),
                    ),
                  ],
                ),
              ),

              // ── Статус-индикатор ──
              _buildBoilerStatusBanner(state, totalBoilers),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBoilerStatusBanner(IncidentFormState state, int totalBoilers) {
    if (totalBoilers == 0) return const SizedBox.shrink();

    final Color bgColor;
    final Color textColor;
    final String emoji;
    final String statusText;
    final String subText;

    if (state.supplyFullyStopped) {
      bgColor = Colors.red.withAlpha(30);
      textColor = Colors.red.shade300;
      emoji = '🔴';
      statusText = 'Полная остановка';
      subText = 'Подача полностью прекращена';
    } else if (state.inactiveBoilers.isEmpty) {
      bgColor = Colors.green.withAlpha(25);
      textColor = Colors.green.shade400;
      emoji = '🟢';
      statusText = 'Все котлы работают';
      subText = 'Подача в штатном режиме';
    } else if (state.inactiveBoilers.length >= totalBoilers) {
      bgColor = Colors.red.withAlpha(30);
      textColor = Colors.red.shade300;
      emoji = '🔴';
      statusText = 'Полная остановка';
      subText = 'Все $totalBoilers котлов не работают';
    } else {
      bgColor = Colors.orange.withAlpha(30);
      textColor = Colors.orange.shade300;
      emoji = '🟠';
      statusText = 'Частичная остановка';
      subText = '${state.inactiveBoilers.length} из $totalBoilers котлов не работает';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withAlpha(80)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(subText, style: TextStyle(color: textColor.withAlpha(180), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ─── ВЫБОР ЗАТРОНУТЫХ ДОМОВ ───────────────────────────────
  // ═══════════════════════════════════════════════════════════

  void _showHouseSelector(
    BuildContext context,
    WidgetRef ref,
    IncidentFormState state,
    IncidentFormController controller,
  ) {
    final mapData = ref.read(mapDataProvider);
    final relevantHouses = mapData.locations
        .where((loc) => loc.boilerHouseId == state.boilerHouseId)
        .toList();

    if (relevantHouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет домов привязанных к этой котельной')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, modalRef, child) {
            final modalState = modalRef.watch(incidentFormControllerProvider(null));
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ЗАТРОНУТЫЕ ДОМА',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              controller.toggleAllHouses(
                                relevantHouses.map((h) => h.id).toList(),
                              );
                            },
                            child: Text(
                              relevantHouses.every((h) => modalState.affectedHouseIds.contains(h.id))
                                  ? 'Снять все'
                                  : 'Выбрать все',
                              style: const TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: relevantHouses.length,
                        itemBuilder: (context, index) {
                          final house = relevantHouses[index];
                          final isSelected = modalState.affectedHouseIds.contains(house.id);
                          return CheckboxListTile(
                            title: Text(
                              house.name,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            ),
                            value: isSelected,
                            onChanged: (_) => controller.toggleHouse(house.id),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
