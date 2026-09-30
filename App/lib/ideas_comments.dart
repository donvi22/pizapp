import 'package:flutter/material.dart';

import 'models/project.dart';
import 'services/api_client.dart';

void _error(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

class IdeasPage extends StatefulWidget {
  const IdeasPage({super.key, required this.api, required this.projectId,
    required this.onTaskCreated});
  final ApiClient api;
  final int projectId;
  final ValueChanged<ProjectTask> onTaskCreated;

  @override
  State<IdeasPage> createState() => _IdeasPageState();
}

class _IdeasPageState extends State<IdeasPage> {
  late Future<List<ProjectIdea>> _ideas;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() {
    _ideas = widget.api.getIdeas(widget.projectId);
  });

  Future<void> _create() async {
    final title = TextEditingController();
    final description = TextEditingController();
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nueva idea'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, maxLength: 200,
                decoration: const InputDecoration(labelText: 'Título')),
              TextField(controller: description, maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Crear')),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      if (title.text.trim().isEmpty) {
        _error(context, 'Escribe un título.');
        return;
      }
      await widget.api.createIdea(widget.projectId, title.text.trim(),
        description.text.trim());
      if (mounted) {
        _refresh();
      }
    } catch (error) {
      if (mounted) {
        _error(context, error);
      }
    } finally {
      title.dispose();
      description.dispose();
    }
  }

  Future<void> _open(ProjectIdea idea) async {
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (_) => IdeaDetailPage(api: widget.api, projectId: widget.projectId,
        idea: idea, onTaskCreated: widget.onTaskCreated),
    ));
    if (mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ideas'), actions: [
      IconButton(tooltip: 'Actualizar', onPressed: _refresh,
        icon: const Icon(Icons.refresh)),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _create,
      icon: const Icon(Icons.add), label: const Text('Nueva idea')),
    body: FutureBuilder<List<ProjectIdea>>(
      future: _ideas,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final ideas = snapshot.data!;
        if (ideas.isEmpty) return const Center(child: Text('Todavía no hay ideas'));
        return ListView.builder(
          padding: const EdgeInsets.all(16), itemCount: ideas.length,
          itemBuilder: (context, index) {
            final idea = ideas[index];
            return Card(child: ListTile(
              title: Text(idea.title),
              subtitle: Text(idea.convertedTaskId == null
                ? idea.description.isEmpty ? 'Abierta' : idea.description
                : 'Convertida en tarea', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(idea),
            ));
          },
        );
      },
    ),
  );
}

class IdeaDetailPage extends StatefulWidget {
  const IdeaDetailPage({super.key, required this.api, required this.projectId,
    required this.idea, required this.onTaskCreated});
  final ApiClient api;
  final int projectId;
  final ProjectIdea idea;
  final ValueChanged<ProjectTask> onTaskCreated;

  @override
  State<IdeaDetailPage> createState() => _IdeaDetailPageState();
}

class _IdeaDetailPageState extends State<IdeaDetailPage> {
  bool _converting = false;
  int? _convertedTaskId;

  @override
  void initState() {
    super.initState();
    _convertedTaskId = widget.idea.convertedTaskId;
  }

