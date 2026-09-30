import logging

from django.conf import settings
from django.db import IntegrityError, transaction
from datetime import timedelta

from django.db.models import Q, Sum
from django.http import FileResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Attachment, Idea, IdeaComment, Milestone, Notification, Project, ProjectActivity, ProjectMember, Task, TaskAssignment, TaskComment, TaskEditor, TaskStatus
from .serializers import (
    AttachmentSerializer,
    ProjectSerializer,
    ProjectMemberSerializer,
    ProjectSlotSerializer,
    MilestoneSerializer,
    IdeaSerializer,
    CommentSerializer,
    IdeaCommentSerializer,
    ProjectActivitySerializer,
    NotificationSerializer,
    TaskSerializer,
)


def accessible_projects(user):
    return Project.objects.filter(
        Q(created_by=user) | Q(members__user=user)
    ).distinct()


def project_actor_name(project, user):
    return (
        user.username if project.created_by_id == user.id else
        ProjectMember.objects.filter(project=project, user=user).values_list(
            "display_name", flat=True,
        ).first() or user.username
    )


def record_activity(project, user, action, description):
    ProjectActivity.objects.create(
        project=project, actor=user, actor_name=project_actor_name(project, user),
        action=action, description=description[:300],
    )


def send_notifications(project, actor, recipients, kind, message, *, task=None, idea=None):
    allowed = candidate_users(project)
    Notification.objects.bulk_create([
        Notification(project=project, recipient_id=user_id, kind=kind,
                     message=message[:300], task=task, idea=idea)
        for user_id in set(recipients) & allowed if user_id != actor.id
    ])


def create_due_notifications(user):
    today = timezone.localdate()
    tasks = Task.objects.filter(
        project__in=accessible_projects(user),
        due_date__range=(today - timedelta(days=7), today + timedelta(days=1)),
    ).exclude(status=TaskStatus.COMPLETED).filter(
        Q(assignments__user=user) | Q(assignments__isnull=True, created_by=user),
    ).distinct().prefetch_related("assignments")
    for task in tasks:
        own_assignment = next((item for item in task.assignments.all() if item.user_id == user.id), None)
        if own_assignment is not None and own_assignment.status == TaskStatus.COMPLETED:
            continue
        when = "vence mañana" if task.due_date == today + timedelta(days=1) else (
            "vence hoy" if task.due_date == today else "está vencida"
        )
        Notification.objects.get_or_create(
            recipient=user,
            dedupe_key=f"due:{task.id}:{task.due_date.isoformat()}",
            defaults={"project": task.project, "task": task, "kind": "due_date",
                      "message": f"La tarea «{task.title}» {when}."[:300]},
        )


class NotificationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            offset = int(request.query_params.get("offset", "0"))
        except (TypeError, ValueError):
            raise ValidationError({"offset": "Indica un desplazamiento válido."})
        if offset < 0:
            raise ValidationError({"offset": "Indica un desplazamiento válido."})
        items = Notification.objects.filter(
            recipient=request.user, project__in=accessible_projects(request.user),
        ).select_related("project")
        count = items.count()
        return Response({
            "count": count,
            "unread_count": items.filter(read_at__isnull=True).count(),
            "next_offset": offset + 50 if offset + 50 < count else None,
            "results": NotificationSerializer(items[offset:offset + 50], many=True).data,
        })


class NotificationSyncView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        create_due_notifications(request.user)
        return Response({"ok": True})


class NotificationDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        item = get_object_or_404(
            Notification.objects.select_related("project"), pk=pk,
            recipient=request.user, project__in=accessible_projects(request.user),
        )
        if item.read_at is None:
            item.read_at = timezone.now()
            item.save(update_fields=["read_at"])
        return Response(NotificationSerializer(item).data)


class NotificationReadAllView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        Notification.objects.filter(
            recipient=request.user, project__in=accessible_projects(request.user),
            read_at__isnull=True,
        ).update(read_at=timezone.now())
        return Response({"ok": True})


class ProjectActivityView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, project_id):
        project = get_object_or_404(accessible_projects(request.user), pk=project_id)
        try:
            offset = int(request.query_params.get("offset", "0"))
        except (TypeError, ValueError):
            raise ValidationError({"offset": "Indica un desplazamiento válido."})
        if offset < 0:
            raise ValidationError({"offset": "Indica un desplazamiento válido."})
        items = ProjectActivity.objects.filter(project=project)
        count = items.count()
        page = items[offset:offset + 50]
        next_offset = offset + 50 if offset + 50 < count else None
        return Response({
            "count": count, "next_offset": next_offset,
            "results": ProjectActivitySerializer(page, many=True).data,
        })


