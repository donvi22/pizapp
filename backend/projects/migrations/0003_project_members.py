from uuid import uuid4

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import projects.models


def give_codes_to_existing_projects(apps, schema_editor):
    Project = apps.get_model("projects", "Project")
    for project in Project.objects.using(schema_editor.connection.alias).all():
        project.invite_code = uuid4().hex
        project.save(update_fields=["invite_code"])


class Migration(migrations.Migration):
    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("projects", "0002_task_canvas_data"),
    ]

    operations = [
        migrations.AddField(
            model_name="project",
            name="invite_code",
            field=models.CharField(max_length=32, null=True, unique=True, editable=False),
        ),
        migrations.RunPython(give_codes_to_existing_projects, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="project",
            name="invite_code",
            field=models.CharField(
                max_length=32, unique=True, default=projects.models.new_invite_code,
                editable=False,
            ),
        ),
        migrations.CreateModel(
            name="ProjectMember",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("display_name", models.CharField(max_length=80)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("joined_at", models.DateTimeField(null=True, blank=True)),
                ("project", models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name="members", to="projects.project",
                )),
                ("user", models.ForeignKey(
                    blank=True, null=True, on_delete=django.db.models.deletion.CASCADE,
                    related_name="project_memberships", to=settings.AUTH_USER_MODEL,
                )),
            ],
        ),
        migrations.AddConstraint(
            model_name="projectmember",
            constraint=models.UniqueConstraint(
                fields=("project", "user"), name="unique_project_member_user",
            ),
        ),
    ]
