from django.test import SimpleTestCase


class DeploymentRoutesTests(SimpleTestCase):
    def test_home_redirect_keeps_invitation(self):
        response = self.client.get("/?invite=abc-123")
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], "/app/index.html?invite=abc-123")

    def test_health_does_not_expose_configuration(self):
        response = self.client.get("/api/health/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})
