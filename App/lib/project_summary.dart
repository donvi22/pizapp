import 'package:flutter/material.dart';

import 'models/project.dart';
import 'services/api_client.dart';

class ProjectSummaryPanel extends StatefulWidget {
  const ProjectSummaryPanel({super.key, required this.api, required this.projectId});

  final ApiClient api;
  final int projectId;

  @override
  State<ProjectSummaryPanel> createState() => _ProjectSummaryPanelState();
}

class _SummaryData {
  const _SummaryData(this.tasks, this.milestones, this.ideas, this.slots);
  final List<ProjectTask> tasks;
  final List<Milestone> milestones;
  final List<ProjectIdea> ideas;
  final List<ProjectSlot> slots;
}

class _ProjectSummaryPanelState extends State<ProjectSummaryPanel> {
  late Future<_SummaryData> _result;

  @override
  void initState() {
    super.initState();
    _result = _fetch();
  }

  Future<_SummaryData> _fetch() async {
    final tasks = await widget.api.getTasks(widget.projectId);
    final milestones = await widget.api.getMilestones(widget.projectId);
    final ideas = await widget.api.getIdeas(widget.projectId);
    final slots = await widget.api.getProjectSlots(widget.projectId);
    return _SummaryData(tasks, milestones, ideas, slots);
  }

  Future<void> _reload() async {
    final next = _fetch();
    setState(() => _result = next);
    try {
      await next;
    } catch (_) {
      // FutureBuilder muestra el error y ofrece un botón para reintentar.
    }
  }

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) => FutureBuilder<_SummaryData>(
    future: _result,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('No se pudo cargar el resumen.'),
          TextButton(onPressed: _reload, child: const Text('Reintentar')),
        ]));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      final tasks = data.tasks;
      final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
      final pending = tasks.where((task) => task.status == TaskStatus.pending).length;
      final inProgress = tasks.where((task) => task.status == TaskStatus.inProgress).length;
      final unassigned = tasks.where((task) =>
        task.status != TaskStatus.completed && task.assignments.isEmpty).length;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final upcoming = tasks.where((task) =>
        task.status != TaskStatus.completed && task.dueDate != null &&
        !task.dueDate!.isBefore(today)).toList()
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      final overdue = tasks.where((task) =>
        task.status != TaskStatus.completed && task.dueDate != null &&
        task.dueDate!.isBefore(today)).toList()
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      final closedMilestones = data.milestones.where((item) => item.isClosed).length;
      final convertedIdeas = data.ideas.where((item) => item.convertedTaskId != null).length;
      final participants = 1 + data.slots.where((slot) => slot.username != null).length;
      final ratio = tasks.isEmpty ? 0.0 : completed / tasks.length;

      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('Avance del proyecto', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: ratio, minHeight: 10, borderRadius: BorderRadius.circular(10)),
            const SizedBox(height: 8),
            Text('$completed de ${tasks.length} tareas completadas · ${(ratio * 100).round()} %'),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 680 ? 4 : 2;
              final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                _Metric(width: width, number: '$pending', label: 'Pendientes', icon: Icons.pending_actions),
                _Metric(width: width, number: '$inProgress', label: 'En curso', icon: Icons.timelapse),
                _Metric(width: width, number: '$unassigned', label: 'Sin repartir', icon: Icons.person_add_alt_1_outlined),
                _Metric(width: width, number: '${overdue.length}', label: 'Vencidas', icon: Icons.warning_amber_outlined),
              ]);
            }),
            const SizedBox(height: 24),
            Text('Próximos plazos', style: Theme.of(context).textTheme.titleMedium),
            if (upcoming.isEmpty)
              const ListTile(title: Text('No hay tareas con fecha próxima')),
            for (final task in upcoming.take(5))
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('Fecha objetivo: ${_date(task.dueDate!)}'),
              ),
            if (upcoming.length > 5)
              Padding(padding: const EdgeInsets.only(left: 16),
                child: Text('Y ${upcoming.length - 5} tareas más con fecha.')),
            if (overdue.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Tareas vencidas', style: Theme.of(context).textTheme.titleMedium),
              for (final task in overdue.take(5))
                ListTile(
                  leading: Icon(Icons.warning_amber_outlined,
                    color: Theme.of(context).colorScheme.error),
                  title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('Venció el ${_date(task.dueDate!)}'),
                ),
              if (overdue.length > 5)
                Padding(padding: const EdgeInsets.only(left: 16),
                  child: Text('Y ${overdue.length - 5} tareas vencidas más.')),
            ],
            const SizedBox(height: 20),
            Text('Más datos', style: Theme.of(context).textTheme.titleMedium),
            ListTile(leading: const Icon(Icons.outlined_flag), title: const Text('Hitos'),
              trailing: Text('$closedMilestones/${data.milestones.length} cerrados')),
            ListTile(leading: const Icon(Icons.lightbulb_outline), title: const Text('Ideas'),
              trailing: Text('$convertedIdeas/${data.ideas.length} convertidas')),
            ListTile(leading: const Icon(Icons.group_outlined), title: const Text('Participantes'),
              trailing: Text('$participants')),
          ],
        ),
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.width, required this.number,
    required this.label, required this.icon});
  final double width;
  final String number;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20),
        const SizedBox(height: 8),
        Text(number, style: Theme.of(context).textTheme.headlineMedium),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      ]))),
  );
}
