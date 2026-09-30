import 'package:flutter/material.dart';

import 'models/project.dart';
import 'services/api_client.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.api, required this.onOpenProject});
  final ApiClient api;
  final Future<void> Function(int projectId) onOpenProject;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<AppNotification> _items = [];
  int? _nextOffset = 0;
  int _unreadCount = 0;
  bool _loading = false;
  bool _markingAll = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
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
      if (reset) await widget.api.syncNotifications();
      final batch = await widget.api.getNotifications(offset: offset);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(batch.results);
        _nextOffset = batch.nextOffset;
        _unreadCount = batch.unreadCount;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _readAndOpen(AppNotification item) async {
    try {
      if (!item.isRead) {
        await widget.api.readNotification(item.id);
        if (!mounted) return;
        final index = _items.indexWhere((entry) => entry.id == item.id);
        setState(() {
          if (index >= 0) _items[index] = item.markRead();
          if (_unreadCount > 0) _unreadCount--;
        });
      }
      await widget.onOpenProject(item.projectId);
      if (mounted) await _load(reset: true);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _readAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await widget.api.readAllNotifications();
      if (mounted) {
        setState(() {
          for (var i = 0; i < _items.length; i++) {
            _items[i] = _items[i].markRead();
          }
          _unreadCount = 0;
        });
        await _load(reset: true);
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _showError(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
  );

  String _date(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year} · '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
  }

  IconData _icon(String kind) {
    if (kind == 'assignment') return Icons.assignment_ind_outlined;
    if (kind == 'due_date') return Icons.calendar_today_outlined;
    if (kind == 'idea_comment') return Icons.lightbulb_outline;
    return Icons.comment_outlined;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Avisos'), actions: [
      if (_unreadCount > 0)
        TextButton(onPressed: _markingAll ? null : _readAll,
          child: const Text('Marcar leídos')),
      IconButton(tooltip: 'Actualizar avisos', onPressed: () => _load(reset: true),
        icon: const Icon(Icons.refresh)),
    ]),
    body: _loading && _items.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty && _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('No se pudieron cargar los avisos.'),
              TextButton(onPressed: () => _load(reset: true),
                child: const Text('Reintentar')),
            ]))
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _items.length + 1,
                itemBuilder: (context, index) {
                  if (_items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 96),
                      child: Center(child: Text('Todavía no tienes avisos.')),
                    );
                  }
                  if (index == _items.length) {
                    if (_loading) {
                      return const Center(child: Padding(padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator()));
                    }
                    if (_error != null) {
                      return Center(child: TextButton(onPressed: _load,
                        child: const Text('Error al cargar. Reintentar')));
                    }
                    if (_nextOffset == null) return const SizedBox(height: 16);
                    return Center(child: TextButton(onPressed: _load,
                      child: const Text('Cargar avisos anteriores')));
                  }
                  final item = _items[index];
                  return Card(
                    color: item.isRead ? null : Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: Icon(_icon(item.kind)),
                      title: Text(item.message),
                      subtitle: Text('${item.projectName} · ${_date(item.createdAt)}'),
                      trailing: item.isRead ? null : const Icon(Icons.circle, size: 9),
                      onTap: () => _readAndOpen(item),
                    ),
                  );
                },
              ),
            ),
  );
}
