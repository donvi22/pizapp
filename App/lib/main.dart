import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'models/project.dart';
import 'models/board_text.dart';
import 'services/api_client.dart';
import 'services/session_store.dart';
import 'task_attachments.dart';
import 'task_canvas.dart';
import 'project_members.dart';
import 'task_assignments.dart';
import 'milestones_page.dart';
import 'ideas_comments.dart';
import 'project_activity.dart';
import 'project_summary.dart';
import 'notifications_page.dart';
void main() => runApp(const Pizapp());
String statusLabel(TaskStatus status) => switch (status) {
  TaskStatus.pending => 'Pendiente',
  TaskStatus.inProgress => 'En curso',
  TaskStatus.completed => 'Completada',
};
String colorLabel(StickyColor color) => switch (color) {
  StickyColor.yellow => 'Amarillo',
  StickyColor.pink => 'Rosa',
  StickyColor.blue => 'Azul',
  StickyColor.green => 'Verde',
  StickyColor.orange => 'Naranja',
};
String taskSummary(ProjectTask task) {
  final status = statusLabel(task.status);
  if (task.assignments.isEmpty) {
    return task.status == TaskStatus.pending ? 'Por repartir · $status' : status;
  }
  return '$status · ${task.assignments.map((a) => a.displayName).join(', ')}';
}

String shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

int daysUntil(DateTime date) {
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  final target = DateTime.utc(date.year, date.month, date.day);
  return target.difference(today).inDays;
}

String? dueDateSummary(ProjectTask task) {
  final due = task.dueDate;
  if (due == null) return null;
  final date = shortDate(due);
  if (task.status == TaskStatus.completed) return 'Fecha objetivo: $date';
  final days = daysUntil(due);
  if (days < 0) return 'Vencida hace ${-days} ${days == -1 ? 'día' : 'días'} · $date';
  if (days == 0) return 'Vence hoy · $date';
  if (days == 1) return 'Vence mañana · $date';
  return 'Faltan $days días · $date';
}

bool isTaskOverdue(ProjectTask task) =>
    task.status != TaskStatus.completed &&
    task.dueDate != null && daysUntil(task.dueDate!) < 0;

int taskSortGroup(ProjectTask task) {
  if (task.status == TaskStatus.pending && task.assignments.isEmpty) return 0;
  if (task.status == TaskStatus.pending) return 1;
  if (task.status == TaskStatus.inProgress) return 2;
  return 3;
}
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString().replaceFirst('Exception: ', '')),
    ),
  );
}
class Pizapp extends StatefulWidget {
  const Pizapp({super.key});
  @override
  State<Pizapp> createState() => _PizappState();
}
class _PizappState extends State<Pizapp> {
  final _api = ApiClient();
  final _sessionStore = SessionStore();
  bool _authenticated = false;
  bool _restoringSession = true;
  Object? _restoreError;
  String? _pendingInvite = Uri.base.queryParameters['invite'];
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    setState(() { _restoringSession = true; _restoreError = null; });
    try {
      final token = await _sessionStore.readToken();
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _authenticated = false);
        return;
      }
      _api.restoreToken(token);
      if (await _api.validateSession()) {
        if (mounted) setState(() => _authenticated = true);
      } else {
        await _sessionStore.clearToken();
        _api.clearToken();
        if (mounted) setState(() => _authenticated = false);
      }
    } catch (error) {
      if (mounted) setState(() => _restoreError = error);
    } finally {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  Future<void> _saveSession() async {
    try {
      await _sessionStore.saveToken(_api.token!);
    } catch (_) {
      _api.clearToken();
      throw Exception('No se pudo guardar la sesión en este dispositivo.');
    }
    if (mounted) setState(() => _authenticated = true);
  }

  Future<void> _logout() async {
    await _sessionStore.clearToken();
    _api.clearToken();
    if (mounted) {
      setState(() { _authenticated = false; _restoreError = null; });
    }
  }

  Future<void> _login(String username, String password) async {
    await _api.login(username, password);
    await _saveSession();
  }
  Future<void> _register(String username, String email, String password) async {
    await _api.register(username, email, password);
    await _saveSession();
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pizapp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: _restoringSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _restoreError != null
          ? Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text('No se pudo comprobar la sesión. Comprueba la conexión con el servidor.',
                        textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _restoreSession, child: const Text('Reintentar')),
                    TextButton(
                      onPressed: () async {
                        try { await _logout(); }
                        catch (error) { if (context.mounted) showError(context, error); }
                      },
                      child: const Text('Cerrar sesión y cambiar de cuenta'),
                    ),
                  ],
                ),
              ),
            )
          : _authenticated
          ? _pendingInvite != null
              ? JoinProjectPage(
                  api: _api,
                  code: _pendingInvite!,
                  onDone: () => setState(() => _pendingInvite = null),
                  onLogout: _logout,
                )
              : ProjectsPage(api: _api, onLogout: _logout)
          : LoginPage(onLogin: _login, onRegister: _register),
    );
  }
}
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, required this.api, required this.onLogout});
  final ApiClient api;
  final Future<void> Function() onLogout;
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}
class _ProjectsPageState extends State<ProjectsPage> {
  List<Project> _projects = [];
  bool _loading = true;
  Object? _loadError;
  int _unreadNotifications = 0;
  @override
  void initState() {
    super.initState();
    _loadProjects();
    _refreshNotifications();
  }
  Future<void> _refreshNotifications() async {
    try {
      await widget.api.syncNotifications();
      final batch = await widget.api.getNotifications();
      if (mounted) setState(() => _unreadNotifications = batch.unreadCount);
    } catch (_) {
      // La lista de proyectos sigue disponible si fallan los avisos.
    }
  }

