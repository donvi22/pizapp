from django.conf import settings
from rest_framework import serializers

from .models import Attachment, Idea, IdeaComment, Milestone, Notification, Project, ProjectActivity, ProjectMember, Task, TaskAssignment, TaskComment


class ProjectActivitySerializer(serializers.ModelSerializer):
    class Meta:
        model = ProjectActivity
        fields = ["id", "actor_name", "action", "description", "created_at"]
        read_only_fields = fields


class NotificationSerializer(serializers.ModelSerializer):
    project_name = serializers.CharField(source="project.name", read_only=True)
    is_read = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = ["id", "project", "project_name", "kind", "message",
                  "task", "idea", "created_at", "is_read"]
        read_only_fields = fields

    def get_is_read(self, obj):
        return obj.read_at is not None


class ProjectSerializer(serializers.ModelSerializer):
    owner_name = serializers.CharField(source="created_by.username", read_only=True)
    is_owner = serializers.SerializerMethodField()
    invite_code = serializers.SerializerMethodField()

    class Meta:
        model = Project
        fields = [
            "id", "name", "color", "created_at", "owner_name",
            "is_owner", "invite_code",
        ]
        read_only_fields = ["id", "created_at", "owner_name", "is_owner", "invite_code"]

    def get_is_owner(self, obj):
        return obj.created_by_id == self.context["request"].user.id

    def get_invite_code(self, obj):
        if self.get_is_owner(obj):
            return obj.invite_code
        return None


class ProjectMemberSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)

    class Meta:
        model = ProjectMember
        fields = ["id", "display_name", "username", "joined_at"]
        read_only_fields = fields


class ProjectSlotSerializer(serializers.Serializer):
    display_name = serializers.CharField(max_length=80, trim_whitespace=True)

    def validate_display_name(self, value):
        project = self.context["project"]
        if ProjectMember.objects.filter(
            project=project, display_name__iexact=value,
        ).exists():
            raise serializers.ValidationError("Este nombre ya tiene una plaza.")
        return value


class TaskAssignmentSerializer(serializers.ModelSerializer):
    user_id = serializers.IntegerField(read_only=True)
    display_name = serializers.SerializerMethodField()

    class Meta:
        model = TaskAssignment
        fields = ["user_id", "display_name", "status"]

    def get_display_name(self, obj):
        if obj.task.project.created_by_id == obj.user_id:
            return obj.user.username
        return ProjectMember.objects.filter(
            project=obj.task.project, user_id=obj.user_id,
        ).values_list("display_name", flat=True).first() or obj.user.username


class MilestoneSerializer(serializers.ModelSerializer):
    can_delete = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()

    class Meta:
        model = Milestone
        fields = [
            "id", "name", "due_date", "is_closed", "can_delete", "can_edit",
            "created_at", "updated_at",
        ]
        read_only_fields = ["id", "can_delete", "can_edit", "created_at", "updated_at"]

    def get_can_delete(self, obj):
        user_id = self.context["request"].user.id
        return obj.created_by_id == user_id or obj.project.created_by_id == user_id

    def get_can_edit(self, obj):
        return self.get_can_delete(obj)

    def validate_name(self, value):
        existing = Milestone.objects.filter(
            project_id=self.context["view"].kwargs["project_id"],
            name__iexact=value,
        )
        if self.instance is not None:
            existing = existing.exclude(pk=self.instance.pk)
        if existing.exists():
            raise serializers.ValidationError("Ya hay un hito con ese nombre.")
        return value


class TaskSerializer(serializers.ModelSerializer):
    assignments = TaskAssignmentSerializer(many=True, read_only=True)
    milestone_name = serializers.CharField(source="milestone.name", read_only=True)
    created_by_id = serializers.IntegerField(read_only=True)
    can_delete = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    can_manage = serializers.SerializerMethodField()
    editor_user_ids = serializers.SerializerMethodField()

    def get_can_delete(self, obj):
        user_id = self.context["request"].user.id
        return user_id in (obj.created_by_id, obj.project.created_by_id)

    def get_can_edit(self, obj):
        user_id = self.context["request"].user.id
        return self.get_can_delete(obj) or any(editor.user_id == user_id for editor in obj.editors.all())

    def get_can_manage(self, obj):
        return obj.project.created_by_id == self.context["request"].user.id

    def get_editor_user_ids(self, obj):
        return [editor.user_id for editor in obj.editors.all()]

    class Meta:
        model = Task
        fields = [
            "id", "title", "description", "canvas_data", "status", "color", "due_date",
            "milestone", "milestone_name", "assignments", "can_delete", "can_edit",
            "can_manage", "editor_user_ids", "created_by_id", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "can_delete", "can_edit", "can_manage",
                            "editor_user_ids", "created_by_id", "created_at", "updated_at"]

    def validate_milestone(self, milestone):
        if milestone is not None and milestone.project_id != self.context["view"].kwargs["project_id"]:
            raise serializers.ValidationError("El hito no pertenece a este proyecto.")
        return milestone


class IdeaSerializer(serializers.ModelSerializer):
    can_delete = serializers.SerializerMethodField()
    can_convert = serializers.SerializerMethodField()

    def get_can_delete(self, obj):
        user_id = self.context["request"].user.id
        return user_id in (obj.created_by_id, obj.project.created_by_id)

    def get_can_convert(self, obj):
        return obj.project.created_by_id == self.context["request"].user.id

    class Meta:
        model = Idea
        fields = ["id", "title", "description", "converted_task", "can_delete", "can_convert", "created_at"]
        read_only_fields = ["id", "converted_task", "can_delete", "can_convert", "created_at"]


class CommentSerializer(serializers.ModelSerializer):
    author_name = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()

    def get_author_name(self, obj):
        project = obj.task.project if isinstance(obj, TaskComment) else obj.idea.project
        if obj.author_id == project.created_by_id:
            return obj.author.username
        return ProjectMember.objects.filter(project=project, user_id=obj.author_id).values_list(
            "display_name", flat=True,
        ).first() or obj.author.username

    def get_can_delete(self, obj):
        return obj.author_id == self.context["request"].user.id

    def validate_text(self, value):
        if not value.strip():
            raise serializers.ValidationError("Escribe un comentario.")
        return value.strip()

    class Meta:
        model = TaskComment
        fields = ["id", "text", "author_name", "can_delete", "created_at"]
        read_only_fields = ["id", "author_name", "can_delete", "created_at"]


class IdeaCommentSerializer(CommentSerializer):
    class Meta(CommentSerializer.Meta):
        model = IdeaComment


class AttachmentSerializer(serializers.ModelSerializer):
    file = serializers.FileField(write_only=True)

    class Meta:
        model = Attachment
        fields = ["id", "file", "original_name", "size_bytes", "uploaded_at"]
        read_only_fields = ["id", "original_name", "size_bytes", "uploaded_at"]

    def validate_file(self, file):
        limit = getattr(settings, "PIZAPP_MAX_UPLOAD_BYTES", 100 * 1024 * 1024)
        if file.size > limit:
            raise serializers.ValidationError(
                f"El archivo supera el límite de {limit // (1024 * 1024)} MB."
            )
        return file
