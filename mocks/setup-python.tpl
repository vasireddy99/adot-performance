import json
import glob
import requests

MOCK_PATH = 'mock.json'
WIREMOCK_ADMIN_URL = 'http://localhost:8080/__admin/mappings'
FILES = glob.glob(MOCK_PATH)

for name in FILES:

    print("Provisioning mock mapping with the file:", name)
    with open(name) as json_file:
        payload = json.load(json_file)

    response = requests.post(WIREMOCK_ADMIN_URL, data=json.dumps(payload))
    print("Status:", response.status_code, response.reason)