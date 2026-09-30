from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("projects", "0005_task_due_date"),
    ]

    operations = [
        migrations.CreateModel(
            name="Milestone",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("name", models.CharField(max_length=160)),
                ("due_date", models.DateField(blank=True, null=True)),
                ("is_closed", models.BooleanField(default=False)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("created_by", models.ForeignKey(
                    on_delete=django.db.models.deletion.PROTECT,
                    related_name="created_milestones", to=settings.AUTH_USER_MODEL,
                )),
                ("project", models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name="milestones", to="projects.project",
                )),
            ],
        ),
        migrations.AddField(
            model_name="task",
            name="milestone",
            field=models.ForeignKey(
                blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL,
                related_name="tasks", to="projects.milestone",
            ),
        ),
    ]
