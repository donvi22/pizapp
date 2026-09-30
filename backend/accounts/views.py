from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .serializers import RegistrationSerializer


class RegisterView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RegistrationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            with transaction.atomic():
                user = serializer.save()
                token, _ = Token.objects.get_or_create(user=user)
        except IntegrityError:
            raise ValidationError("El usuario o el correo ya está registrado.")
        return Response({"token": token.key}, status=status.HTTP_201_CREATED)
