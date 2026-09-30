from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("projects", "0003_project_members"),
    ]

    operations = [
        migrations.CreateModel(
            name="TaskAssignment",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("status", models.CharField(
                    choices=[
                        ("pending", "Pendiente"),
                        ("inProgress", "En curso"),
                        ("completed", "Completada"),
                    ], default="pending", max_length=12,
                )),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("task", models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name="assignments", to="projects.task",
                )),
                ("user", models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name="task_assignments", to=settings.AUTH_USER_MODEL,
                )),
            ],
        ),
        migrations.AddConstraint(
            model_name="taskassignment",
            constraint=models.UniqueConstraint(
                fields=("task", "user"), name="unique_task_assignment_user",
            ),
        ),
    ]
