import 'package:flutter/material.dart';

import 'models/project.dart';
import 'services/api_client.dart';

class ProjectActivityPanel extends StatefulWidget {
  const ProjectActivityPanel({super.key, required this.api, required this.projectId});
  final ApiClient api;
  final int projectId;

  @override
  State<ProjectActivityPanel> createState() => _ProjectActivityPanelState();
}

class _ProjectActivityPanelState extends State<ProjectActivityPanel> {
  final List<ProjectActivity> _items = [];
  int? _nextOffset = 0;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    final offset = reset ? 0 : _nextOffset;
    if (offset == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.getProjectActivity(widget.projectId, offset: offset);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.results);
        _nextOffset = page.nextOffset;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _iconFor(String action) {
    if (action.startsWith('task_') || action == 'assignment_progress') {
      return Icons.assignment_outlined;
    }
    if (action.startsWith('idea_')) return Icons.lightbulb_outline;
    if (action.startsWith('milestone_')) return Icons.outlined_flag;
    if (action.startsWith('member_')) return Icons.group_outlined;
    if (action == 'attachment_added') return Icons.attach_file;
    return Icons.history;
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('No se pudo cargar el historial.'),
        TextButton(onPressed: () => _load(reset: true), child: const Text('Reintentar')),
      ]));
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
          SizedBox(height: 100),
          Center(child: Text('Los cambios nuevos del proyecto aparecerán aquí.')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            if (_loading) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
            }
            if (_error != null) {
              return Center(child: TextButton(onPressed: _load,
                child: const Text('Error al cargar. Reintentar')));
            }
            if (_nextOffset == null) {
              return const SizedBox(height: 20);
            }
            return Center(child: TextButton(onPressed: _load,
              child: const Text('Cargar cambios anteriores')));
          }
          final activity = _items[index];
          return Card(child: ListTile(
            leading: Icon(_iconFor(activity.action)),
            title: Text(activity.actorName),
            subtitle: Text('${activity.description}\n${_date(activity.createdAt)}'),
            isThreeLine: true,
          ));
        },
      ),
    );
  }
}
