from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase


class RegistrationTests(APITestCase):
    def test_register_returns_usable_token(self):
        response = self.client.post('/api/register/', {
            'username': 'ana', 'email': 'ana@example.com',
            'password': 'Seguro-123-ABC',
        }, format='json')
        self.assertEqual(response.status_code, 201)
        self.assertTrue(response.data['token'])
        self.assertTrue(get_user_model().objects.get(username='ana').check_password('Seguro-123-ABC'))
        self.assertEqual(self.client.post('/api/register/', {
            'username': 'ana', 'email': 'otro@example.com',
            'password': 'Seguro-123-ABC',
        }, format='json').status_code, 400)
