import 'package:flutter/material.dart';

import 'models/project.dart';
import 'services/api_client.dart';

String assignmentStatusLabel(TaskStatus status) => switch (status) {
  TaskStatus.pending => 'Pendiente',
  TaskStatus.inProgress => 'En curso',
  TaskStatus.completed => 'Terminado',
};

class TaskAssignmentsPage extends StatefulWidget {
  const TaskAssignmentsPage({
    super.key,
    required this.api,
    required this.projectId,
    required this.task,
    required this.onUpdated,
  });

  final ApiClient api;
  final int projectId;
  final ProjectTask task;
  final ValueChanged<ProjectTask> onUpdated;

  @override
  State<TaskAssignmentsPage> createState() => _TaskAssignmentsPageState();
}

class _TaskAssignmentsPageState extends State<TaskAssignmentsPage> {
  late ProjectTask _task;
  late Future<List<AssignmentCandidate>> _candidates;
  late Set<int> _selected;
  bool _busy = false;

  bool get _hasChanges => !_sameIds(
    _selected,
    _task.assignments.map((assignment) => assignment.userId).toSet(),
  );

  bool _sameIds(Set<int> first, Set<int> second) =>
      first.length == second.length && first.containsAll(second);

  TaskAssignment? _assignmentFor(int userId) {
    for (final assignment in _task.assignments) {
      if (assignment.userId == userId) return assignment;
    }
    return null;
  }

  String _subtitleFor(AssignmentCandidate person) {
    final assignment = _assignmentFor(person.userId);
    if (assignment != null) return assignmentStatusLabel(assignment.status);
    return person.isMe ? 'Tu cuenta' : '';
  }

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _selected = _task.assignments.map((assignment) => assignment.userId).toSet();
    _candidates = widget.api.getAssignmentCandidates(widget.projectId);
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error.toString().replaceFirst('Exception: ', '')),
    ));
  }

  void _apply(ProjectTask updated) {
    setState(() {
      _task = updated;
      _selected = updated.assignments.map((assignment) => assignment.userId).toSet();
    });
    widget.onUpdated(updated);
  }

  Future<bool> _save() async {
    if (_busy) return false;
    if (!_task.canManage) return false;
    if (!_hasChanges) return true;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.setTaskAssignments(
        widget.projectId, _task.id!, _selected.toList()..sort(),
      );
      if (!mounted) return false;
      _apply(updated);
      return true;
    } catch (error) {
      if (mounted) _showError(error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeMyStatus(int userId, TaskStatus status) async {
    if (_busy || _hasChanges) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.setMyAssignmentStatus(
        widget.projectId, _task.id!, userId, status,
      );
      if (mounted) _apply(updated);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmLeaving() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reparto sin guardar'),
        content: const Text('¿Quieres guardar los cambios antes de salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      if (await _save() && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } else if (choice == 'discard') {
      setState(() => _selected = _task.assignments.map((a) => a.userId).toSet());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_hasChanges && !_busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_busy && _hasChanges) _confirmLeaving();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Reparto y avance'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_task.canManage)
            TextButton.icon(
              onPressed: _hasChanges ? _save : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
        ],
      ),
      body: FutureBuilder<List<AssignmentCandidate>>(
        future: _candidates,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No se pudo cargar el equipo.'),
                  TextButton(
                    onPressed: () => setState(() {
                      _candidates = widget.api.getAssignmentCandidates(widget.projectId);
                    }),
                    child: const Text('Reintentar'),
                  ),
                ],
              ));
            }
            return const Center(child: CircularProgressIndicator());
          }
          final candidates = snapshot.data!;
          AssignmentCandidate? mine;
          for (final candidate in candidates) {
            if (candidate.isMe) {
              mine = candidate;
              break;
            }
          }
          final myAssignment = mine == null ? null : _assignmentFor(mine.userId);
          return Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_task.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(_task.canManage
                    ? 'Selecciona quién trabajará en esta tarea. Puede haber varios responsables.'
                    : 'Solo el creador del proyecto puede repartir la tarea.'),
                const SizedBox(height: 16),
                for (final person in candidates)
                  CheckboxListTile(
                    title: Text(person.displayName),
                    subtitle: Text(_subtitleFor(person)),
                    value: _selected.contains(person.userId),
                    onChanged: _busy || !_task.canManage ? null : (checked) => setState(() {
                      if (checked == true) {
                        _selected.add(person.userId);
                      } else {
                        _selected.remove(person.userId);
                      }
                    }),
                  ),
                if (candidates.length == 1)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Añade integrantes desde Equipo para repartir la tarea.'),
                  ),
                const Divider(height: 36),
                Text('Mi avance', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_hasChanges)
                  const Text('Guarda primero el reparto para actualizar tu avance.')
                else if (myAssignment == null)
                  const Text('No tienes esta tarea asignada.')
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final status in TaskStatus.values)
                        ChoiceChip(
                          label: Text(assignmentStatusLabel(status)),
                          selected: myAssignment.status == status,
                          onSelected: _busy ? null : (_) => _changeMyStatus(mine!.userId, status),
                        ),
                    ],
                  ),
              ],
            ),
          ));
        },
      ),
    ),
  );
}
