import 'package:flutter/material.dart';

enum StickyColor {
  yellow(Color(0xFFFFF1A8)),
  pink(Color(0xFFF8CADD)),
  blue(Color(0xFFCBE6FF)),
  green(Color(0xFFCFF0D2)),
  orange(Color(0xFFFFD9AD));

  const StickyColor(this.value);

  final Color value;
}

enum TaskStatus {
  pending,
  inProgress,
  completed,
}

class ProjectTask {
  const ProjectTask({
    this.id,
    required this.title,
    this.description = '',
    this.canvasData = const {},
    this.status = TaskStatus.pending,
    this.color = StickyColor.yellow,
    this.assignments = const [],
    this.dueDate,
    this.milestoneId,
    this.milestoneName,
    this.canDelete = false,
    this.canEdit = false,
    this.canManage = false,
    this.editorUserIds = const [],
    this.createdById,
  });

  final int? id;
  final String title;
  final String description;
  final Map<String, dynamic> canvasData;
  final TaskStatus status;
  final StickyColor color;
  final List<TaskAssignment> assignments;
  final DateTime? dueDate;
  final int? milestoneId;
  final String? milestoneName;
  final bool canDelete;
  final bool canEdit;
  final bool canManage;
  final List<int> editorUserIds;
  final int? createdById;

  ProjectTask copyWith({
    String? title,
    String? description,
    Map<String, dynamic>? canvasData,
    TaskStatus? status,
    StickyColor? color,
    List<TaskAssignment>? assignments,
    DateTime? dueDate,
    bool clearDueDate = false,
    int? milestoneId,
    String? milestoneName,
    bool clearMilestone = false,
  }) {
    return ProjectTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      canvasData: canvasData ?? this.canvasData,
      status: status ?? this.status,
      color: color ?? this.color,
      assignments: assignments ?? this.assignments,
      dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
      milestoneId: clearMilestone ? null : milestoneId ?? this.milestoneId,
      milestoneName: clearMilestone ? null : milestoneName ?? this.milestoneName,
      canDelete: canDelete,
      canEdit: canEdit,
      canManage: canManage,
      editorUserIds: editorUserIds,
      createdById: createdById,
    );
  }
}

class Project {
  const Project({
    this.id,
    required this.name,
    required this.color,
    required this.tasks,
    this.ownerName = '',
    this.isOwner = true,
    this.inviteCode,
  });

  final int? id;
  final String name;
  final Color color;
  final List<ProjectTask> tasks;
  final String ownerName;
  final bool isOwner;
  final String? inviteCode;

  int get totalCount => tasks.length;

  int get completedCount =>
      tasks.where((task) => task.status == TaskStatus.completed).length;
}

class Milestone {
  const Milestone({
    required this.id,
    required this.name,
    required this.dueDate,
    required this.isClosed,
    required this.canDelete,
    required this.canEdit,
  });

  final int id;
  final String name;
  final DateTime? dueDate;
  final bool isClosed;
  final bool canDelete;
  final bool canEdit;

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
    id: json['id'] as int,
    name: json['name'] as String,
    dueDate: json['due_date'] == null
        ? null : DateTime.parse(json['due_date'] as String),
    isClosed: json['is_closed'] as bool,
    canDelete: json['can_delete'] as bool,
    canEdit: json['can_edit'] as bool,
  );
}

class ProjectIdea {
  const ProjectIdea({
    required this.id, required this.title, required this.description,
    required this.convertedTaskId, required this.canDelete, required this.canConvert,
  });
  final int id;
  final String title;
  final String description;
  final int? convertedTaskId;
  final bool canDelete;
  final bool canConvert;

  factory ProjectIdea.fromJson(Map<String, dynamic> json) => ProjectIdea(
    id: json['id'] as int,
    title: json['title'] as String,
    description: json['description'] as String,
    convertedTaskId: json['converted_task'] as int?,
    canDelete: json['can_delete'] as bool,
    canConvert: json['can_convert'] as bool,
  );
}

class ProjectComment {
  const ProjectComment({required this.id, required this.text,
    required this.authorName, required this.canDelete, required this.createdAt});
  final int id;
  final String text;
  final String authorName;
  final bool canDelete;
  final DateTime createdAt;

