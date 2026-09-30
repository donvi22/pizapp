from django.conf import settings
from django.db import models
from uuid import uuid4


def new_invite_code():
    return uuid4().hex


class StickyColor(models.TextChoices):
    YELLOW = "yellow", "Amarillo"
    PINK = "pink", "Rosa"
    BLUE = "blue", "Azul"
    GREEN = "green", "Verde"
    ORANGE = "orange", "Naranja"


class TaskStatus(models.TextChoices):
    PENDING = "pending", "Pendiente"
    IN_PROGRESS = "inProgress", "En curso"
    COMPLETED = "completed", "Completada"


class Project(models.Model):
    name = models.CharField(max_length=160)
    color = models.CharField(
        max_length=10,
        choices=StickyColor.choices,
        default=StickyColor.YELLOW,
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="created_projects",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    invite_code = models.CharField(
        max_length=32, unique=True, default=new_invite_code, editable=False,
    )

    def __str__(self):
        return self.name


class ProjectActivity(models.Model):
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name="activity")
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
                              null=True, related_name="project_activity")
    actor_name = models.CharField(max_length=150)
    action = models.CharField(max_length=40)
    description = models.CharField(max_length=300)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]


class Notification(models.Model):
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name="notifications")
    recipient = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                                  related_name="pizapp_notifications")
    kind = models.CharField(max_length=30)
    message = models.CharField(max_length=300)
    task = models.ForeignKey("Task", on_delete=models.SET_NULL, null=True, blank=True)
    idea = models.ForeignKey("Idea", on_delete=models.SET_NULL, null=True, blank=True)
    dedupe_key = models.CharField(max_length=100, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        constraints = [models.UniqueConstraint(fields=["recipient", "dedupe_key"],
                                               name="unique_notification_dedupe")]


class ProjectMember(models.Model):
    project = models.ForeignKey(
        Project, on_delete=models.CASCADE, related_name="members",
    )
    display_name = models.CharField(max_length=80)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="project_memberships", null=True, blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    joined_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["project", "user"], name="unique_project_member_user",
            ),
        ]

    def __str__(self):
        return f"{self.display_name} · {self.project.name}"


class Milestone(models.Model):
    project = models.ForeignKey(
        Project, on_delete=models.CASCADE, related_name="milestones",
    )
    name = models.CharField(max_length=160)
    due_date = models.DateField(null=True, blank=True)
    is_closed = models.BooleanField(default=False)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="created_milestones",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name


class Task(models.Model):
    project = models.ForeignKey(
        Project,
        on_delete=models.CASCADE,
        related_name="tasks",
    )
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    canvas_data = models.JSONField(default=dict, blank=True)
    due_date = models.DateField(null=True, blank=True)
    milestone = models.ForeignKey(
        Milestone, on_delete=models.SET_NULL, related_name="tasks",
        null=True, blank=True,
    )
    status = models.CharField(
        max_length=12,
        choices=TaskStatus.choices,
        default=TaskStatus.PENDING,
    )
    color = models.CharField(
        max_length=10,
        choices=StickyColor.choices,
        default=StickyColor.YELLOW,
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="created_tasks",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.title


class Idea(models.Model):
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name="ideas")
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
                                   related_name="created_ideas")
    converted_task = models.OneToOneField(Task, on_delete=models.SET_NULL, null=True,
                                          blank=True, related_name="source_idea")
    created_at = models.DateTimeField(auto_now_add=True)


class TaskComment(models.Model):
    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name="comments")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    text = models.TextField(max_length=2000)
    created_at = models.DateTimeField(auto_now_add=True)


class IdeaComment(models.Model):
    idea = models.ForeignKey(Idea, on_delete=models.CASCADE, related_name="comments")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    text = models.TextField(max_length=2000)
    created_at = models.DateTimeField(auto_now_add=True)


class TaskAssignment(models.Model):
    task = models.ForeignKey(
        Task, on_delete=models.CASCADE, related_name="assignments",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="task_assignments",
    )
    status = models.CharField(
        max_length=12, choices=TaskStatus.choices, default=TaskStatus.PENDING,
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["task", "user"], name="unique_task_assignment_user",
            ),
        ]

    def __str__(self):
        return f"{self.task.title}: {self.user.username}"


class TaskEditor(models.Model):
    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name="editors")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                             related_name="editable_tasks")

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["task", "user"], name="unique_task_editor_user"),
        ]


class Attachment(models.Model):
    task = models.ForeignKey(
        Task,
        on_delete=models.CASCADE,
        related_name="attachments",
    )
    file = models.FileField(upload_to="task_attachments/%Y/%m/%d/")
    original_name = models.CharField(max_length=255)
    size_bytes = models.PositiveBigIntegerField()
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="uploaded_attachments",
    )
    uploaded_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.original_name
