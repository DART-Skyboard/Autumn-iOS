#!/usr/bin/env python3
import sys, time, json, urllib.request, urllib.error, base64, ssl, os

# Pure python JWT for ES256 - avoids needing cryptography package
# We use the p8 key directly with PyJWT which handles EC keys natively
try:
    import jwt
except ImportError:
    print("PyJWT not found", file=sys.stderr)
    sys.exit(1)

key_id    = "P6Z72KS63T"
issuer_id = os.environ["ASC_ISSUER_ID"]
key_path  = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_P6Z72KS63T.p8")

with open(key_path) as f:
    private_key = f.read()

payload = {
    "iss": issuer_id,
    "iat": int(time.time()),
    "exp": int(time.time()) + 1200,
    "aud": "appstoreconnect-v1"
}
token = jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})
if isinstance(token, bytes):
    token = token.decode()

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
    cert_bytes   = base64.b64decode(cert_content)
    with open("/tmp/dist_cert.der", "wb") as f:
        f.write(cert_bytes)
    print(f"Certificate created: {result['data']['id']}")
except urllib.error.HTTPError as e:
    err_body = e.read().decode()
    print(f"HTTP {e.code}: {err_body}", file=sys.stderr)
    sys.exit(1)