def delete_with_attachments(instance, attachments):
    """Delete database rows atomically, then remove stored files after commit."""
    with transaction.atomic():
        files = [(item.file.storage, item.file.name) for item in attachments]
        instance.delete()

        def remove_files():
            for storage, name in files:
                try:
                    storage.delete(name)
                except Exception:
                    logging.getLogger(__name__).exception("Could not delete attachment %s", name)

        transaction.on_commit(remove_files)


class ProjectListCreateView(generics.ListCreateAPIView):
    serializer_class = ProjectSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return accessible_projects(self.request.user).order_by("-created_at")

    def perform_create(self, serializer):
        with transaction.atomic():
            project = serializer.save(created_by=self.request.user)
            record_activity(project, self.request.user, "project_created", "Creó el proyecto.")


class ProjectDetailView(generics.RetrieveDestroyAPIView):
    serializer_class = ProjectSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return accessible_projects(self.request.user)

    def perform_destroy(self, instance):
        if instance.created_by_id != self.request.user.id:
            raise PermissionDenied("Solo el creador puede eliminar el proyecto.")
        delete_with_attachments(instance, Attachment.objects.filter(task__project=instance))


class MilestoneListCreateView(generics.ListCreateAPIView):
    serializer_class = MilestoneSerializer
    permission_classes = [IsAuthenticated]

    def get_project(self):
        return get_object_or_404(
            accessible_projects(self.request.user), pk=self.kwargs["project_id"],
        )

    def get_queryset(self):
        return Milestone.objects.filter(
            project=self.get_project(),
        ).select_related("project").order_by("is_closed", "due_date", "id")

    def perform_create(self, serializer):
        with transaction.atomic():
            milestone = serializer.save(project=self.get_project(), created_by=self.request.user)
            record_activity(milestone.project, self.request.user, "milestone_created",
                            f"Creó el hito «{milestone.name}».")


class MilestoneDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = MilestoneSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Milestone.objects.filter(
            project_id=self.kwargs["project_id"],
            project__in=accessible_projects(self.request.user),
        ).select_related("project")

    def perform_update(self, serializer):
        old = serializer.instance
        if self.request.user.id not in (old.created_by_id, old.project.created_by_id):
            raise PermissionDenied("Solo quien creó el hito o el creador del proyecto puede editarlo.")
        before = (old.name, old.due_date, old.is_closed)
        with transaction.atomic():
            milestone = serializer.save()
            if before != (milestone.name, milestone.due_date, milestone.is_closed):
                action = "milestone_closed" if not before[2] and milestone.is_closed else (
                    "milestone_reopened" if before[2] and not milestone.is_closed else "milestone_updated"
                )
                verb = "Cerró" if action == "milestone_closed" else (
                    "Reabrió" if action == "milestone_reopened" else "Actualizó"
                )
                record_activity(milestone.project, self.request.user, action,
                                f"{verb} el hito «{milestone.name}».")

    def perform_destroy(self, instance):
        if self.request.user.id not in (instance.created_by_id, instance.project.created_by_id):
            raise PermissionDenied("Solo quien creó el hito o el creador del proyecto puede retirarlo.")
        with transaction.atomic():
            project, name = instance.project, instance.name
            instance.delete()
            record_activity(project, self.request.user, "milestone_deleted", f"Eliminó el hito «{name}».")


class TaskListCreateView(generics.ListCreateAPIView):
    serializer_class = TaskSerializer
    permission_classes = [IsAuthenticated]

    def get_project(self):
        return get_object_or_404(
            accessible_projects(self.request.user),
            pk=self.kwargs["project_id"],
        )

    def get_queryset(self):
        return Task.objects.filter(
            project=self.get_project()
        ).select_related("milestone").prefetch_related("assignments__user", "editors").order_by("created_at")

    def perform_create(self, serializer):
        with transaction.atomic():
            task = serializer.save(
                project=self.get_project(), created_by=self.request.user,
            )
            record_activity(task.project, self.request.user, "task_created", f"Creó la tarea «{task.title}».")


class TaskDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = TaskSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Task.objects.filter(
            project_id=self.kwargs["project_id"],
            project__in=accessible_projects(self.request.user),
        ).select_related("milestone").prefetch_related("assignments__user", "editors")

    def perform_update(self, serializer):
        task = serializer.instance
        if self.request.user.id not in (task.created_by_id, task.project.created_by_id) and not task.editors.filter(
            user_id=self.request.user.id,
        ).exists():
            raise PermissionDenied("No tienes permiso para editar esta tarea.")
        fields = ("title", "description", "canvas_data", "status", "color", "due_date", "milestone_id")
        before = tuple(getattr(task, field) for field in fields)
        with transaction.atomic():
            task = serializer.save()
            if before != tuple(getattr(task, field) for field in fields):
                record_activity(task.project, self.request.user, "task_updated",
                                f"Actualizó la tarea «{task.title}».")

    def perform_destroy(self, instance):
        if self.request.user.id not in (instance.created_by_id, instance.project.created_by_id):
            raise PermissionDenied("Solo quien creó la tarea o el creador del proyecto puede eliminarla.")
        with transaction.atomic():
            project, title = instance.project, instance.title
            delete_with_attachments(instance, instance.attachments.all())
            record_activity(project, self.request.user, "task_deleted", f"Eliminó la tarea «{title}».")


def accessible_task(user, project_id, task_id):
    return get_object_or_404(
        Task, pk=task_id, project_id=project_id,
        project__in=accessible_projects(user),
    )


def accessible_idea(user, project_id, idea_id):
    return get_object_or_404(
        Idea, pk=idea_id, project_id=project_id,
        project__in=accessible_projects(user),
    )


