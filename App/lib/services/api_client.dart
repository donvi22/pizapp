import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../models/project.dart';

class ApiClient {
  static final baseUrl = _resolveBaseUrl();

  static String _resolveBaseUrl() {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured.replaceFirst(RegExp(r'/+$'), '');
    if (kIsWeb && Uri.base.scheme == 'https') return '${Uri.base.origin}/api';
    return 'http://127.0.0.1:8000/api';
  }

  String? _token;

  String? get token => _token;

  void restoreToken(String token) => _token = token;

  void clearToken() => _token = null;

  // Comprueba el token sin cargar todas las tareas de cada proyecto.
  Future<bool> validateSession() async {
    final response = await http
        .get(Uri.parse('$baseUrl/projects/'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 || response.statusCode == 403) return false;
    _decodeResponse(response);
    return true;
  }

  Future<void> login(String username, String password) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/login/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 400) {
      throw Exception('Usuario o contraseña incorrectos.');
    }

    if (response.statusCode != 200) {
      throw Exception('Error del servidor (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final receivedToken = data['token'];

    if (receivedToken is! String || receivedToken.isEmpty) {
      throw Exception('El servidor no ha devuelto un token válido.');
    }

    _token = receivedToken;
  }

  Future<void> register(String username, String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username, 'email': email, 'password': password,
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 201) {
      throw Exception('No se pudo crear la cuenta: ${utf8.decode(response.bodyBytes)}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    _token = json['token'] as String;
  }

  Map<String, String> get _headers {
    if (_token == null) {
      throw StateError('Inicia sesión antes de consultar la API.');
    }

    return {
      'Authorization': 'Token $_token',
      'Content-Type': 'application/json',
    };
  }

  Future<dynamic> _get(String path) async {
    final response = await http
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));

    return _decodeResponse(response);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> data) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 15));

    return _decodeResponse(response);
  }

  Future<dynamic> _put(String path, Map<String, dynamic> data) async {
    final response = await http
        .put(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 15));

    return _decodeResponse(response);
  }

  Future<void> _delete(String path) async {
    final response = await http.delete(
      Uri.parse('$baseUrl$path'), headers: _headers,
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 204) _decodeResponse(response);
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'La petición ha fallado (${response.statusCode}): ${response.body}',
      );
    }

    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<Project>> getProjects() async {
    final data = await _get('/projects/') as List<dynamic>;
    final projects = <Project>[];

    for (final item in data) {
      final json = item as Map<String, dynamic>;
      final id = json['id'] as int;
      final color = StickyColor.values.byName(json['color'] as String);

      projects.add(
        Project(
          id: id,
          name: json['name'] as String,
          color: color.value,
          tasks: await getTasks(id),
          ownerName: json['owner_name'] as String,
          isOwner: json['is_owner'] as bool,
          inviteCode: json['invite_code'] as String?,
        ),
      );
    }

    return projects;
  }

  Future<List<ProjectTask>> getTasks(int projectId) async {
    final data = await _get('/projects/$projectId/tasks/') as List<dynamic>;

    return data
        .map((item) => _taskFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Project> createProject(String name, StickyColor color) async {
    final json = await _post('/projects/', {
      'name': name,
      'color': color.name,
    }) as Map<String, dynamic>;

    return Project(
      id: json['id'] as int,
      name: json['name'] as String,
      color: StickyColor.values.byName(json['color'] as String).value,
      tasks: [],
      ownerName: json['owner_name'] as String,
      isOwner: json['is_owner'] as bool,
      inviteCode: json['invite_code'] as String?,
    );
  }

  Future<void> deleteProject(int projectId) => _delete('/projects/$projectId/');

  Future<ActivityPage> getProjectActivity(int projectId, {int offset = 0}) async {
    final data = await _get('/projects/$projectId/activity/?offset=$offset')
        as Map<String, dynamic>;
    return ActivityPage.fromJson(data);
  }

  Future<void> syncNotifications() async {
    await _post('/notifications/sync/', {});
  }

  Future<NotificationBatch> getNotifications({int offset = 0}) async {
    final data = await _get('/notifications/?offset=$offset') as Map<String, dynamic>;
    return NotificationBatch.fromJson(data);
  }

  Future<AppNotification> readNotification(int id) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/notifications/$id/'), headers: _headers,
      body: jsonEncode({}),
    ).timeout(const Duration(seconds: 15));
    return AppNotification.fromJson(_decodeResponse(response) as Map<String, dynamic>);
  }

  Future<void> readAllNotifications() async {
    await _post('/notifications/read-all/', {});
  }

  Future<List<Milestone>> getMilestones(int projectId) async {
    final data = await _get('/projects/$projectId/milestones/') as List<dynamic>;
    return data.map((item) => Milestone.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Milestone> createMilestone(int projectId, String name, DateTime? dueDate) async {
    final json = await _post('/projects/$projectId/milestones/', {
      'name': name,
      'due_date': dueDate?.toIso8601String().split('T').first,
    }) as Map<String, dynamic>;
    return Milestone.fromJson(json);
  }

  Future<Milestone> updateMilestone(int projectId, Milestone milestone, {
    required String name,
    required DateTime? dueDate,
    required bool isClosed,
  }) async {
    final json = await _put('/projects/$projectId/milestones/${milestone.id}/', {
      'name': name,
      'due_date': dueDate?.toIso8601String().split('T').first,
      'is_closed': isClosed,
    }) as Map<String, dynamic>;
    return Milestone.fromJson(json);
  }

  Future<void> deleteMilestone(int projectId, int milestoneId) =>
      _delete('/projects/$projectId/milestones/$milestoneId/');

  Future<List<ProjectIdea>> getIdeas(int projectId) async {
    final data = await _get('/projects/$projectId/ideas/') as List<dynamic>;
    return data.map((item) => ProjectIdea.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<ProjectIdea> createIdea(int projectId, String title, String description) async {
    final data = await _post('/projects/$projectId/ideas/', {
      'title': title, 'description': description,
    }) as Map<String, dynamic>;
    return ProjectIdea.fromJson(data);
  }

  Future<ProjectTask> convertIdea(int projectId, int ideaId) async {
    final data = await _post('/projects/$projectId/ideas/$ideaId/convert/', {})
        as Map<String, dynamic>;
    return _taskFromJson(data);
  }

  Future<void> deleteIdea(int projectId, int ideaId) =>
      _delete('/projects/$projectId/ideas/$ideaId/');

  String _commentsPath(int projectId, {int? taskId, int? ideaId}) {
    if ((taskId == null) == (ideaId == null)) {
      throw ArgumentError('Indica una tarea o una idea.');
    }
    if (taskId != null) return '/projects/$projectId/tasks/$taskId/comments/';
    return '/projects/$projectId/ideas/$ideaId/comments/';
  }

  Future<List<ProjectComment>> getComments(int projectId, {int? taskId, int? ideaId}) async {
    final data = await _get(_commentsPath(projectId, taskId: taskId, ideaId: ideaId))
        as List<dynamic>;
    return data.map((item) => ProjectComment.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<ProjectComment> addComment(int projectId, String text, {int? taskId, int? ideaId}) async {
    final data = await _post(_commentsPath(projectId, taskId: taskId, ideaId: ideaId),
        {'text': text}) as Map<String, dynamic>;
    return ProjectComment.fromJson(data);
  }

  Future<void> deleteComment(int projectId, int commentId, {int? taskId, int? ideaId}) =>
      _delete('${_commentsPath(projectId, taskId: taskId, ideaId: ideaId)}$commentId/');

  Future<List<ProjectSlot>> getProjectSlots(int projectId) async {
    final data = await _get('/projects/$projectId/slots/') as List<dynamic>;
    return data.map((entry) => ProjectSlot.fromJson(entry as Map<String, dynamic>)).toList();
  }

  Future<ProjectSlot> createProjectSlot(int projectId, String name) async {
    final data = await _post('/projects/$projectId/slots/', {
      'display_name': name,
    }) as Map<String, dynamic>;
    return ProjectSlot.fromJson(data);
  }

  Future<void> removeProjectSlot(int projectId, int slotId) =>
      _delete('/projects/$projectId/slots/$slotId/');

  Future<ProjectInvitation> getInvitation(String code) async {
    final data = await _get('/invitations/$code/') as Map<String, dynamic>;
    return ProjectInvitation.fromJson(data);
  }

  Future<void> joinProject(String code, int slotId) async {
    await _post('/invitations/$code/join/', {'slot_id': slotId});
  }

  Future<List<AssignmentCandidate>> getAssignmentCandidates(int projectId) async {
    final data = await _get('/projects/$projectId/assignment-candidates/') as List<dynamic>;
    return data.map((item) => AssignmentCandidate.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<ProjectTask> setTaskAssignments(
    int projectId, int taskId, List<int> userIds,
  ) async {
    final json = await _put('/projects/$projectId/tasks/$taskId/assignments/', {
      'user_ids': userIds,
    }) as Map<String, dynamic>;
    return _taskFromJson(json);
  }

  Future<ProjectTask> setTaskEditors(int projectId, int taskId, List<int> userIds) async {
    final json = await _put('/projects/$projectId/tasks/$taskId/editors/', {
      'user_ids': userIds,
    }) as Map<String, dynamic>;
    return _taskFromJson(json);
  }

  Future<ProjectTask> setMyAssignmentStatus(
    int projectId, int taskId, int userId, TaskStatus status,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/projects/$projectId/tasks/$taskId/assignments/$userId/'),
      headers: _headers,
      body: jsonEncode({'status': status.name}),
    ).timeout(const Duration(seconds: 15));
    return _taskFromJson(_decodeResponse(response) as Map<String, dynamic>);
  }

  Future<ProjectTask> createTask(
    int projectId,
    String title,
    StickyColor color,
  ) async {
    final json = await _post('/projects/$projectId/tasks/', {
      'title': title,
      'description': '',
      'status': TaskStatus.pending.name,
      'color': color.name,
    }) as Map<String, dynamic>;

    return _taskFromJson(json);
  }

  Future<ProjectTask> updateTask(
    int projectId,
    ProjectTask task,
  ) async {
    if (task.id == null) {
      throw StateError('Esta tarea todavía no existe en Django.');
    }

    final json = await _put('/projects/$projectId/tasks/${task.id}/', {
      'title': task.title,
      'description': task.description,
      'canvas_data': task.canvasData,
      'status': task.status.name,
      'color': task.color.name,
      'due_date': task.dueDate?.toIso8601String().split('T').first,
      'milestone': task.milestoneId,
    }) as Map<String, dynamic>;

    return _taskFromJson(json);
  }

  Future<void> deleteTask(int projectId, int taskId) =>
      _delete('/projects/$projectId/tasks/$taskId/');

  ProjectTask _taskFromJson(Map<String, dynamic> json) {
    return ProjectTask(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      canvasData: Map<String, dynamic>.from(
        (json['canvas_data'] as Map?) ?? const {},
      ),
      status: TaskStatus.values.byName(json['status'] as String),
      color: StickyColor.values.byName(json['color'] as String),
      assignments: (json['assignments'] as List<dynamic>? ?? const [])
          .map((item) => TaskAssignment.fromJson(item as Map<String, dynamic>))
          .toList(),
      dueDate: json['due_date'] == null
          ? null
          : DateTime.parse(json['due_date'] as String),
      milestoneId: json['milestone'] as int?,
      milestoneName: json['milestone_name'] as String?,
      canDelete: json['can_delete'] as bool,
      canEdit: json['can_edit'] as bool,
      canManage: json['can_manage'] as bool,
      editorUserIds: (json['editor_user_ids'] as List<dynamic>).cast<int>(),
      createdById: json['created_by_id'] as int,
    );
  }
}
