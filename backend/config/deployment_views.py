from urllib.parse import urlencode

from django.http import HttpResponseRedirect, JsonResponse


def open_app(request):
    # Al seguir la invitación desde la raíz se conserva su código.
    target = "/app/index.html"
    invite = request.GET.get("invite")
    if invite:
        target += "?" + urlencode({"invite": invite})
    return HttpResponseRedirect(target)


def health(request):
    return JsonResponse({"status": "ok"})