  factory ProjectComment.fromJson(Map<String, dynamic> json) => ProjectComment(
    id: json['id'] as int,
    text: json['text'] as String,
    authorName: json['author_name'] as String,
    canDelete: json['can_delete'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

class ProjectActivity {
  const ProjectActivity({required this.id, required this.actorName,
    required this.action, required this.description, required this.createdAt});
  final int id;
  final String actorName;
  final String action;
  final String description;
  final DateTime createdAt;

  factory ProjectActivity.fromJson(Map<String, dynamic> json) => ProjectActivity(
    id: json['id'] as int,
    actorName: json['actor_name'] as String,
    action: json['action'] as String,
    description: json['description'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

class ActivityPage {
  const ActivityPage({required this.results, required this.count, required this.nextOffset});
  final List<ProjectActivity> results;
  final int count;
  final int? nextOffset;

  factory ActivityPage.fromJson(Map<String, dynamic> json) => ActivityPage(
    results: (json['results'] as List<dynamic>)
      .map((item) => ProjectActivity.fromJson(item as Map<String, dynamic>)).toList(),
    count: json['count'] as int,
    nextOffset: json['next_offset'] as int?,
  );
}

class AppNotification {
  const AppNotification({required this.id, required this.projectId,
    required this.projectName, required this.kind, required this.message,
    required this.taskId, required this.ideaId, required this.createdAt,
    required this.isRead});
  final int id;
  final int projectId;
  final String projectName;
  final String kind;
  final String message;
  final int? taskId;
  final int? ideaId;
  final DateTime createdAt;
  final bool isRead;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as int,
    projectId: json['project'] as int,
    projectName: json['project_name'] as String,
    kind: json['kind'] as String,
    message: json['message'] as String,
    taskId: json['task'] as int?,
    ideaId: json['idea'] as int?,
    createdAt: DateTime.parse(json['created_at'] as String),
    isRead: json['is_read'] as bool,
  );

  AppNotification markRead() => AppNotification(
    id: id, projectId: projectId, projectName: projectName, kind: kind,
    message: message, taskId: taskId, ideaId: ideaId,
    createdAt: createdAt, isRead: true,
  );
}

class NotificationBatch {
  const NotificationBatch({required this.results, required this.unreadCount,
    required this.nextOffset});
  final List<AppNotification> results;
  final int unreadCount;
  final int? nextOffset;

  factory NotificationBatch.fromJson(Map<String, dynamic> json) => NotificationBatch(
    results: (json['results'] as List<dynamic>)
      .map((entry) => AppNotification.fromJson(entry as Map<String, dynamic>)).toList(),
    unreadCount: json['unread_count'] as int,
    nextOffset: json['next_offset'] as int?,
  );
}

class TaskAssignment {
  const TaskAssignment({
    required this.userId,
    required this.displayName,
    required this.status,
  });

  final int userId;
  final String displayName;
  final TaskStatus status;

  factory TaskAssignment.fromJson(Map<String, dynamic> json) => TaskAssignment(
    userId: json['user_id'] as int,
    displayName: json['display_name'] as String,
    status: TaskStatus.values.byName(json['status'] as String),
  );
}

class AssignmentCandidate {
  const AssignmentCandidate({
    required this.userId,
    required this.displayName,
    required this.isMe,
  });

  final int userId;
  final String displayName;
  final bool isMe;

  factory AssignmentCandidate.fromJson(Map<String, dynamic> json) => AssignmentCandidate(
    userId: json['user_id'] as int,
    displayName: json['display_name'] as String,
    isMe: json['is_me'] as bool,
  );
}

class ProjectSlot {
  const ProjectSlot({required this.id, required this.displayName, this.username});

  final int id;
  final String displayName;
  final String? username;

  factory ProjectSlot.fromJson(Map<String, dynamic> json) => ProjectSlot(
    id: json['id'] as int,
    displayName: json['display_name'] as String,
    username: json['username'] as String?,
  );
}

class ProjectInvitation {
  const ProjectInvitation({
    required this.projectName,
    required this.ownerName,
    required this.slots,
  });

  final String projectName;
  final String ownerName;
  final List<ProjectSlot> slots;

  factory ProjectInvitation.fromJson(Map<String, dynamic> json) => ProjectInvitation(
    projectName: json['project_name'] as String,
    ownerName: json['owner_name'] as String,
    slots: (json['slots'] as List<dynamic>)
        .map((slot) => ProjectSlot.fromJson(slot as Map<String, dynamic>))
        .toList(),
  );
}
