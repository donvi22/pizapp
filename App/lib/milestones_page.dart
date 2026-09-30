import 'package:flutter/material.dart';

import 'models/project.dart';
import 'services/api_client.dart';

class MilestonesPage extends StatefulWidget {
  const MilestonesPage({
    super.key,
    required this.api,
    required this.projectId,
  });

  final ApiClient api;
  final int projectId;

  @override
  State<MilestonesPage> createState() => _MilestonesPageState();
}

class _MilestoneDraft {
  const _MilestoneDraft(this.name, this.dueDate);
  final String name;
  final DateTime? dueDate;
}

class _MilestonesPageState extends State<MilestonesPage> {
  late Future<void> _loading;
  List<Milestone> _milestones = [];
  List<ProjectTask> _tasks = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loading = _fetch();
  }

  Future<void> _fetch() async {
    final milestones = await widget.api.getMilestones(widget.projectId);
    final tasks = await widget.api.getTasks(widget.projectId);
    if (!mounted) return;
    setState(() {
      _milestones = milestones;
      _tasks = tasks;
    });
  }

  void _refresh() {
    setState(() {
      _loading = _fetch();
    });
  }

  void _showError(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
  );

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _subtitle(Milestone milestone, List<ProjectTask> tasks) {
    final pending = tasks.where((task) => task.status != TaskStatus.completed).length;
    final count = '${tasks.length} tareas · $pending pendientes';
    if (milestone.dueDate == null) return count;
    final date = milestone.dueDate!;
    final today = DateTime.now();
    final diff = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    if (milestone.isClosed) return '$count · Fecha objetivo: ${_dateLabel(date)}';
    if (diff < 0) return '$count · ${-diff} días de retraso';
    if (diff == 0) return '$count · Vence hoy';
    return '$count · ${_dateLabel(date)}';
  }

  Future<_MilestoneDraft?> _showEditor([Milestone? milestone]) async {
    var name = milestone?.name ?? '';
    DateTime? dueDate = milestone?.dueDate;
    return showDialog<_MilestoneDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: Text(milestone == null ? 'Nuevo hito' : 'Editar hito'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                initialValue: name,
                autofocus: true,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Nombre del hito'),
                onChanged: (value) => updateDialog(() => name = value),
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(dueDate == null ? 'Añadir fecha objetivo' : _dateLabel(dueDate!)),
                    onPressed: () async {
                      final chosen = await showDatePicker(
                        context: dialogContext,
                        initialDate: dueDate ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                        helpText: 'Fecha objetivo del hito',
                      );
                      if (chosen != null && dialogContext.mounted) {
                        updateDialog(() => dueDate = chosen);
                      }
                    },
                  ),
                  if (dueDate != null)
                    IconButton(
                      tooltip: 'Quitar fecha',
                      icon: const Icon(Icons.close),
                      onPressed: () => updateDialog(() => dueDate = null),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: name.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, _MilestoneDraft(name.trim(), dueDate)),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit([Milestone? milestone]) async {
    if (milestone != null && !milestone.canEdit) return;
    final draft = await _showEditor(milestone);
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (milestone == null) {
        await widget.api.createMilestone(widget.projectId, draft.name, draft.dueDate);
      } else {
        await widget.api.updateMilestone(widget.projectId, milestone,
          name: draft.name, dueDate: draft.dueDate, isClosed: milestone.isClosed,
        );
      }
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(Milestone milestone) async {
    if (_busy || !milestone.canEdit) return;
    setState(() => _busy = true);
    try {
      await widget.api.updateMilestone(widget.projectId, milestone,
        name: milestone.name,
        dueDate: milestone.dueDate,
        isClosed: !milestone.isClosed,
      );
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Milestone milestone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar hito'),
        content: Text('¿Eliminar «${milestone.name}»? Sus tareas seguirán existiendo sin hito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteMilestone(widget.projectId, milestone.id);
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Hitos'),
      actions: [
        IconButton(tooltip: 'Actualizar hitos', onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh)),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy ? null : () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Nuevo hito'),
    ),
    body: FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No se pudieron cargar los hitos.'),
              TextButton(onPressed: _refresh, child: const Text('Reintentar')),
            ],
          ));
        }
        if (_milestones.isEmpty) {
          return const Center(child: Text('Añade el primer hito del proyecto.'));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            for (final milestone in _milestones)
              Card(child: ExpansionTile(
                leading: Icon(milestone.isClosed ? Icons.flag : Icons.outlined_flag),
                title: Text(milestone.name),
                subtitle: Text('${milestone.isClosed ? 'Cerrado' : 'Abierto'} · '
                    '${_subtitle(milestone, _tasks.where((task) => task.milestoneId == milestone.id).toList())}'),
                trailing: milestone.canEdit ? PopupMenuButton<String>(
                  enabled: !_busy,
                  tooltip: 'Opciones del hito',
                  onSelected: (choice) {
                    if (choice == 'edit') _edit(milestone);
                    if (choice == 'toggle') _toggle(milestone);
                    if (choice == 'delete') _delete(milestone);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'toggle',
                        child: Text(milestone.isClosed ? 'Reabrir' : 'Cerrar')),
                    if (milestone.canDelete)
                      const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ) : null,
                children: [
                  for (final task in _tasks.where((task) => task.milestoneId == milestone.id))
                    ListTile(
                      title: Text(task.title),
                      subtitle: Text(task.status == TaskStatus.completed ? 'Completada' :
                          task.status == TaskStatus.inProgress ? 'En curso' : 'Pendiente'),
                    ),
                  if (!_tasks.any((task) => task.milestoneId == milestone.id))
                    const ListTile(title: Text('Aún no hay tareas en este hito.')),
                  if (milestone.canDelete)
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Eliminar hito'),
                      subtitle: const Text('Las tareas seguirán existiendo sin hito.'),
                      enabled: !_busy,
                      onTap: () => _delete(milestone),
                    ),
                ],
              )),
          ],
        );
      },
    ),
  );
}
