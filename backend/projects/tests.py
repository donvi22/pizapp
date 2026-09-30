from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from datetime import timedelta
from tempfile import TemporaryDirectory
from rest_framework.test import APITestCase

from .models import Attachment, Idea, IdeaComment, Milestone, Notification, Project, ProjectActivity, ProjectMember, Task, TaskAssignment, TaskComment, TaskEditor


class ProjectInvitationTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.owner = User.objects.create_user(username="owner", email="owner@example.com", password="pass12345")
        self.guest = User.objects.create_user(username="guest", email="guest@example.com", password="pass12345")
        self.stranger = User.objects.create_user(username="stranger", email="stranger@example.com", password="pass12345")
        self.project = Project.objects.create(name="Clase", created_by=self.owner)
        self.task = Task.objects.create(project=self.project, title="Diseño", created_by=self.owner)

    def test_join_edit_attachment_and_revoke(self):
        root = f"/api/projects/{self.project.id}/"
        self.client.force_authenticate(user=self.owner)
        created = self.client.post(root + "slots/", {"display_name": "Ana"}, format="json")
        self.assertEqual(created.status_code, 201)
        slot_id = created.data["id"]
        self.client.force_authenticate(user=self.guest)
        self.assertEqual(self.client.get("/api/projects/").data, [])
        self.assertEqual(self.client.get(root + "tasks/").status_code, 404)
        self.assertEqual(self.client.post(root + "slots/", {"display_name": "Otra"}).status_code, 404)

        invite = f"/api/invitations/{self.project.invite_code}/"
        self.assertEqual(self.client.get(invite).data["slots"][0]["id"], slot_id)
        self.assertEqual(self.client.post(invite + "join/", {"slot_id": slot_id}, format="json").status_code, 200)
        self.assertEqual(len(self.client.get("/api/projects/").data), 1)
        self.assertEqual(self.client.get(root + "tasks/").status_code, 200)
        self.assertEqual(self.client.patch(root + f"tasks/{self.task.id}/", {
            "title": "Sin permiso",
        }, format="json").status_code, 403)
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.put(root + f"tasks/{self.task.id}/editors/", {
            "user_ids": [self.guest.id],
        }, format="json").status_code, 200)
        self.client.force_authenticate(user=self.guest)
        self.assertEqual(self.client.put(root + f"tasks/{self.task.id}/", {
            "title": "Diseño final", "description": "", "canvas_data": {},
            "status": "pending", "color": "yellow",
        }, format="json").status_code, 200)
        self.assertEqual(self.client.post(root + "slots/", {"display_name": "Otra"}).status_code, 403)

        with TemporaryDirectory() as media_dir, override_settings(MEDIA_ROOT=media_dir):
            uploaded = self.client.post(
                root + f"tasks/{self.task.id}/attachments/",
                {"file": SimpleUploadedFile("nota.txt", b"contenido")},
            )
            self.assertEqual(uploaded.status_code, 201)
            download_url = root + f"tasks/{self.task.id}/attachments/{uploaded.data['id']}/download/"
            response = self.client.get(download_url)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(b"".join(response.streaming_content), b"contenido")
            self.client.force_authenticate(user=self.stranger)
            self.assertEqual(self.client.get(download_url).status_code, 404)

        self.assertEqual(self.client.post(invite + "join/", {"slot_id": slot_id}, format="json").status_code, 400)
        self.assertEqual(self.client.get(root + "tasks/").status_code, 404)

        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.delete(root + f"slots/{slot_id}/").status_code, 204)
        self.client.force_authenticate(user=self.guest)
        self.assertEqual(self.client.get(root + "tasks/").status_code, 404)

    def test_owner_cannot_add_duplicate_names(self):
        self.client.force_authenticate(user=self.owner)
        root = f"/api/projects/{self.project.id}/slots/"
        self.assertEqual(self.client.post(root, {"display_name": "Ana"}).status_code, 201)
        self.assertEqual(self.client.post(root, {"display_name": "ana"}).status_code, 400)


class TaskAssignmentTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.owner = User.objects.create_user(username="owner", email="owner@example.com", password="pass12345")
        self.ana = User.objects.create_user(username="ana", email="ana@example.com", password="pass12345")
        self.luis = User.objects.create_user(username="luis", email="luis@example.com", password="pass12345")
        self.outsider = User.objects.create_user(username="outsider", email="outside@example.com", password="pass12345")
        self.project = Project.objects.create(name="Compartido", created_by=self.owner)
        self.ana_slot = ProjectMember.objects.create(project=self.project, user=self.ana, display_name="Ana")
        ProjectMember.objects.create(project=self.project, user=self.luis, display_name="Luis")
        self.task = Task.objects.create(project=self.project, title="Boceto", created_by=self.owner)
        self.url = f"/api/projects/{self.project.id}/tasks/{self.task.id}/assignments/"

    def test_reparto_progreso_y_revocacion(self):
        self.client.force_authenticate(user=self.ana)
        candidates = self.client.get(f"/api/projects/{self.project.id}/assignment-candidates/")
        self.assertEqual(candidates.status_code, 200)
        self.assertEqual({item["user_id"] for item in candidates.data},
                         {self.owner.id, self.ana.id, self.luis.id})
        self.assertEqual(self.client.put(self.url, {
            "user_ids": [self.ana.id, self.luis.id],
        }, format="json").status_code, 403)
        self.client.force_authenticate(user=self.owner)
        assigned = self.client.put(self.url, {
            "user_ids": [self.ana.id, self.luis.id],
        }, format="json")
        self.assertEqual(assigned.status_code, 200)
        self.assertEqual(len(assigned.data["assignments"]), 2)

        self.client.force_authenticate(user=self.outsider)
        self.assertEqual(self.client.put(self.url, {"user_ids": []}, format="json").status_code, 404)
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.put(self.url, {"user_ids": [self.outsider.id]}, format="json").status_code, 400)
        self.assertEqual(self.client.patch(self.url + f"{self.ana.id}/", {
            "status": "completed",
        }, format="json").status_code, 403)

        self.client.force_authenticate(user=self.ana)
        self.assertEqual(self.client.patch(self.url + f"{self.ana.id}/", {
            "status": "completed",
        }, format="json").data["status"], "pending")
        self.assertEqual(self.client.put(self.url, {
            "user_ids": [self.ana.id, self.luis.id],
        }, format="json").status_code, 403)
        self.client.force_authenticate(user=self.owner)
        preserved = self.client.put(self.url, {
            "user_ids": [self.ana.id, self.luis.id],
        }, format="json")
        self.assertEqual(next(item for item in preserved.data["assignments"]
                              if item["user_id"] == self.ana.id)["status"], "completed")
        self.client.force_authenticate(user=self.luis)
        self.assertEqual(self.client.patch(self.url + f"{self.luis.id}/", {
            "status": "completed",
        }, format="json").data["status"], "completed")

        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.delete(
            f"/api/projects/{self.project.id}/slots/{self.ana_slot.id}/",
        ).status_code, 204)
        self.assertFalse(TaskAssignment.objects.filter(task=self.task, user=self.ana).exists())
        self.client.force_authenticate(user=self.ana)
        self.assertEqual(self.client.get(
            f"/api/projects/{self.project.id}/tasks/",
        ).status_code, 404)
        self.assertEqual(self.client.patch(self.url + f"{self.ana.id}/", {
            "status": "pending",
        }, format="json").status_code, 404)

    def test_fecha_vencida_no_bloquea_edicion_y_puede_quitarse(self):
        url = f"/api/projects/{self.project.id}/tasks/{self.task.id}/"
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.put(url + "editors/", {
            "user_ids": [self.ana.id],
        }, format="json").status_code, 200)
        self.client.force_authenticate(user=self.ana)
        changed = self.client.patch(url, {
            "due_date": "2020-01-01", "title": "Boceto actualizado",
        }, format="json")
        self.assertEqual(changed.status_code, 200)
        self.assertEqual(changed.data["due_date"], "2020-01-01")
        self.assertEqual(changed.data["title"], "Boceto actualizado")
        self.assertEqual(self.client.patch(url, {
            "status": "completed",
        }, format="json").status_code, 200)
        removed = self.client.patch(url, {"due_date": None}, format="json")
        self.assertEqual(removed.status_code, 200)
        self.assertIsNone(removed.data["due_date"])


class MilestoneTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.owner = User.objects.create_user(username="owner", email="owner@example.com", password="pass12345")
        self.member = User.objects.create_user(username="member", email="member@example.com", password="pass12345")
        self.outsider = User.objects.create_user(username="outsider", email="outsider@example.com", password="pass12345")
        self.project = Project.objects.create(name="Compartido", created_by=self.owner)
        ProjectMember.objects.create(project=self.project, user=self.member, display_name="Miembro")
        self.other_project = Project.objects.create(name="Privado", created_by=self.owner)
        self.task = Task.objects.create(project=self.project, title="Entrega", created_by=self.owner)
        self.list_url = f"/api/projects/{self.project.id}/milestones/"

    def test_member_creates_closes_and_reopens_milestone_with_pending_task(self):
        self.client.force_authenticate(user=self.member)
        created = self.client.post(self.list_url, {
            "name": "Primera entrega", "due_date": "2020-01-01",
        }, format="json")
        self.assertEqual(created.status_code, 201)
        milestone_id = created.data["id"]
        detail_url = self.list_url + f"{milestone_id}/"
        task_url = f"/api/projects/{self.project.id}/tasks/{self.task.id}/"
        self.assertEqual(self.client.patch(task_url, {"milestone": milestone_id}, format="json").status_code, 403)
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.put(task_url + "editors/", {
            "user_ids": [self.member.id],
        }, format="json").status_code, 200)
        self.client.force_authenticate(user=self.member)
        linked = self.client.patch(task_url, {"milestone": milestone_id}, format="json")
        self.assertEqual(linked.status_code, 200)
        self.assertEqual(linked.data["milestone_name"], "Primera entrega")
        closed = self.client.patch(detail_url, {"is_closed": True}, format="json")
        self.assertEqual(closed.status_code, 200)
        self.assertTrue(closed.data["is_closed"])
        self.assertEqual(self.client.patch(task_url, {
            "title": "Entrega después del cierre", "status": "completed",
        }, format="json").status_code, 200)
        reopened = self.client.patch(detail_url, {
            "is_closed": False, "due_date": None,
        }, format="json")
        self.assertEqual(reopened.status_code, 200)
        self.assertIsNone(reopened.data["due_date"])

        other = Milestone.objects.create(
            project=self.other_project, name="Ajeno", created_by=self.owner,
        )
        self.assertEqual(self.client.patch(task_url, {
            "milestone": other.id,
        }, format="json").status_code, 400)
        self.client.force_authenticate(user=self.outsider)
        self.assertEqual(self.client.get(self.list_url).status_code, 404)
        self.assertEqual(self.client.patch(detail_url, {
            "name": "Intruso",
        }, format="json").status_code, 404)

        self.client.force_authenticate(user=self.member)
        self.assertTrue(self.client.get(self.list_url).data[0]["can_delete"])
        self.assertEqual(self.client.delete(detail_url).status_code, 204)
        self.task.refresh_from_db()
        self.assertIsNone(self.task.milestone_id)

    def test_member_cannot_remove_milestone_created_by_another(self):
        milestone = Milestone.objects.create(
            project=self.project, name="Del creador", created_by=self.owner,
        )
        self.client.force_authenticate(user=self.member)
        self.assertFalse(self.client.get(self.list_url).data[0]["can_delete"])
        self.assertEqual(self.client.delete(
            self.list_url + f"{milestone.id}/",
        ).status_code, 403)


class IdeaAndCommentTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.owner = User.objects.create_user(username="owner", email="owner@example.com", password="pass12345")
        self.member = User.objects.create_user(username="member", email="member@example.com", password="pass12345")
        self.outsider = User.objects.create_user(username="outsider", email="outsider@example.com", password="pass12345")
        self.project = Project.objects.create(name="Proyecto", created_by=self.owner)
        self.other = Project.objects.create(name="Ajeno", created_by=self.outsider)
        ProjectMember.objects.create(project=self.project, user=self.member, display_name="Ana")
        self.task = Task.objects.create(project=self.project, title="Inicial", created_by=self.owner)
        self.task_comments = f"/api/projects/{self.project.id}/tasks/{self.task.id}/comments/"
        self.ideas = f"/api/projects/{self.project.id}/ideas/"

    def test_ideas_convert_once_and_keep_conversation(self):
        self.client.force_authenticate(user=self.member)
        idea = self.client.post(self.ideas, {"title": "  Boceto  ", "description": "Dibujar"}, format="json")
        self.assertEqual(idea.status_code, 201)
        idea_id = idea.data["id"]
        comments = self.ideas + f"{idea_id}/comments/"
        posted = self.client.post(comments, {"text": "¿Qué opináis?"}, format="json")
        self.assertEqual(posted.status_code, 201)
        self.assertEqual(posted.data["author_name"], "Ana")
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.get(comments).data[0]["text"], "¿Qué opináis?")
        converted = self.client.post(self.ideas + f"{idea_id}/convert/", {}, format="json")
        self.assertEqual(converted.status_code, 201)
        self.assertEqual(converted.data["title"], "Boceto")
        self.assertEqual(converted.data["description"], "Dibujar")
        self.assertEqual(self.client.post(self.ideas + f"{idea_id}/convert/", {}, format="json").status_code, 400)
        self.assertEqual(Task.objects.filter(project=self.project).count(), 2)
        self.assertEqual(self.client.get(self.ideas + f"{idea_id}/").data["converted_task"], converted.data["id"])

    def test_comments_are_private_and_only_author_can_delete(self):
        self.client.force_authenticate(user=self.member)
        self.assertEqual(self.client.post(self.task_comments, {"text": "   "}, format="json").status_code, 400)
        self.assertEqual(self.client.post(self.task_comments, {"text": "x" * 2001}, format="json").status_code, 400)
        posted = self.client.post(self.task_comments, {"text": "  Listo  "}, format="json")
        self.assertEqual(posted.status_code, 201)
        comment_id = posted.data["id"]
        self.assertEqual(posted.data["text"], "Listo")
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.get(self.task_comments).data[0]["author_name"], "Ana")
        self.assertEqual(self.client.delete(self.task_comments + f"{comment_id}/").status_code, 403)
        self.client.force_authenticate(user=self.outsider)
        self.assertEqual(self.client.get(self.ideas).status_code, 404)
        self.assertEqual(self.client.get(self.task_comments).status_code, 404)
        self.assertEqual(self.client.post(self.task_comments, {"text": "Intruso"}, format="json").status_code, 404)
        self.assertEqual(self.client.delete(self.task_comments + f"{comment_id}/").status_code, 404)
        self.client.force_authenticate(user=self.member)
        self.assertEqual(self.client.delete(self.task_comments + f"{comment_id}/").status_code, 204)
        self.assertEqual(self.client.get(self.task_comments).data, [])

    def test_idea_url_cannot_mix_projects_or_membership_after_revocation(self):
        self.client.force_authenticate(user=self.owner)
        idea = self.client.post(self.ideas, {"title": "Privada"}, format="json")
        self.assertEqual(idea.status_code, 201)
        wrong_url = f"/api/projects/{self.other.id}/ideas/{idea.data['id']}/comments/"
        self.client.force_authenticate(user=self.outsider)
        self.assertEqual(self.client.get(wrong_url).status_code, 404)
        self.client.force_authenticate(user=self.member)
        ProjectMember.objects.filter(project=self.project, user=self.member).delete()
        self.assertEqual(self.client.get(self.ideas).status_code, 404)
        self.assertEqual(self.client.get(self.ideas + f"{idea.data['id']}/comments/").status_code, 404)


class DeletionTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.owner = User.objects.create_user(username="owner", email="owner@example.com", password="pass12345")
        self.author = User.objects.create_user(username="author", email="author@example.com", password="pass12345")
        self.other = User.objects.create_user(username="other", email="other@example.com", password="pass12345")
        self.outsider = User.objects.create_user(username="outsider", email="outsider@example.com", password="pass12345")
        self.project = Project.objects.create(name="Grupo", created_by=self.owner)
        ProjectMember.objects.create(project=self.project, user=self.author, display_name="Ana")
        ProjectMember.objects.create(project=self.project, user=self.other, display_name="Luis")
        self.milestone = Milestone.objects.create(project=self.project, name="Entrega", created_by=self.owner)
        self.task = Task.objects.create(project=self.project, title="Tarea", created_by=self.author,
                                        milestone=self.milestone)
        self.idea = Idea.objects.create(project=self.project, title="Idea", created_by=self.author,
                                       converted_task=self.task)
        TaskComment.objects.create(task=self.task, author=self.owner, text="Comentario")
        IdeaComment.objects.create(idea=self.idea, author=self.author, text="Idea")
        self.task_url = f"/api/projects/{self.project.id}/tasks/{self.task.id}/"
        self.idea_url = f"/api/projects/{self.project.id}/ideas/{self.idea.id}/"
        self.project_url = f"/api/projects/{self.project.id}/"

    def test_members_can_only_delete_their_own_items_owner_can_delete_all(self):
        self.client.force_authenticate(user=self.other)
        self.assertFalse(self.client.get(self.task_url).data["can_delete"])
        self.assertFalse(self.client.get(self.idea_url).data["can_delete"])
        self.assertEqual(self.client.delete(self.task_url).status_code, 403)
        self.assertEqual(self.client.delete(self.idea_url).status_code, 403)
        self.assertEqual(self.client.delete(self.project_url).status_code, 403)
        self.client.force_authenticate(user=self.outsider)
        for url in (self.task_url, self.idea_url, self.project_url):
            self.assertEqual(self.client.delete(url).status_code, 404)
        self.client.force_authenticate(user=self.author)
        self.assertTrue(self.client.get(self.task_url).data["can_delete"])
        self.assertTrue(self.client.get(self.idea_url).data["can_delete"])
        self.assertEqual(self.client.delete(self.project_url).status_code, 403)
        self.assertEqual(self.client.delete(self.task_url).status_code, 204)
        self.idea.refresh_from_db()
        self.assertIsNone(self.idea.converted_task_id)
        self.assertFalse(TaskComment.objects.exists())
        self.assertEqual(self.client.delete(self.idea_url).status_code, 204)
        self.assertFalse(IdeaComment.objects.exists())
        self.assertTrue(Milestone.objects.filter(pk=self.milestone.id).exists())

    def test_owner_deletes_project_and_attachment_files_after_commit(self):
        with TemporaryDirectory() as media_dir, override_settings(MEDIA_ROOT=media_dir):
            attachment = Attachment.objects.create(
                task=self.task, uploaded_by=self.author, original_name="prueba.txt",
                size_bytes=4, file=SimpleUploadedFile("prueba.txt", b"dato"),
            )
            storage, name = attachment.file.storage, attachment.file.name
            self.assertTrue(storage.exists(name))
            self.client.force_authenticate(user=self.owner)
            with self.captureOnCommitCallbacks(execute=True):
                self.assertEqual(self.client.delete(self.project_url).status_code, 204)
            self.assertFalse(Project.objects.filter(pk=self.project.id).exists())
            self.assertFalse(Task.objects.filter(pk=self.task.id).exists())
            self.assertFalse(Idea.objects.filter(pk=self.idea.id).exists())
            self.assertFalse(Milestone.objects.filter(pk=self.milestone.id).exists())
            self.assertFalse(storage.exists(name))

    def test_deleting_task_removes_its_file_but_keeps_milestone_and_idea(self):
        with TemporaryDirectory() as media_dir, override_settings(MEDIA_ROOT=media_dir):
            attachment = Attachment.objects.create(
                task=self.task, uploaded_by=self.author, original_name="tarea.txt",
                size_bytes=4, file=SimpleUploadedFile("tarea.txt", b"dato"),
            )
            storage, name = attachment.file.storage, attachment.file.name
            self.client.force_authenticate(user=self.author)
            with self.captureOnCommitCallbacks(execute=True):
                self.assertEqual(self.client.delete(self.task_url).status_code, 204)
            self.assertFalse(storage.exists(name))
            self.assertFalse(Task.objects.filter(pk=self.task.id).exists())
            self.assertTrue(Milestone.objects.filter(pk=self.milestone.id).exists())
            self.idea.refresh_from_db()
            self.assertIsNone(self.idea.converted_task_id)

    def test_deleting_milestone_keeps_task_and_idea(self):
        self.client.force_authenticate(user=self.owner)
        url = f"/api/projects/{self.project.id}/milestones/{self.milestone.id}/"
        self.assertEqual(self.client.delete(url).status_code, 204)
        self.task.refresh_from_db()
        self.assertIsNone(self.task.milestone_id)
        self.assertTrue(Idea.objects.filter(pk=self.idea.id).exists())


class ActivityTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.owner = User.objects.create_user(username="owner", email="owner@example.com", password="pass12345")
        self.member = User.objects.create_user(username="member", email="member@example.com", password="pass12345")
        self.outsider = User.objects.create_user(username="outsider", email="outsider@example.com", password="pass12345")
        self.project = Project.objects.create(name="Grupo", created_by=self.owner)
        self.slot = ProjectMember.objects.create(project=self.project, user=self.member, display_name="Ana")
        self.url = f"/api/projects/{self.project.id}/activity/"

    def test_history_records_actions_with_actor_and_is_private(self):
        self.client.force_authenticate(user=self.member)
        task_url = f"/api/projects/{self.project.id}/tasks/"
        created = self.client.post(task_url, {"title": "Boceto", "color": "yellow"}, format="json")
        self.assertEqual(created.status_code, 201)
        detail = task_url + f"{created.data['id']}/"
        self.assertEqual(self.client.patch(detail, {"title": "Boceto 2"}, format="json").status_code, 200)
        comments = detail + "comments/"
        self.assertEqual(self.client.post(comments, {"text": "Texto privado"}, format="json").status_code, 201)
        self.assertEqual(self.client.delete(detail).status_code, 204)
        history = self.client.get(self.url)
        self.assertEqual(history.status_code, 200)
        self.assertEqual(history.data["count"], 4)
        self.assertEqual([row["action"] for row in history.data["results"]],
                         ["task_deleted", "task_comment", "task_updated", "task_created"])
        self.assertTrue(all(row["actor_name"] == "Ana" for row in history.data["results"]))
        self.assertNotIn("Texto privado", str(history.data))
        self.client.force_authenticate(user=self.outsider)
        self.assertEqual(self.client.get(self.url).status_code, 404)
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.delete(
            f"/api/projects/{self.project.id}/slots/{self.slot.id}/",
        ).status_code, 204)
        after_removal = self.client.get(self.url)
        self.assertEqual(after_removal.data["results"][0]["action"], "member_removed")
        self.assertEqual(after_removal.data["results"][1]["actor_name"], "Ana")
        self.client.force_authenticate(user=self.member)
        self.assertEqual(self.client.get(self.url).status_code, 404)

    def test_history_paginates_and_rejects_bad_offsets(self):
        ProjectActivity.objects.bulk_create([
            ProjectActivity(project=self.project, actor=self.owner,
                            actor_name="owner", action="test", description=f"Cambio {n}")
            for n in range(55)
        ])
        self.client.force_authenticate(user=self.owner)
        first = self.client.get(self.url)
        self.assertEqual(first.data["count"], 55)
        self.assertEqual(len(first.data["results"]), 50)
        self.assertEqual(first.data["next_offset"], 50)
        second = self.client.get(self.url + "?offset=50")
        self.assertEqual(len(second.data["results"]), 5)
        self.assertIsNone(second.data["next_offset"])
        self.assertEqual(len({row["id"] for row in first.data["results"] + second.data["results"]}), 55)
        self.assertEqual(self.client.get(self.url + "?offset=-1").status_code, 400)
        self.assertEqual(self.client.get(self.url + "?offset=nan").status_code, 400)

    def test_ideas_milestones_assignments_and_noop_edits(self):
        self.client.force_authenticate(user=self.owner)
        root = f"/api/projects/{self.project.id}/"
        milestone = self.client.post(root + "milestones/", {"name": "Entrega"}, format="json")
        self.assertEqual(milestone.status_code, 201)
        milestone_url = root + f"milestones/{milestone.data['id']}/"
        self.assertEqual(self.client.patch(milestone_url, {"is_closed": True}, format="json").status_code, 200)
        idea = self.client.post(root + "ideas/", {"title": "Propuesta"}, format="json")
        self.assertEqual(idea.status_code, 201)
        idea_id = idea.data["id"]
        self.assertEqual(self.client.post(root + f"ideas/{idea_id}/comments/",
                                          {"text": "Hola"}, format="json").status_code, 201)
        task = self.client.post(root + f"ideas/{idea_id}/convert/", {}, format="json")
        self.assertEqual(task.status_code, 201)
        task_url = root + f"tasks/{task.data['id']}/"
        self.assertEqual(self.client.patch(task_url, {"title": "Propuesta"}, format="json").status_code, 200)
        self.assertEqual(self.client.put(task_url + "assignments/",
                                         {"user_ids": [self.member.id]}, format="json").status_code, 200)
        self.client.force_authenticate(user=self.member)
        self.assertEqual(self.client.patch(task_url + f"assignments/{self.member.id}/",
                                           {"status": "completed"}, format="json").status_code, 200)
        actions = [entry["action"] for entry in self.client.get(self.url).data["results"]]
        self.assertEqual(actions, [
            "assignment_progress", "task_assigned", "idea_converted", "idea_comment",
            "idea_created", "milestone_closed", "milestone_created",
        ])


class NotificationTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.owner = User.objects.create_user(username="owner", email="owner@example.com", password="pass12345")
        self.ana = User.objects.create_user(username="ana", email="ana@example.com", password="pass12345")
        self.luis = User.objects.create_user(username="luis", email="luis@example.com", password="pass12345")
        self.outsider = User.objects.create_user(username="outsider", email="outsider@example.com", password="pass12345")
        self.project = Project.objects.create(name="Grupo", created_by=self.owner)
        self.ana_slot = ProjectMember.objects.create(project=self.project, user=self.ana, display_name="Ana")
        ProjectMember.objects.create(project=self.project, user=self.luis, display_name="Luis")
        self.task = Task.objects.create(project=self.project, title="Entrega", created_by=self.owner)
        self.task_url = f"/api/projects/{self.project.id}/tasks/{self.task.id}/"

    def test_assignment_and_comment_notifications_are_private_and_readable(self):
        self.client.force_authenticate(user=self.owner)
        assigned = self.client.put(self.task_url + "assignments/",
                                   {"user_ids": [self.ana.id]}, format="json")
        self.assertEqual(assigned.status_code, 200)
        self.client.force_authenticate(user=self.ana)
        inbox = self.client.get("/api/notifications/")
        self.assertEqual(inbox.data["unread_count"], 1)
        self.assertEqual(inbox.data["results"][0]["kind"], "assignment")
        notification_id = inbox.data["results"][0]["id"]
        self.assertEqual(self.client.patch(f"/api/notifications/{notification_id}/").status_code, 200)
        self.assertEqual(self.client.get("/api/notifications/").data["unread_count"], 0)
        comment = self.client.post(self.task_url + "comments/", {"text": "He empezado"}, format="json")
        self.assertEqual(comment.status_code, 201)
        self.assertEqual(self.client.get("/api/notifications/").data["count"], 1)
        self.client.force_authenticate(user=self.owner)
        owner_inbox = self.client.get("/api/notifications/")
        self.assertEqual(owner_inbox.data["results"][0]["kind"], "task_comment")
        self.assertIn("Ana", owner_inbox.data["results"][0]["message"])
        self.assertEqual(self.client.post("/api/notifications/read-all/").status_code, 200)
        self.assertEqual(self.client.get("/api/notifications/").data["unread_count"], 0)
        self.client.force_authenticate(user=self.luis)
        self.assertEqual(self.client.get("/api/notifications/").data["count"], 0)
        self.assertEqual(self.client.patch(f"/api/notifications/{notification_id}/").status_code, 404)
        self.client.force_authenticate(user=self.outsider)
        self.assertEqual(self.client.get("/api/notifications/").data["count"], 0)

    def test_due_reminder_deduplicates_and_respects_assignments_and_revocation(self):
        tomorrow = timezone.localdate() + timedelta(days=1)
        self.task.due_date = tomorrow
        self.task.save(update_fields=["due_date"])
        TaskAssignment.objects.create(task=self.task, user=self.ana)
        self.client.force_authenticate(user=self.ana)
        self.assertEqual(self.client.post("/api/notifications/sync/").status_code, 200)
        self.assertEqual(self.client.post("/api/notifications/sync/").status_code, 200)
        inbox = self.client.get("/api/notifications/")
        self.assertEqual(inbox.data["count"], 1)
        self.assertEqual(inbox.data["results"][0]["kind"], "due_date")
        self.assertIn("mañana", inbox.data["results"][0]["message"])
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.post("/api/notifications/sync/").status_code, 200)
        self.assertEqual(self.client.get("/api/notifications/").data["count"], 0)
        self.assertEqual(self.client.delete(
            f"/api/projects/{self.project.id}/slots/{self.ana_slot.id}/",
        ).status_code, 204)
        self.client.force_authenticate(user=self.ana)
        self.assertEqual(self.client.get("/api/notifications/").data["count"], 0)
        self.assertEqual(self.client.post("/api/notifications/sync/").status_code, 200)
        self.assertEqual(self.client.get("/api/notifications/").data["count"], 0)
        self.assertEqual(Notification.objects.filter(recipient=self.ana).count(), 1)

    def test_completed_tasks_do_not_create_new_due_reminders(self):
        self.task.due_date = timezone.localdate()
        self.task.status = "completed"
        self.task.save(update_fields=["due_date", "status"])
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.post("/api/notifications/sync/").status_code, 200)
        self.assertEqual(self.client.get("/api/notifications/").data["count"], 0)

    def test_idea_comments_notify_idea_author_only_once(self):
        self.client.force_authenticate(user=self.ana)
        idea = self.client.post(f"/api/projects/{self.project.id}/ideas/",
                                {"title": "Diseño"}, format="json")
        self.assertEqual(idea.status_code, 201)
        self.client.force_authenticate(user=self.luis)
        url = f"/api/projects/{self.project.id}/ideas/{idea.data['id']}/comments/"
        self.assertEqual(self.client.post(url, {"text": "Me parece bien"}, format="json").status_code, 201)
        self.client.force_authenticate(user=self.ana)
        inbox = self.client.get("/api/notifications/")
        self.assertEqual(inbox.data["count"], 1)
        self.assertEqual(inbox.data["results"][0]["kind"], "idea_comment")
        self.assertEqual(inbox.data["results"][0]["idea"], idea.data["id"])


class TaskPermissionTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.owner = User.objects.create_user(username="owner", email="owner@example.com", password="pass12345")
        self.author = User.objects.create_user(username="author", email="author@example.com", password="pass12345")
        self.editor = User.objects.create_user(username="editor", email="editor@example.com", password="pass12345")
        self.outsider = User.objects.create_user(username="outsider", email="outsider@example.com", password="pass12345")
        self.project = Project.objects.create(name="Grupo", created_by=self.owner)
        ProjectMember.objects.create(project=self.project, user=self.author, display_name="Autor")
        self.editor_slot = ProjectMember.objects.create(project=self.project, user=self.editor, display_name="Editor")
        self.task = Task.objects.create(project=self.project, title="Tarea", created_by=self.author)
        self.task_url = f"/api/projects/{self.project.id}/tasks/{self.task.id}/"
        self.editors_url = self.task_url + "editors/"

    def test_owner_grants_and_revokes_edit_but_editor_cannot_manage_or_delete(self):
        self.client.force_authenticate(user=self.editor)
        self.assertFalse(self.client.get(self.task_url).data["can_edit"])
        self.assertEqual(self.client.patch(self.task_url, {"title": "No"}, format="json").status_code, 403)
        self.assertEqual(self.client.put(self.editors_url, {"user_ids": [self.editor.id]}, format="json").status_code, 403)
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.put(self.editors_url, {"user_ids": [self.outsider.id]}, format="json").status_code, 400)
        granted = self.client.put(self.editors_url, {"user_ids": [self.editor.id]}, format="json")
        self.assertEqual(granted.status_code, 200)
        self.assertIn(self.editor.id, granted.data["editor_user_ids"])
        self.client.force_authenticate(user=self.editor)
        self.assertTrue(self.client.get(self.task_url).data["can_edit"])
        self.assertFalse(self.client.get(self.task_url).data["can_manage"])
        self.assertEqual(self.client.patch(self.task_url, {"title": "Editada"}, format="json").status_code, 200)
        self.assertEqual(self.client.delete(self.task_url).status_code, 403)
        self.assertEqual(self.client.put(self.task_url + "assignments/", {"user_ids": []}, format="json").status_code, 403)
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.put(self.editors_url, {"user_ids": []}, format="json").status_code, 200)
        self.client.force_authenticate(user=self.editor)
        self.assertEqual(self.client.patch(self.task_url, {"title": "Otra"}, format="json").status_code, 403)
        self.client.force_authenticate(user=self.author)
        self.assertTrue(self.client.get(self.task_url).data["can_edit"])
        self.assertFalse(self.client.get(self.task_url).data["can_manage"])
        self.assertEqual(self.client.patch(self.task_url, {"title": "Autor"}, format="json").status_code, 200)

    def test_revoking_membership_removes_editor_grant(self):
        self.client.force_authenticate(user=self.owner)
        self.assertEqual(self.client.put(self.editors_url, {"user_ids": [self.editor.id]}, format="json").status_code, 200)
        self.assertEqual(self.client.delete(
            f"/api/projects/{self.project.id}/slots/{self.editor_slot.id}/",
        ).status_code, 204)
        self.assertFalse(TaskEditor.objects.filter(task=self.task, user=self.editor).exists())
        self.client.force_authenticate(user=self.editor)
        self.assertEqual(self.client.get(self.task_url).status_code, 404)

    def test_only_owner_approves_ideas_and_authors_edit_own_milestones(self):
        self.client.force_authenticate(user=self.author)
        idea = self.client.post(f"/api/projects/{self.project.id}/ideas/",
                                {"title": "Idea"}, format="json")
        self.assertEqual(idea.status_code, 201)
        convert_url = f"/api/projects/{self.project.id}/ideas/{idea.data['id']}/convert/"
        self.assertFalse(idea.data["can_convert"])
        self.assertEqual(self.client.post(convert_url, {}, format="json").status_code, 403)
        own_milestone = self.client.post(f"/api/projects/{self.project.id}/milestones/",
                                         {"name": "Propio"}, format="json")
        self.assertEqual(own_milestone.status_code, 201)
        own_url = f"/api/projects/{self.project.id}/milestones/{own_milestone.data['id']}/"
        self.assertEqual(self.client.patch(own_url, {"is_closed": True}, format="json").status_code, 200)
        self.client.force_authenticate(user=self.editor)
        self.assertFalse(self.client.get(own_url).data["can_edit"])
        self.assertEqual(self.client.patch(own_url, {"name": "Ajeno"}, format="json").status_code, 403)
        self.client.force_authenticate(user=self.owner)
        self.assertTrue(self.client.get(own_url).data["can_edit"])
        self.assertEqual(self.client.post(convert_url, {}, format="json").status_code, 201)
