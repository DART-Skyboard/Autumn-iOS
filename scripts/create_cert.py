#!/usr/bin/env python3
import jwt, time, json, urllib.request, base64, ssl, os, sys

key_id = "P6Z72KS63T"
issuer_id = os.environ["ASC_ISSUER_ID"]
key_path = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_P6Z72KS63T.p8")

with open(key_path) as f:
    private_key = f.read()

payload = {
    "iss": issuer_id,
    "iat": int(time.time()),
    "exp": int(time.time()) + 1200,
    "aud": "appstoreconnect-v1"
}
token = jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})

with open("/tmp/dist_csr.pem") as f:
    csr_content = f.read()

ctx = ssl.create_default_context()
body = json.dumps({
    "data": {
        "type": "certificates",
        "attributes": {
            "certificateType": "IOS_DISTRIBUTION",
            "csrContent": csr_content
        }
    }
}).encode()

req = urllib.request.Request(
    "https://api.appstoreconnect.apple.com/v1/certificates",
    body,
    {"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    method="POST"
)
try:
    with urllib.request.urlopen(req, context=ctx) as r:
        result = json.loads(r.read())
    cert_content = result["data"]["attributes"]["certificateContent"]
    cert_bytes = base64.b64decode(cert_content)
    with open("/tmp/dist_cert.der", "wb") as f:
        f.write(cert_bytes)
    print(f"Certificate created: {result['data']['id']}")
except urllib.error.HTTPError as e:
    body = e.read().decode()
    print(f"Error {e.code}: {body}", file=sys.stderr)
    # If cert limit reached, list existing certs
    if e.code == 409 or "CERTIFICATE_LIMIT_REACHED" in body:
        print("Certificate limit reached - listing existing certs")
        list_req = urllib.request.Request(
            "https://api.appstoreconnect.apple.com/v1/certificates?filter[certificateType]=IOS_DISTRIBUTION",
            headers={"Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(list_req, context=ctx) as r:
            certs = json.loads(r.read())
        print(json.dumps(certs, indent=2))
    sys.exit(1)