  Future<void> _openNotificationProject(int projectId) async {
    Project? project;
    for (final item in _projects) {
      if (item.id == projectId) {
        project = item;
        break;
      }
    }
    if (project == null) {
      await _loadProjects();
      if (!mounted) return;
      for (final item in _projects) {
        if (item.id == projectId) {
          project = item;
          break;
        }
      }
    }
    if (project == null || !mounted) {
      if (mounted) showError(context, 'Ya no tienes acceso a este proyecto.');
      return;
    }
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (context) => ProjectTasksPage(
        project: project!, api: widget.api,
        onChanged: () { if (mounted) setState(() {}); },
        onDeleted: () { _loadProjects(); },
      ),
    ));
  }

  Future<void> _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (context) => NotificationsPage(
        api: widget.api, onOpenProject: _openNotificationProject,
      ),
    ));
    if (mounted) await _refreshNotifications();
  }
  Future<void> _loadProjects() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final projects = await widget.api.getProjects();
      if (!mounted) return;
      setState(() => _projects = projects);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
  Future<void> _addProject() async {
    var name = '';
    var selectedColor = StickyColor.yellow;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Nuevo proyecto'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre'),
                onChanged: (value) => name = value,
              ),
              const SizedBox(height: 20),
              const Text('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in StickyColor.values)
                    ChoiceChip(
                      label: Text(colorLabel(color)),
                      backgroundColor: color.value,
                      selectedColor: color.value,
                      selected: selectedColor == color,
                      onSelected: (_) {
                        updateDialog(() => selectedColor = color);
                      },
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
              onPressed: () {
                if (name.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, name.trim());
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    try {
      final project = await widget.api.createProject(
        result,
        selectedColor,
      );
      if (!mounted) return;
      setState(() => _projects.insert(0, project));
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final columns = width < 360 || (width < 700 && textScale > 1.3)
        ? 1 : width < 700 ? 2 : width < 1100 ? 3 : 4;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis proyectos'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar proyectos y avisos',
            onPressed: () { _loadProjects(); _refreshNotifications(); },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Avisos',
            onPressed: _openNotifications,
            icon: _unreadNotifications == 0
              ? const Icon(Icons.notifications_outlined)
              : Badge.count(count: _unreadNotifications,
                  child: const Icon(Icons.notifications_outlined)),
          ),
          IconButton(
            tooltip: 'Cerrar sesión y cambiar de cuenta',
            onPressed: () async {
              try { await widget.onLogout(); }
              catch (error) { if (context.mounted) showError(context, error); }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProject,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo proyecto'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No se pudieron cargar los proyectos.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadProjects,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _projects.isEmpty
                  ? const Center(
                      child: Text('Crea tu primer proyecto con el botón +'),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: GridView.count(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1,
                          children: _projects
                              .map(
                                (project) => ProjectCard(
                                  project: project,
                                  api: widget.api,
                                  onChanged: () => setState(() {}),
                                  onDeleted: () { _loadProjects(); },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
    );
  }
}
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.api,
    required this.onChanged,
    required this.onDeleted,
  });
  final Project project;
  final ApiClient api;
  final VoidCallback onChanged;
  final VoidCallback onDeleted;
  @override
  Widget build(BuildContext context) {
    final taskLabel = project.totalCount == 1 ? 'tarea' : 'tareas';
    final completedLabel =
        project.completedCount == 1 ? 'completada' : 'completadas';
    return Card(
      color: project.color,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => ProjectTasksPage(
                project: project,
                api: api,
                onChanged: onChanged,
                onDeleted: onDeleted,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    project.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${project.totalCount} $taskLabel\n'
                '${project.completedCount} $completedLabel',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class ProjectTasksPage extends StatefulWidget {
  const ProjectTasksPage({
    super.key,
    required this.project,
    required this.api,
    required this.onChanged,
    required this.onDeleted,
  });
  final Project project;
  final ApiClient api;
  final VoidCallback onChanged;
  final VoidCallback onDeleted;
  @override
  State<ProjectTasksPage> createState() => _ProjectTasksPageState();
}
class _ProjectTasksPageState extends State<ProjectTasksPage> {
  int _selectedTab = 0;
  bool _refreshing = false;
  bool _deleting = false;

  Future<void> _deleteProject() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar proyecto'),
        content: Text('¿Eliminar «${widget.project.name}»? Se borrarán todas sus '
          'tareas, ideas, hitos, comentarios y archivos adjuntos. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar proyecto')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.api.deleteProject(widget.project.id!);
      if (!mounted) return;
      widget.onDeleted();
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _refreshTasks() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final tasks = await widget.api.getTasks(widget.project.id!);
      if (!mounted) return;
      setState(() {
        widget.project.tasks
          ..clear()
          ..addAll(tasks);
      });
      widget.onChanged();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _applyTask(ProjectTask updatedTask) {
    final index = widget.project.tasks.indexWhere((item) => item.id == updatedTask.id);
    if (index == -1) return;
    setState(() => widget.project.tasks[index] = updatedTask);
    widget.onChanged();
  }

  void _removeTask(int taskId) {
    setState(() => widget.project.tasks.removeWhere((item) => item.id == taskId));
    widget.onChanged();
  }

  void _openTeam() {
    Navigator.push(context, MaterialPageRoute<void>(
      builder: (context) => ProjectMembersPage(
        api: widget.api, project: widget.project,
      ),
    ));
  }

  Future<void> _openMilestones() async {
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (context) => MilestonesPage(
        api: widget.api, projectId: widget.project.id!,
      ),
    ));
    if (mounted) await _refreshTasks();
  }

  Future<void> _openIdeas() async {
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (context) => IdeasPage(
        api: widget.api, projectId: widget.project.id!,
        onTaskCreated: (task) {
          if (!mounted) return;
          setState(() => widget.project.tasks.add(task));
          widget.onChanged();
        },
      ),
    ));
    if (mounted) await _refreshTasks();
  }

  void _openTask(ProjectTask task, {bool startEditing = false}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => TaskDetailPage(
          task: task,
          api: widget.api,
          projectId: widget.project.id!,
          startEditing: startEditing,
          onAssignmentsUpdated: _applyTask,
          onDeleted: _removeTask,
          onChanged: (updatedTask) async {
            final savedTask = await widget.api.updateTask(
              widget.project.id!,
              updatedTask,
            );
            if (!mounted) return savedTask;
            _applyTask(savedTask);
            return savedTask;
          },
        ),
      ),
    );
  }
  Future<void> _addTask() async {
    var title = '';
    final colors = StickyColor.values;
    var selectedColor = colors[Random().nextInt(colors.length)];
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Nueva tarea'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Título'),
                onChanged: (value) => title = value,
              ),
              const SizedBox(height: 20),
              const Text('Color del pósit'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in colors)
                    ChoiceChip(
                      label: Text(colorLabel(color)),
                      backgroundColor: color.value,
                      selectedColor: color.value,
                      selected: selectedColor == color,
                      onSelected: (_) {
                        updateDialog(() => selectedColor = color);
                      },
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
              onPressed: () {
                if (title.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, title.trim());
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    try {
      final newTask = await widget.api.createTask(
        widget.project.id!,
        result,
        selectedColor,
      );
      if (!mounted) return;
      setState(() => widget.project.tasks.add(newTask));
      widget.onChanged();
      _openTask(newTask, startEditing: true);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
  @override
  Widget build(BuildContext context) {
    final tasks = [...widget.project.tasks]
      ..sort((a, b) => taskSortGroup(a).compareTo(taskSortGroup(b)));
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.white,
        bottom: _refreshing || _deleting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          if (compact)
            PopupMenuButton<String>(
              tooltip: 'Opciones del proyecto',
              enabled: !_deleting,
              onSelected: (value) {
                if (value == 'ideas') _openIdeas();
                if (value == 'milestones') _openMilestones();
                if (value == 'team') _openTeam();
                if (value == 'refresh') _refreshTasks();
                if (value == 'delete') _deleteProject();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'ideas', child: Text('Ideas')),
                const PopupMenuItem(value: 'milestones', child: Text('Hitos')),
                const PopupMenuItem(value: 'team', child: Text('Equipo e invitaciones')),
                if (_selectedTab == 0)
                  PopupMenuItem(value: 'refresh', enabled: !_refreshing,
                    child: const Text('Actualizar tareas')),
                if (widget.project.isOwner)
                  const PopupMenuItem(value: 'delete', child: Text('Eliminar proyecto')),
              ],
            ),
          if (!compact) ...[
          if (widget.project.isOwner)
            PopupMenuButton<String>(
              tooltip: 'Opciones del proyecto',
              enabled: !_deleting,
              onSelected: (value) {
                if (value == 'delete') _deleteProject();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'delete', child: Text('Eliminar proyecto')),
              ],
            ),
          IconButton(
            tooltip: 'Ideas del proyecto',
            onPressed: _openIdeas,
            icon: const Icon(Icons.lightbulb_outline),
          ),
          IconButton(
            tooltip: 'Hitos del proyecto',
            onPressed: _openMilestones,
            icon: const Icon(Icons.outlined_flag),
          ),
          if (_selectedTab == 0)
            IconButton(
              tooltip: 'Actualizar tareas',
              onPressed: _refreshing ? null : _refreshTasks,
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: 'Equipo e invitaciones',
            onPressed: _openTeam,
            icon: const Icon(Icons.group_outlined),
          ),
          ],
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = index);
          if (index == 0) _refreshTasks();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Tareas'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Resumen'),
        ],
      ),
      floatingActionButton: _selectedTab == 0 ? FloatingActionButton.extended(
        onPressed: _addTask,
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarea'),
      ) : null,
      body: _selectedTab == 1
          ? ProjectActivityPanel(api: widget.api, projectId: widget.project.id!)
          : _selectedTab == 2
          ? ProjectSummaryPanel(api: widget.api, projectId: widget.project.id!)
          : tasks.isEmpty
          ? const Center(child: Text('Todavía no hay tareas'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return Card(
                  color: task.color.value,
                  child: ListTile(
                    onTap: () => _openTask(task),
                    title: Row(
                      children: [
                        if (task.status == TaskStatus.completed) ...[
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: Text(task.title)),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(taskSummary(task), maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (task.milestoneName != null)
                          Text('Hito: ${task.milestoneName}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        if (task.dueDate != null)
                          Text(dueDateSummary(task)!,
                            style: TextStyle(
                              color: isTaskOverdue(task) ? Theme.of(context).colorScheme.error : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
class _TaskSnapshot {
  const _TaskSnapshot(this.title, this.texts, this.strokes);
  final String title;
  final List<BoardText> texts;
  final List<BoardStroke> strokes;
}
class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({
    super.key,
    required this.task,
    required this.api,
    required this.projectId,
    required this.onChanged,
    required this.onAssignmentsUpdated,
    required this.onDeleted,
    this.startEditing = false,
  });
  final ProjectTask task;
  final ApiClient api;
  final int projectId;
  final Future<ProjectTask> Function(ProjectTask) onChanged;
  final ValueChanged<ProjectTask> onAssignmentsUpdated;
  final ValueChanged<int> onDeleted;
  final bool startEditing;
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}
class _TaskDetailPageState extends State<TaskDetailPage> {
  late ProjectTask _task;
  late TextEditingController _titleController;
  late List<BoardText> _texts;
  late List<BoardStroke> _strokes;
  late _TaskSnapshot _lastState;
  final List<_TaskSnapshot> _undoHistory = [];
  final List<_TaskSnapshot> _redoHistory = [];
  Timer? _textTimer;
  bool _textBatchActive = false;
  _TaskSnapshot? _beforeCanvasAction;
  bool _saving = false;
  bool _deleted = false;
  Future<void> _chooseEditors() async {
    if (_saving || !_task.canManage) return;
    List<AssignmentCandidate> candidates;
    try {
      candidates = await widget.api.getAssignmentCandidates(widget.projectId);
    } catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    final available = candidates.where((person) =>
      !person.isMe && person.userId != _task.createdById).toList();
    final selected = _task.editorUserIds.toSet();
    final chosen = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Permisos de edición'),
          content: SizedBox(
            width: 420,
            height: min(400.0, max(110.0, available.length * 64.0)),
            child: available.isEmpty
              ? const Center(child: Text('Añade integrantes al equipo para dar permisos.'))
              : ListView(children: [
                  const Padding(padding: EdgeInsets.all(8),
                    child: Text('Estas personas podrán editar texto, dibujo, fecha y estado de la tarea.')),
                  for (final person in available)
                    CheckboxListTile(
                      title: Text(person.displayName),
                      value: selected.contains(person.userId),
                      onChanged: (checked) => updateDialog(() {
                        if (checked == true) {
                          selected.add(person.userId);
                        } else {
                          selected.remove(person.userId);
                        }
                      }),
                    ),
                ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final updated = await widget.api.setTaskEditors(
        widget.projectId, _task.id!, chosen.toList()..sort(),
      );
      if (!mounted) return;
      setState(() => _task = updated);
      widget.onAssignmentsUpdated(updated);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  Future<void> _deleteTask() async {
    if (_saving || !_task.canDelete) return;
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Eliminar «${_task.title}»? También se borrarán sus '
          'comentarios y archivos adjuntos. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.api.deleteTask(widget.projectId, _task.id!);
      if (!mounted) return;
      widget.onDeleted(_task.id!);
      setState(() => _deleted = true);
      _leaveAfterFrame();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  Future<void> _openAssignments() async {
    if (_saving) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => TaskAssignmentsPage(
        api: widget.api,
        projectId: widget.projectId,
        task: _task,
        onUpdated: (updated) {
          if (!mounted) return;
          setState(() => _task = updated);
          widget.onAssignmentsUpdated(updated);
        },
      ),
    ));
  }
  void _openComments() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => TaskCommentsPage(
        api: widget.api, projectId: widget.projectId, taskId: _task.id!,
      ),
    ));
  }
  _TaskSnapshot get _savedState => _TaskSnapshot(
        _task.title,
        BoardText.fromTask(_task),
        BoardStroke.fromCanvasData(_task.canvasData),
      );

  bool get _hasChanges => !_same(_snapshot(), _savedState);

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _titleController = TextEditingController(text: _task.title);
    _texts = BoardText.fromTask(_task);
    _strokes = BoardStroke.fromCanvasData(_task.canvasData);
    _lastState = _snapshot();
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  _TaskSnapshot _snapshot() => _TaskSnapshot(
        _titleController.text,
        List<BoardText>.from(_texts),
        List<BoardStroke>.from(_strokes),
      );

  bool _same(_TaskSnapshot a, _TaskSnapshot b) =>
      a.title.trim() == b.title.trim() &&
      jsonEncode(a.texts.map((text) => text.toJson()).toList()) ==
          jsonEncode(b.texts.map((text) => text.toJson()).toList()) &&
      jsonEncode(a.strokes.map((stroke) => stroke.toJson()).toList()) ==
          jsonEncode(b.strokes.map((stroke) => stroke.toJson()).toList());

  void _finishTextBatch() {
    _textTimer?.cancel();
    _textBatchActive = false;
  }
  void _textChanged() {
    if (!_textBatchActive) {
      _undoHistory.add(_lastState);
      _redoHistory.clear();
      _textBatchActive = true;
    }
    _lastState = _snapshot();
    _textTimer?.cancel();
    _textTimer = Timer(
      const Duration(milliseconds: 650),
      () => _textBatchActive = false,
    );
    setState(() {});
  }
  void _canvasActionStart() {
    _finishTextBatch();
    _beforeCanvasAction = _snapshot();
  }
  void _canvasActionEnd() {
    final before = _beforeCanvasAction;
    final now = _snapshot();
    if (before != null && !_same(before, now)) {
      _undoHistory.add(before);
      _redoHistory.clear();
    }
    _beforeCanvasAction = null;
    _lastState = now;
    setState(() {});
  }
  void _restore(_TaskSnapshot snapshot) {
    _finishTextBatch();
    setState(() {
      _titleController.text = snapshot.title;
      _texts = List<BoardText>.from(snapshot.texts);
      _strokes = List<BoardStroke>.from(snapshot.strokes);
      _lastState = _snapshot();
    });
  }
  void _undo() {
    if (_undoHistory.isEmpty) return;
    final current = _snapshot();
    final previous = _undoHistory.removeLast();
    _redoHistory.add(current);
    _restore(previous);
  }
  void _redo() {
    if (_redoHistory.isEmpty) return;
    final current = _snapshot();
    final next = _redoHistory.removeLast();
    _undoHistory.add(current);
    _restore(next);
  }
  Future<bool> _save() async {
    if (_saving) return false;
    if (!_task.canEdit) return false;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      showError(context, 'La tarea necesita un título');
      return false;
    }
    if (!_hasChanges) return true;
    _finishTextBatch();
    setState(() => _saving = true);
    try {
      final savedTask = await widget.onChanged(
        _task.copyWith(
          title: title,
          description: _texts
              .map((block) => block.text.trim())
              .where((text) => text.isNotEmpty)
              .join('\n\n'),
          canvasData: {
            'version': 2,
            'texts': _texts.map((block) => block.toJson()).toList(),
            'strokes': _strokes.map((stroke) => stroke.toJson()).toList(),
          },
        ),
      );
      if (!mounted) return false;
      setState(() {
        _task = savedTask;
        _titleController.text = savedTask.title;
        _texts = BoardText.fromTask(savedTask);
        _strokes = BoardStroke.fromCanvasData(savedTask.canvasData);
        _lastState = _snapshot();
      });
      return true;
    } catch (error) {
      if (mounted) showError(context, error);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  void _leaveAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }
  Future<void> _confirmLeaving() async {
    if (_saving) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text('¿Qué quieres hacer con los cambios de la tarea?'),
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
      final saved = await _save();
      if (saved && mounted) _leaveAfterFrame();
    } else if (choice == 'discard') {
      setState(() {
        _titleController.text = _task.title;
        _texts = BoardText.fromTask(_task);
        _strokes = BoardStroke.fromCanvasData(_task.canvasData);
        _undoHistory.clear();
        _redoHistory.clear();
        _finishTextBatch();
        _lastState = _snapshot();
      });
      _leaveAfterFrame();
    }
  }
  Future<void> _editSettings() async {
    if (!_task.canEdit) return;
    var newStatus = _task.status;
    var newColor = _task.color;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Estado y color'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estado'),
              Wrap(
                spacing: 8,
                children: [
                  for (final status in TaskStatus.values)
                    ChoiceChip(
                      label: Text(statusLabel(status)),
                      selected: newStatus == status,
                      onSelected: (_) {
                        updateDialog(() => newStatus = status);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Color del pósit'),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in StickyColor.values)
                    ChoiceChip(
                      label: Text(colorLabel(color)),
                      backgroundColor: color.value,
                      selectedColor: color.value,
                      selected: newColor == color,
                      onSelected: (_) {
                        updateDialog(() => newColor = color);
                      },
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _saving = true);
    try {
      final savedTask = await widget.onChanged(
        _task.copyWith(status: newStatus, color: newColor),
      );
      if (!mounted) return;
      setState(() => _task = savedTask);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  Future<void> _chooseDueDate() async {
    if (_saving || !_task.canEdit) return;
    final selected = await showDatePicker(
      context: context,
      initialDate: _task.dueDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Fecha objetivo de la tarea',
    );
    if (selected != null && mounted) await _setDueDate(selected);
  }

  Future<void> _setDueDate(DateTime? date) async {
    if (_saving || !_task.canEdit) return;
    setState(() => _saving = true);
    try {
      final savedTask = await widget.onChanged(
        _task.copyWith(dueDate: date, clearDueDate: date == null),
      );
      if (!mounted) return;
      setState(() => _task = savedTask);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  Future<void> _chooseMilestone() async {
    if (_saving || !_task.canEdit) return;
    List<Milestone> milestones;
    try {
      milestones = await widget.api.getMilestones(widget.projectId);
    } catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elegir hito'),
        content: SizedBox(
          width: 380,
          height: min(400.0, 58.0 * (milestones.length + 1)),
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Sin hito'),
                selected: _task.milestoneId == null,
                onTap: () => Navigator.pop(dialogContext, -1),
              ),
              for (final milestone in milestones)
                ListTile(
                  leading: Icon(milestone.isClosed ? Icons.flag : Icons.outlined_flag),
                  title: Text(milestone.name),
                  subtitle: milestone.isClosed ? const Text('Cerrado') : null,
                  selected: _task.milestoneId == milestone.id,
                  onTap: () => Navigator.pop(dialogContext, milestone.id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        ],
      ),
    );
    if (!mounted || chosen == null ||
        (chosen == -1 ? _task.milestoneId == null : chosen == _task.milestoneId)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final savedTask = await widget.onChanged(
        _task.copyWith(milestoneId: chosen == -1 ? null : chosen,
          clearMilestone: chosen == -1,
        ),
      );
      if (mounted) setState(() => _task = savedTask);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _deleted || (!_hasChanges && !_saving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving && _hasChanges) {
          _confirmLeaving();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tarea'),
          backgroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Comentarios',
              onPressed: _saving ? null : _openComments,
              icon: const Icon(Icons.comment_outlined),
            ),
            IconButton(
              tooltip: 'Reparto y avance',
              onPressed: _saving ? null : _openAssignments,
              icon: const Icon(Icons.assignment_ind_outlined),
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_task.canEdit)
              if (MediaQuery.sizeOf(context).width < 500)
                IconButton(
                  tooltip: 'Guardar cambios',
                  onPressed: _hasChanges ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                )
              else
                TextButton.icon(
                  onPressed: _hasChanges ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
            if (_task.canEdit || _task.canManage || _task.canDelete)
              PopupMenuButton<String>(
              tooltip: 'Opciones de la tarea',
              enabled: !_saving,
              onSelected: (option) {
                if (option == 'settings') _editSettings();
                if (option == 'editors') _chooseEditors();
                if (option == 'delete') _deleteTask();
              },
              itemBuilder: (context) => [
                if (_task.canEdit)
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Estado y color'),
                  ),
                if (_task.canManage)
                  const PopupMenuItem(
                    value: 'editors',
                    child: Text('Permisos de edición'),
                  ),
                if (_task.canDelete)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar tarea'),
                  ),
              ],
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                readOnly: _saving || !_task.canEdit,
                onChanged: !_saving && _task.canEdit ? (_) => _textChanged() : null,
                style: Theme.of(context).textTheme.headlineSmall,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Título de la tarea',
                  border: InputBorder.none,
                ),
              ),
              if (_task.canEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_saving ? 'Guardando…' : _hasChanges ? 'Cambios sin guardar' : 'Guardado',
                    style: Theme.of(context).textTheme.labelMedium),
                ),
              Text(taskSummary(_task),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (!_task.canEdit)
                const Text('Tarea en modo lectura. Puedes comentar, adjuntar archivos y actualizar tu avance.'),
              Row(
                children: [
                  Flexible(
                    child: TextButton.icon(
                      onPressed: _saving || !_task.canEdit ? null : _chooseDueDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(dueDateSummary(_task) ?? 'Añadir fecha objetivo',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      style: isTaskOverdue(_task)
                          ? TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error)
                          : null,
                    ),
                  ),
                  if (_task.dueDate != null)
                    IconButton(
                      tooltip: 'Quitar fecha',
                      onPressed: _saving || !_task.canEdit ? null : () => _setDueDate(null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving || !_task.canEdit ? null : _chooseMilestone,
                  icon: const Icon(Icons.outlined_flag, size: 18),
                  label: Text(_task.milestoneName == null
                      ? 'Asignar a un hito'
                      : 'Hito: ${_task.milestoneName}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: max(360.0, constraints.maxHeight - 300.0),
                child: TaskCanvas(
                  readOnly: _saving || !_task.canEdit,
                  texts: _texts,
                  strokes: _strokes,
                  onTextsChanged: (texts) {
                    setState(() => _texts = texts);
                  },
                  onTextEdited: _textChanged,
                  onStrokesChanged: (strokes) {
                    setState(() => _strokes = strokes);
                  },
                  onActionStart: _canvasActionStart,
                  onActionEnd: _canvasActionEnd,
                  canUndo: _undoHistory.isNotEmpty,
                  canRedo: _redoHistory.isNotEmpty,
                  onUndo: _undo,
                  onRedo: _redo,
                ),
              ),
              const SizedBox(height: 8),
              TaskAttachments(
                api: widget.api,
                projectId: widget.projectId,
                taskId: _task.id!,
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
