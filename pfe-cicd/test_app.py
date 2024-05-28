import unittest
from app import app

class FlaskTestCase(unittest.TestCase):

    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True

    def test_random_dog(self):
        response = self.app.get('/random-pets')
        self.assertEqual(response.status_code, 200)
        self.assertIn('breed', response.json)

if __name__ == '__main__':
    unittest.main()
