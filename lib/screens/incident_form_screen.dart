import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/incident_models.dart';
import '../providers/incident_form_controller.dart';
import '../providers/map_providers.dart';
import '../utils/app_theme.dart';
import '../widgets/base_card.dart';
import '../services/user_service.dart';
import '../models/api_models.dart';
import '../models/user_role.dart';
import 'package:intl/intl.dart';

class IncidentFormScreen extends ConsumerStatefulWidget {
  final IncidentResponse? initialIncident;

  const IncidentFormScreen({super.key, this.initialIncident});

  @override
  ConsumerState<IncidentFormScreen> createState() => _IncidentFormScreenState();
}

class _IncidentFormScreenState extends ConsumerState<IncidentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  /// Временное кол-во котлов если у котельной totalBoilersCount не задан
  int _localBoilerCount = 1;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(incidentFormControllerProvider(widget.initialIncident));
    final controller = ref.read(incidentFormControllerProvider(widget.initialIncident).notifier);
    final mapData = ref.watch(mapDataProvider);
    final usersAsync = ref.watch(usersProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.initialIncident == null ? 'НОВЫЙ ИНЦИДЕНТ' : 'РЕДАКТИРОВАНИЕ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final success = await controller.save();
                  if (success && mounted) {
                    Navigator.pop(context);
                  }
                }
              },
              child: const Text('СОХРАНИТЬ', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
                ),
              
              _buildSection(
                title: 'ОСНОВНАЯ ИНФОРМАЦИЯ',
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: state.title,
                      decoration: _inputDecoration('Название / Тип инцидента'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      onChanged: controller.updateTitle,
                      validator: (v) => v == null || v.isEmpty ? 'Обязательное поле' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: state.boilerHouseId,
                      isExpanded: true,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      decoration: _inputDecoration('Организация'),
                      items: mapData.boilerHouses.map((bh) {
                        return DropdownMenuItem(
                          value: bh.id,
                          child: Text(bh.address, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (v) {
                        controller.updateBoilerHouse(v);
                        // Сбрасываем локальный счётчик котлов при смене котельной
                        setState(() => _localBoilerCount = 1);
                      },
                      validator: (v) => v == null ? 'Выберите организацию' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<IncidentStatus>(
                            value: state.status,
                            isExpanded: true,
                            dropdownColor: Theme.of(context).colorScheme.surface,
                            decoration: _inputDecoration('Статус'),
                            items: IncidentStatus.values.map((s) {
                              return DropdownMenuItem(
                                value: s,
                                child: Text(s.title.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) controller.updateStatus(v);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: state.severity,
                            isExpanded: true,
                            dropdownColor: Theme.of(context).colorScheme.surface,
                            decoration: _inputDecoration('Серьезность'),
                            items: ['1', '2', '3'].map((s) {
                              return DropdownMenuItem(
                                value: s,
                                child: Text(s, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) controller.updateSeverity(v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              _buildSection(
                title: 'ОТВЕТСТВЕННЫЙ И СПЕРИОД',
                child: Column(
                  children: [
                    usersAsync.when(
                      data: (users) {
                        return DropdownButtonFormField<int>(
                          value: state.assignedTo,
                          isExpanded: true,
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          decoration: _inputDecoration('Ответственный'),
                          items: [
                            DropdownMenuItem<int>(
                              value: null,
                              child: Text('Не назначен', overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(180), fontSize: 14)),
                            ),
                            ...users.map((u) {
                              return DropdownMenuItem<int>(
                                value: u.id,
                                child: Text(u.formattedDisplayName, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                              );
                            }),
                          ],
                          onChanged: controller.updateAssignedTo,
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (err, stack) => Text('Ошибка загрузки пользователей: $err', style: const TextStyle(color: Colors.red)),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      title: Text('Время создания', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(180), fontSize: 12)),
                      subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(state.createdAt), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      trailing: const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: state.createdAt,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null && mounted) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(state.createdAt),
                          );
                          if (time != null) {
                            controller.updateCreatedAt(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    // ─── Время начала (startedAt) — может быть в будущем ───
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      title: Text('Время начала', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(180), fontSize: 12)),
                      subtitle: Text(
                        state.startedAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(state.startedAt!) : 'Сейчас',
                        style: TextStyle(
                          color: state.startedAt != null && state.startedAt!.isAfter(DateTime.now())
                            ? Colors.orange
                            : Theme.of(context).colorScheme.onSurface,
                          fontWeight: state.startedAt != null && state.startedAt!.isAfter(DateTime.now())
                            ? FontWeight.bold
                            : FontWeight.normal,
                        ),
                      ),
                      trailing: const Icon(Icons.play_arrow_rounded, color: Colors.orange, size: 20),
                      onTap: () async {
                        final initialDate = state.startedAt ?? DateTime.now();
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
                    const SizedBox(height: 16),
                    // ─── Время завершения (finishedAt) — опционально ───
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      title: Text('Время завершения', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(180), fontSize: 12)),
                      subtitle: Text(
                        state.finishedAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(state.finishedAt!) : 'Не указано (бессрочный)',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.finishedAt != null)
                            IconButton(
                              icon: const Icon(Icons.clear, color: Colors.red, size: 18),
                              onPressed: () => controller.updateFinishedAt(null),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          const SizedBox(width: 4),
                          const Icon(Icons.timer_off_outlined, color: Colors.blue, size: 20),
                        ],
                      ),
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
                    ),
                    // ─── Тумблер авто-завершения (показывается когда finishedAt задан) ───
                    if (state.finishedAt != null) ...[
                      const SizedBox(height: 16),
                      SwitchListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        title: Text('Авто-завершение по окончании', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                        subtitle: Text(
                          state.autoResolveOnFinish 
                            ? 'Инцидент автоматически завершится' 
                            : 'Авто-завершение',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(140), fontSize: 12),
                        ),
                        secondary: Icon(
                          Icons.check_circle_outline,
                          color: state.autoResolveOnFinish ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                        value: state.autoResolveOnFinish,
                        onChanged: (value) => controller.updateAutoResolveOnFinish(value),
                        activeColor: Colors.green,
                      ),
                    ],
                    if (state.status == IncidentStatus.resolved || state.status == IncidentStatus.closed) ...[
                      const SizedBox(height: 16),
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        title: Text('Время решения', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(180), fontSize: 12)),
                        subtitle: Text(
                          state.resolvedAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(state.resolvedAt!) : 'Не указано',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface)
                        ),
                        trailing: const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                        onTap: () async {
                          final initialDate = state.resolvedAt ?? DateTime.now();
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
                              controller.updateResolvedAt(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              _buildSection(
                title: 'ЗАТРОНУТЫЕ РЕСУРСЫ И ДОМА',
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text('Остановить ГВС', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      value: state.stopHotWater,
                      onChanged: controller.updateStopHotWater,
                      activeColor: Colors.blue,
                    ),
                    SwitchListTile(
                      title: Text('Остановить отопление', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      value: state.stopHeating,
                      onChanged: controller.updateStopHeating,
                      activeColor: Colors.red,
                    ),
                    Divider(color: Theme.of(context).colorScheme.onSurface.withAlpha(25)),
                    ListTile(
                      title: Text('Выбрать дома', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text(
                        'Выбрано: ${state.affectedHouseIds.length}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(128)),
                      ),
                      trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(140)),
                      onTap: () => _showHouseSelector(context, ref, state, controller),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // --- СОСТОЯНИЕ КОТЛОВ ---
              _buildBoilerSection(context, state, controller, mapData),
              
              const SizedBox(height: 16),

              _buildSection(
                title: 'УВЕДОМЛЕНИЯ ПРИ ПУБЛИКАЦИИ',
                child: Column(
                  children: [
                    DropdownButtonFormField<AudienceType>(
                      value: state.notificationConfig?.type ?? AudienceType.broadcast,
                      isExpanded: true,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      decoration: _inputDecoration('Кому отправить уведомление'),
                      items: [
                        DropdownMenuItem(
                          value: AudienceType.broadcast,
                          child: Text('Всем пользователям', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                        ),
                        DropdownMenuItem(
                          value: AudienceType.roleBased,
                          child: Text('По ролям', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                        ),
                        DropdownMenuItem(
                          value: AudienceType.userBased,
                          child: Text('Выбранным пользователям', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          controller.updateNotificationConfig(
                            NotificationConfig(type: v, userIds: state.notificationConfig?.userIds),
                          );
                        }
                      },
                    ),
                    if (state.notificationConfig?.type == AudienceType.userBased) ...[
                      const SizedBox(height: 16),
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        title: Text('Выбрать получателей', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        subtitle: Text(
                          'Выбрано: ${state.notificationConfig?.userIds?.length ?? 0}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(128)),
                        ),
                        trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(140)),
                        onTap: () => _showUserSelector(context, ref, state, controller),
                      ),
                    ],
                    if (state.notificationConfig?.type == AudienceType.roleBased) ...[
                      const SizedBox(height: 16),
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        title: Text('Выбрать роли', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        subtitle: Text(
                          'Выбрано: ${state.notificationConfig?.roleIds?.length ?? 0}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(128)),
                        ),
                        trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withAlpha(140)),
                        onTap: () => _showRoleSelector(context, ref, state, controller),
                      ),
                    ],
                  ],
                ),
              ),


              const SizedBox(height: 16),
              
              _buildSection(
                title: 'ОПИСАНИЕ',
                child: TextFormField(
                  initialValue: state.description,
                  maxLines: 5,
                  decoration: _inputDecoration('Детали инцидента'),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  onChanged: controller.updateDescription,
                ),
              ),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(128),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        BaseCard(child: child),
      ],
    );
  }

  /// Секция "СОСТОЯНИЕ КОТЛОВ": чипы котлов + тумблер + статус-индикатор
  Widget _buildBoilerSection(
    BuildContext context,
    IncidentFormState state,
    IncidentFormController controller,
    MapDataState mapData,
  ) {
    // Ищем котельную по всему списку (независимо от фильтров)
    final selectedBh = state.boilerHouseId != null
        ? mapData.boilerHouses.where((b) => b.id == state.boilerHouseId).firstOrNull
        : null;
    // Если totalBoilersCount не задан в БД — используем локальный стейт формы
    final serverBoilerCount = selectedBh?.totalBoilersCount;
    final totalBoilers = (serverBoilerCount != null && serverBoilerCount > 0)
        ? serverBoilerCount
        : (state.boilerHouseId != null ? _localBoilerCount : 0);
    final boilerHouseNotSelected = state.boilerHouseId == null;
    final noBoilersConfigured = false; // всегда показываем чипы если котельная выбрана
    final usingLocalCount = serverBoilerCount == null || serverBoilerCount == 0;

    return _buildSection(
      title: 'СОСТОЯНИЕ КОТЛОВ',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Placeholder: котельная не выбрана ──
          if (boilerHouseNotSelected) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurface.withAlpha(100)),
                  const SizedBox(width: 8),
                  Text(
                    'Сначала выберите котельную выше',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ]

          // ── Чипы котлов (всегда если котельная выбрана) ──
          else ...[
            // Предупреждение + ручной счётчик если totalBoilersCount не задан
            if (usingLocalCount) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 15, color: Colors.orange.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Кол-во котлов не задано в котельной. Укажите вручную:',
                        style: TextStyle(color: Colors.orange.shade300, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Уменьшить
                    GestureDetector(
                      onTap: _localBoilerCount > 1
                          ? () => setState(() => _localBoilerCount--)
                          : null,
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.remove, size: 16,
                            color: _localBoilerCount > 1 ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withAlpha(97)),
                        ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '$_localBoilerCount',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    // Увеличить
                    GestureDetector(
                      onTap: _localBoilerCount < 20
                          ? () => setState(() => _localBoilerCount++)
                          : null,
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.add, size: 16,
                            color: _localBoilerCount < 20 ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withAlpha(97)),
                        ),
                    ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Text(
                'Нажмите на котёл чтобы отметить его как неработающий:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
                  fontSize: 12,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(totalBoilers, (index) {
                final boilerNumber = index + 1;
                final isInactive = state.inactiveBoilers.contains(boilerNumber);
                // Чипы ВСЕГДА кликабельны — пользователь может снять котёл с нерабочего
                // даже когда supplyFullyStopped=true (автоустановлен при всех нерабочих)
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
            const SizedBox(height: 14),
          ],

          // ── Тумблер "Услуги поступают" (инверсный — как на iOS) ──
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Услуги поступают',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              state.supplyFullyStopped
                  ? 'Теплоноситель полностью прекращён'
                  : 'Подача в штатном / частичном режиме',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(128),
                fontSize: 12,
              ),
            ),
            secondary: Icon(
              state.supplyFullyStopped
                  ? Icons.cancel_outlined
                  : Icons.check_circle_outline,
              color: state.supplyFullyStopped ? Colors.red : Colors.green,
              size: 22,
            ),
            // Инверсия: тумблер ВКЛ = услуги поступают = supplyFullyStopped = false
            value: !state.supplyFullyStopped,
            // Тумблер заблокирован если: все котлы нерабочие ИЛИ хотя бы один ресурс остановлен
            onChanged: ((state.inactiveBoilers.length >= totalBoilers && totalBoilers > 0) || state.stopHotWater || state.stopHeating)
                ? null
                : (value) => controller.updateSupplyFullyStopped(!value, totalBoilers: totalBoilers),
            activeColor: Colors.green,
            inactiveThumbColor: Colors.red.shade400,
            inactiveTrackColor: Colors.red.shade900.withAlpha(100),
          ),

          // ── Статус-индикатор ──
          const SizedBox(height: 8),
          _buildBoilerStatusIndicator(context, state, totalBoilers),
        ],
      ),
    );
  }

  /// Цветной статус-индикатор в нижней части секции
  Widget _buildBoilerStatusIndicator(
    BuildContext context,
    IncidentFormState state,
    int totalBoilers,
  ) {
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
    } else if (totalBoilers > 0 && state.inactiveBoilers.length >= totalBoilers) {
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
                Text(
                  statusText,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subText,
                  style: TextStyle(
                    color: textColor.withAlpha(180),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  InputDecoration _inputDecoration(String label) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: cs.onSurface.withAlpha(128)),
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  void _showHouseSelector(
    BuildContext context,
    WidgetRef ref,
    IncidentFormState state,
    IncidentFormController controller,
  ) {
    if (state.boilerHouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала выберите котельную')),
      );
      return;
    }

    final mapData = ref.read(mapDataProvider);
    // Filter locations by boiler house ID if available in data
    final relevantHouses = mapData.locations.where((loc) => loc.boilerHouseId == state.boilerHouseId).toList();

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
            final modalState = modalRef.watch(incidentFormControllerProvider(widget.initialIncident));
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
                            'ВЫБОР ДОМОВ',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              final allIds = relevantHouses.map((h) => h.id).toList();
                              controller.toggleAllHouses(allIds);
                            },
                            child: const Text('Выбрать все', style: TextStyle(color: Colors.blue)),
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
                            title: Text(house.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                            value: isSelected,
                            onChanged: (v) {
                              controller.toggleHouse(house.id);
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
            final modalState = modalRef.watch(incidentFormControllerProvider(widget.initialIncident));
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
                            title: Text(user.formattedDisplayName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                            subtitle: null,
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
            final modalState = modalRef.watch(incidentFormControllerProvider(widget.initialIncident));
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
}