class IdeaListCreateView(generics.ListCreateAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = IdeaSerializer

    def get_project(self):
        return get_object_or_404(accessible_projects(self.request.user), pk=self.kwargs["project_id"])

    def get_queryset(self):
        return Idea.objects.filter(project=self.get_project()).order_by("-created_at", "-id")

    def perform_create(self, serializer):
        with transaction.atomic():
            idea = serializer.save(project=self.get_project(), created_by=self.request.user)
            record_activity(idea.project, self.request.user, "idea_created", f"Propuso la idea «{idea.title}».")


class IdeaDetailView(generics.RetrieveDestroyAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = IdeaSerializer

    def get_queryset(self):
        return Idea.objects.filter(project_id=self.kwargs["project_id"],
                                   project__in=accessible_projects(self.request.user))

    def perform_destroy(self, instance):
        if self.request.user.id not in (instance.created_by_id, instance.project.created_by_id):
            raise PermissionDenied("Solo quien creó la idea o el creador del proyecto puede eliminarla.")
        with transaction.atomic():
            project, title = instance.project, instance.title
            instance.delete()
            record_activity(project, self.request.user, "idea_deleted", f"Eliminó la idea «{title}».")


class IdeaConvertView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, project_id, idea_id):
        with transaction.atomic():
            idea = get_object_or_404(
                Idea.objects.select_for_update(), pk=idea_id, project_id=project_id,
                project__in=accessible_projects(request.user),
            )
            if idea.project.created_by_id != request.user.id:
                raise PermissionDenied("Solo el creador del proyecto puede aprobar esta idea.")
            if idea.converted_task_id is not None:
                raise ValidationError({"idea": "Esta idea ya se convirtió en tarea."})
            task = Task.objects.create(project=idea.project, title=idea.title,
                                       description=idea.description, created_by=request.user)
            idea.converted_task = task
            idea.save(update_fields=["converted_task"])
            record_activity(idea.project, request.user, "idea_converted",
                            f"Convirtió la idea «{idea.title}» en tarea.")
        return Response(TaskSerializer(task, context={"request": request}).data,
                        status=status.HTTP_201_CREATED)


class TaskCommentListCreateView(generics.ListCreateAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = CommentSerializer

    def get_queryset(self):
        task = accessible_task(self.request.user, self.kwargs["project_id"], self.kwargs["task_id"])
        return TaskComment.objects.filter(task=task).select_related("author", "task__project").order_by("created_at", "id")

    def perform_create(self, serializer):
        task = accessible_task(self.request.user, self.kwargs["project_id"], self.kwargs["task_id"])
        with transaction.atomic():
            serializer.save(task=task, author=self.request.user)
            record_activity(task.project, self.request.user, "task_comment",
                            f"Comentó la tarea «{task.title}».")
            recipients = {task.created_by_id}
            recipients.update(task.assignments.values_list("user_id", flat=True))
            recipients.update(task.comments.values_list("author_id", flat=True))
            send_notifications(task.project, self.request.user, recipients, "task_comment",
                               f"{project_actor_name(task.project, self.request.user)} comentó «{task.title}».", task=task)


class IdeaCommentListCreateView(generics.ListCreateAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = IdeaCommentSerializer

    def get_queryset(self):
        idea = accessible_idea(self.request.user, self.kwargs["project_id"], self.kwargs["idea_id"])
        return IdeaComment.objects.filter(idea=idea).select_related("author", "idea__project").order_by("created_at", "id")

    def perform_create(self, serializer):
        idea = accessible_idea(self.request.user, self.kwargs["project_id"], self.kwargs["idea_id"])
        with transaction.atomic():
            serializer.save(idea=idea, author=self.request.user)
            record_activity(idea.project, self.request.user, "idea_comment",
                            f"Comentó la idea «{idea.title}».")
            recipients = {idea.created_by_id}
            recipients.update(idea.comments.values_list("author_id", flat=True))
            send_notifications(idea.project, self.request.user, recipients, "idea_comment",
                               f"{project_actor_name(idea.project, self.request.user)} comentó la idea «{idea.title}».", idea=idea)


class TaskCommentDetailView(generics.DestroyAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = CommentSerializer

    def get_queryset(self):
        return TaskComment.objects.filter(
            task_id=self.kwargs["task_id"], task__project_id=self.kwargs["project_id"],
            task__project__in=accessible_projects(self.request.user),
        )

    def perform_destroy(self, instance):
        if instance.author_id != self.request.user.id:
            raise PermissionDenied("Solo puedes borrar tus comentarios.")
        with transaction.atomic():
            project, title = instance.task.project, instance.task.title
            instance.delete()
            record_activity(project, self.request.user, "task_comment_deleted",
                            f"Eliminó un comentario de «{title}».")


class IdeaCommentDetailView(generics.DestroyAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = IdeaCommentSerializer

    def get_queryset(self):
        return IdeaComment.objects.filter(
            idea_id=self.kwargs["idea_id"], idea__project_id=self.kwargs["project_id"],
            idea__project__in=accessible_projects(self.request.user),
        )

    def perform_destroy(self, instance):
        if instance.author_id != self.request.user.id:
            raise PermissionDenied("Solo puedes borrar tus comentarios.")
        with transaction.atomic():
            project, title = instance.idea.project, instance.idea.title
            instance.delete()
            record_activity(project, self.request.user, "idea_comment_deleted",
                            f"Eliminó un comentario de la idea «{title}».")


def candidate_users(project):
    users = {project.created_by_id}
    users.update(project.members.filter(user__isnull=False).values_list("user_id", flat=True))
    return users


class AssignmentCandidatesView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, project_id):
        project = get_object_or_404(
            accessible_projects(request.user), pk=project_id,
        )
        result = [{
            "user_id": project.created_by_id,
            "display_name": project.created_by.username,
            "is_me": project.created_by_id == request.user.id,
        }]
        for slot in project.members.filter(user__isnull=False).select_related("user").order_by("id"):
            result.append({
                "user_id": slot.user_id,
                "display_name": slot.display_name,
                "is_me": slot.user_id == request.user.id,
            })
        return Response(result)


class TaskAssignmentView(APIView):
    permission_classes = [IsAuthenticated]

    def put(self, request, project_id, task_id):
        user_ids = request.data.get("user_ids")
        if (not isinstance(user_ids, list) or
                any(not isinstance(value, int) or isinstance(value, bool) for value in user_ids) or
                len(user_ids) != len(set(user_ids))):
            raise ValidationError({"user_ids": "Selecciona integrantes sin duplicados."})

        with transaction.atomic():
            task = accessible_task(request.user, project_id, task_id)
            if task.project.created_by_id != request.user.id:
                raise PermissionDenied("Solo el creador del proyecto puede repartir esta tarea.")
            if not set(user_ids).issubset(candidate_users(task.project)):
                raise ValidationError({"user_ids": "Hay integrantes que no pertenecen al proyecto."})
            existing = set(task.assignments.values_list("user_id", flat=True))
            task.assignments.exclude(user_id__in=user_ids).delete()
            TaskAssignment.objects.bulk_create([
                TaskAssignment(task=task, user_id=user_id)
                for user_id in user_ids if user_id not in existing
            ])
            task.save(update_fields=["updated_at"])
            if existing != set(user_ids):
                record_activity(task.project, request.user, "task_assigned",
                                f"Cambió el reparto de «{task.title}».")
                send_notifications(task.project, request.user, set(user_ids) - existing,
                                   "assignment", f"Te han asignado «{task.title}».", task=task)

        task.refresh_from_db()
        return Response(TaskSerializer(task, context={"request": request}).data)


class TaskEditorsView(APIView):
    permission_classes = [IsAuthenticated]

    def put(self, request, project_id, task_id):
        user_ids = request.data.get("user_ids")
        if (not isinstance(user_ids, list) or
                any(not isinstance(value, int) or isinstance(value, bool) for value in user_ids) or
                len(user_ids) != len(set(user_ids))):
            raise ValidationError({"user_ids": "Selecciona integrantes sin duplicados."})
        with transaction.atomic():
            task = accessible_task(request.user, project_id, task_id)
            if task.project.created_by_id != request.user.id:
                raise PermissionDenied("Solo el creador del proyecto puede conceder permisos de edición.")
            allowed = candidate_users(task.project) - {task.project.created_by_id, task.created_by_id}
            if not set(user_ids).issubset(allowed):
                raise ValidationError({"user_ids": "Selecciona integrantes válidos del equipo."})
            old = set(task.editors.values_list("user_id", flat=True))
            task.editors.exclude(user_id__in=user_ids).delete()
            TaskEditor.objects.bulk_create([
                TaskEditor(task=task, user_id=user_id) for user_id in user_ids if user_id not in old
            ])
            if old != set(user_ids):
                record_activity(task.project, request.user, "task_editors",
                                f"Cambió los permisos de edición de «{task.title}».")
        return Response(TaskSerializer(task, context={"request": request}).data)


class TaskAssignmentProgressView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, project_id, task_id, user_id):
        if user_id != request.user.id:
            raise PermissionDenied("Solo puedes cambiar tu propio avance.")
        progress = request.data.get("status")
        if progress not in TaskStatus.values:
            raise ValidationError({"status": "Estado no válido."})

        with transaction.atomic():
            task = accessible_task(request.user, project_id, task_id)
            assignment = get_object_or_404(
                TaskAssignment, task=task, user_id=user_id,
            )
            before = assignment.status
            assignment.status = progress
            assignment.save(update_fields=["status", "updated_at"])
            if progress == TaskStatus.COMPLETED and not task.assignments.exclude(
                status=TaskStatus.COMPLETED,
            ).exists():
                task.status = TaskStatus.COMPLETED
                task.save(update_fields=["status", "updated_at"])
            else:
                task.save(update_fields=["updated_at"])
            if before != progress:
                status_name = {"pending": "pendiente", "inProgress": "en curso",
                               "completed": "completado"}[progress]
                record_activity(task.project, request.user, "assignment_progress",
                                f"Marcó su parte de «{task.title}» como {status_name}.")

        task.refresh_from_db()
        return Response(TaskSerializer(task, context={"request": request}).data)


class AttachmentListCreateView(generics.ListCreateAPIView):
    serializer_class = AttachmentSerializer
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def get_task(self):
        return get_object_or_404(
            Task,
            pk=self.kwargs["task_id"],
            project_id=self.kwargs["project_id"],
            project__in=accessible_projects(self.request.user),
        )

    def get_queryset(self):
        return Attachment.objects.filter(
            task=self.get_task()
        ).order_by("uploaded_at")

    def perform_create(self, serializer):
        task = self.get_task()
        file = serializer.validated_data["file"]

        original_name = file.name.replace("\\", "/").split("/")[-1][:255]
        project_limit = getattr(settings, "PIZAPP_PROJECT_STORAGE_BYTES", 1024 * 1024 * 1024)
        total_limit = getattr(settings, "PIZAPP_TOTAL_STORAGE_BYTES", 0)
        with transaction.atomic():
            used_bytes = (
                Attachment.objects.filter(task__project=task.project)
                .aggregate(total=Sum("size_bytes"))["total"] or 0
            )
            if used_bytes + file.size > project_limit:
                raise ValidationError({"file": "El proyecto ha alcanzado su límite de almacenamiento."})
            if total_limit:
                total_bytes = Attachment.objects.aggregate(total=Sum("size_bytes"))["total"] or 0
                if total_bytes + file.size > total_limit:
                    raise ValidationError({"file": "La demo ha alcanzado su límite de almacenamiento."})
            serializer.save(
                task=task,
                uploaded_by=self.request.user,
                original_name=original_name,
                size_bytes=file.size,
            )
            record_activity(task.project, self.request.user, "attachment_added",
                            f"Adjuntó «{original_name}» a «{task.title}».")


class AttachmentDownloadView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, project_id, task_id, attachment_id):
        attachment = get_object_or_404(
            Attachment,
            pk=attachment_id,
            task_id=task_id,
            task__project_id=project_id,
            task__project__in=accessible_projects(request.user),
        )

        return FileResponse(
            attachment.file.open("rb"),
            as_attachment=True,
            filename=attachment.original_name,
        )


class ProjectSlotView(APIView):
    permission_classes = [IsAuthenticated]

    def get_project(self, request, project_id):
        return get_object_or_404(accessible_projects(request.user), pk=project_id)

    def get(self, request, project_id):
        project = self.get_project(request, project_id)
        slots = project.members.select_related("user").order_by("id")
        return Response(ProjectMemberSerializer(slots, many=True).data)

    def post(self, request, project_id):
        project = self.get_project(request, project_id)
        if project.created_by_id != request.user.id:
            raise PermissionDenied("Solo el creador puede preparar plazas.")
        serializer = ProjectSlotSerializer(
            data=request.data, context={"project": project},
        )
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            slot = ProjectMember.objects.create(
                project=project, display_name=serializer.validated_data["display_name"],
            )
            record_activity(project, request.user, "member_slot_created",
                            f"Preparó la plaza «{slot.display_name}».")
        return Response(ProjectMemberSerializer(slot).data, status=status.HTTP_201_CREATED)


class ProjectSlotDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, project_id, slot_id):
        project = get_object_or_404(Project, pk=project_id, created_by=request.user)
        slot = get_object_or_404(ProjectMember, pk=slot_id, project=project)
        with transaction.atomic():
            if slot.user_id is not None:
                TaskAssignment.objects.filter(
                    task__project=project, user_id=slot.user_id,
                ).delete()
                TaskEditor.objects.filter(
                    task__project=project, user_id=slot.user_id,
                ).delete()
            name = slot.display_name
            slot.delete()
            record_activity(project, request.user, "member_removed",
                            f"Quitó del equipo la plaza «{name}».")
        return Response(status=status.HTTP_204_NO_CONTENT)


class InvitationView(APIView):
    permission_classes = [IsAuthenticated]

    def get_project(self, code):
        return get_object_or_404(Project, invite_code=code)

    def get(self, request, code):
        project = self.get_project(code)
        free_slots = project.members.filter(user__isnull=True).order_by("id")
        return Response({
            "project_id": project.id,
            "project_name": project.name,
            "owner_name": project.created_by.username,
            "slots": ProjectMemberSerializer(free_slots, many=True).data,
        })


class InvitationJoinView(InvitationView):
    def post(self, request, code):
        project = self.get_project(code)
        if project.created_by_id == request.user.id or project.members.filter(
            user=request.user,
        ).exists():
            raise ValidationError("Ya formas parte de este proyecto.")

        slot_id = request.data.get("slot_id")
        if not isinstance(slot_id, int) or isinstance(slot_id, bool):
            raise ValidationError({"slot_id": "Selecciona una plaza disponible."})

        try:
            with transaction.atomic():
                claimed = ProjectMember.objects.filter(
                    pk=slot_id, project=project, user__isnull=True,
                ).update(user=request.user, joined_at=timezone.now())
                if claimed:
                    slot_name = ProjectMember.objects.get(pk=slot_id).display_name
                    record_activity(project, request.user, "member_joined",
                                    f"Se unió al equipo como «{slot_name}».")
        except IntegrityError:
            raise ValidationError("Ya formas parte de este proyecto.")
        if not claimed:
            raise ValidationError("Esa plaza ya no está disponible.")
        return Response(ProjectSerializer(project, context={"request": request}).data)
