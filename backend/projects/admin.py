from django.contrib import admin

from .models import Attachment, Project, Task

admin.site.register(Project)
admin.site.register(Task)
admin.site.register(Attachment)