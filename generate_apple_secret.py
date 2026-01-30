#!/usr/bin/env python3
"""
Generate Apple Sign-In secret for Supabase
"""
import jwt
import time

# Your Apple Developer credentials
TEAM_ID = "MJSVJG4DXR"  # From Apple Developer account (top right corner)
KEY_ID = "P663WA8X5Y"   # Your Key ID
CLIENT_ID = "com.ironforge.app.auth"  # Your Service ID

# Read the private key
with open("AuthKey_P663WA8X5Y.p8", "r") as f:
    private_key = f.read()

# Generate the JWT
now = int(time.time())
payload = {
    "iss": TEAM_ID,
    "iat": now,
    "exp": now + (86400 * 180),  # 180 days (max allowed by Apple)
    "aud": "https://appleid.apple.com",
    "sub": CLIENT_ID
}

secret = jwt.encode(
    payload,
    private_key,
    algorithm="ES256",
    headers={"kid": KEY_ID}
)

print("=" * 60)
print("YOUR APPLE SECRET FOR SUPABASE:")
print("=" * 60)
print(secret)
print("=" * 60)
print("\nCopy the string above and paste it into Supabase's 'Secret Key' field")