  Future<void> _deleteIdea() async {
    if (_converting || !widget.idea.canDelete) return;
    final accepted = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar idea'),
        content: Text('¿Eliminar «${widget.idea.title}» y todos sus comentarios? '
          'Si ya se convirtió en tarea, la tarea seguirá existiendo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _converting = true);
    try {
      await widget.api.deleteIdea(widget.projectId, widget.idea.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        _error(context, error);
      }
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Future<void> _convert() async {
    final accepted = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Convertir en tarea'),
        content: const Text('Se creará una tarea con el título y la descripción de esta idea.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Crear tarea')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _converting = true);
    try {
      final task = await widget.api.convertIdea(widget.projectId, widget.idea.id);
      if (!mounted) return;
      setState(() => _convertedTaskId = task.id);
      widget.onTaskCreated(task);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea creada a partir de la idea')));
    } catch (error) {
      if (mounted) {
        _error(context, error);
      }
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Idea'), actions: [
      if (widget.idea.canDelete)
        IconButton(tooltip: 'Eliminar idea',
          onPressed: _converting ? null : _deleteIdea,
          icon: const Icon(Icons.delete_outline)),
    ]),
    body: SafeArea(child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.idea.title, style: Theme.of(context).textTheme.headlineSmall),
        if (widget.idea.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(widget.idea.description),
        ],
        const SizedBox(height: 12),
        if (_convertedTaskId == null && widget.idea.canConvert)
          FilledButton.icon(onPressed: _converting ? null : _convert,
            icon: const Icon(Icons.add_task), label: const Text('Convertir en tarea'))
        else if (_convertedTaskId != null)
          const Chip(label: Text('Convertida en tarea')),
        if (_convertedTaskId == null && !widget.idea.canConvert)
          const Text('Pendiente de aprobación por el creador del proyecto.'),
        const Divider(),
        Text('Comentarios', style: Theme.of(context).textTheme.titleMedium),
        Expanded(child: CommentsPanel(api: widget.api,
          projectId: widget.projectId, ideaId: widget.idea.id)),
      ]),
    )),
  );
}

class TaskCommentsPage extends StatelessWidget {
  const TaskCommentsPage({super.key, required this.api, required this.projectId,
    required this.taskId});
  final ApiClient api;
  final int projectId;
  final int taskId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Comentarios de la tarea')),
    body: SafeArea(child: Padding(padding: const EdgeInsets.all(12),
      child: CommentsPanel(api: api, projectId: projectId, taskId: taskId))),
  );
}

class CommentsPanel extends StatefulWidget {
  const CommentsPanel({super.key, required this.api, required this.projectId,
    this.taskId, this.ideaId});
  final ApiClient api;
  final int projectId;
  final int? taskId;
  final int? ideaId;

  @override
  State<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<CommentsPanel> {
  final _controller = TextEditingController();
  late Future<List<ProjectComment>> _comments;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
    _comments = widget.api.getComments(widget.projectId,
      taskId: widget.taskId, ideaId: widget.ideaId);
  });

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.addComment(widget.projectId, text,
        taskId: widget.taskId, ideaId: widget.ideaId);
      if (!mounted) return;
      _controller.clear();
      _refresh();
    } catch (error) {
      if (mounted) {
        _error(context, error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(ProjectComment comment) async {
    final accepted = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar comentario'),
        content: const Text('¿Quieres borrar tu comentario?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.api.deleteComment(widget.projectId, comment.id,
        taskId: widget.taskId, ideaId: widget.ideaId);
      if (mounted) {
        _refresh();
      }
    } catch (error) {
      if (mounted) {
        _error(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Expanded(child: FutureBuilder<List<ProjectComment>>(
      future: _comments,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Text('Error: ${snapshot.error}'),
              TextButton(onPressed: _refresh, child: const Text('Reintentar')),
            ],
          ));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final comments = snapshot.data!;
        if (comments.isEmpty) {
          return const Center(child: Text('Aún no hay comentarios'));
        }
        return ListView.builder(itemCount: comments.length,
          itemBuilder: (context, index) {
            final comment = comments[index];
            final date = comment.createdAt.toLocal();
            final dateText = '${date.day}/${date.month}/${date.year} '
              '${date.hour.toString().padLeft(2, '0')}:'
              '${date.minute.toString().padLeft(2, '0')}';
            return Card(child: ListTile(
              title: Text(comment.authorName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(comment.text), Text(dateText,
                  style: Theme.of(context).textTheme.bodySmall)]),
              trailing: comment.canDelete ? IconButton(
                tooltip: 'Borrar comentario', onPressed: () => _delete(comment),
                icon: const Icon(Icons.delete_outline)) : null,
            ));
          },
        );
      },
    )),
    Row(children: [
      Expanded(child: TextField(controller: _controller, maxLength: 2000,
        maxLines: 2, minLines: 1,
        decoration: const InputDecoration(hintText: 'Escribe un comentario'),
        onChanged: (_) => setState(() {}))),
      IconButton(tooltip: 'Enviar', onPressed: _sending ||
          _controller.text.trim().isEmpty ? null : _send,
        icon: const Icon(Icons.send)),
    ]),
  ]);
}
