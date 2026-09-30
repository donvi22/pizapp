from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("projects", "0004_task_assignments"),
    ]

    operations = [
        migrations.AddField(
            model_name="task",
            name="due_date",
            field=models.DateField(blank=True, null=True),
        ),
    ]
