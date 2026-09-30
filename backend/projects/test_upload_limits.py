from tempfile import TemporaryDirectory

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from .models import Attachment, Project, Task


class UploadLimitTests(APITestCase):
    def setUp(self):
        media_dir = self.enterContext(TemporaryDirectory())
        self.enterContext(override_settings(MEDIA_ROOT=media_dir))
        self.user = get_user_model().objects.create_user(username="quota", password="test-pass")
        self.project = Project.objects.create(name="Demo", created_by=self.user)
        self.task = Task.objects.create(project=self.project, title="Entrega", created_by=self.user)
        self.client.force_authenticate(self.user)
        self.url = f"/api/projects/{self.project.id}/tasks/{self.task.id}/attachments/"

    def upload(self, size):
        return self.client.post(self.url, {"file": SimpleUploadedFile("dato.txt", b"x" * size)})

    @override_settings(PIZAPP_MAX_UPLOAD_BYTES=4)
    def test_file_limit_rejects_without_creating_attachment(self):
        self.assertEqual(self.upload(5).status_code, 400)
        self.assertEqual(Attachment.objects.count(), 0)

    @override_settings(PIZAPP_PROJECT_STORAGE_BYTES=8)
    def test_project_limit_counts_existing_files(self):
        self.assertEqual(self.upload(4).status_code, 201)
        self.assertEqual(self.upload(5).status_code, 400)
        self.assertEqual(Attachment.objects.count(), 1)

    @override_settings(PIZAPP_TOTAL_STORAGE_BYTES=8)
    def test_demo_limit_counts_files_from_other_projects(self):
        other = Project.objects.create(name="Otro", created_by=self.user)
        task = Task.objects.create(project=other, title="Otra entrega", created_by=self.user)
        Attachment.objects.create(task=task, uploaded_by=self.user, original_name="otro.txt",
                                  file=SimpleUploadedFile("otro.txt", b"xxxx"), size_bytes=4)
        self.assertEqual(self.upload(4).status_code, 201)
        self.assertEqual(self.upload(1).status_code, 400)
        self.assertEqual(Attachment.objects.count(), 2)
