# Temporal Cloud Certificates

Certificates for mTLS authentication with Temporal Cloud. Not needed for local development.

## Generate Certificates

```bash
# CA certificate
echo "y" | tcld gen ca --org temporal --validity-period 1y \
  --ca-cert certs/ca.pem --ca-key certs/ca.key

# Client certificate
echo "y" | tcld gen leaf --org temporal --validity-period 364d \
  --ca-cert certs/ca.pem --ca-key certs/ca.key \
  --cert certs/client.pem --key certs/client.key
```

## Upload to Temporal Cloud

1. Go to https://cloud.temporal.io
2. Navigate to your namespace → Settings → Certificates
3. Upload `ca.pem` contents

## Configure

Update `.env`:
```env
TEMPORAL_HOST=your-namespace.tmprl.cloud
TEMPORAL_NAMESPACE=your-namespace
TEMPORAL_TLS_ENABLED=true
TEMPORAL_CLIENT_CERT=certs/client.pem
TEMPORAL_CLIENT_KEY=certs/client.key
```

## Notes

- Certificate files are in `.gitignore`
- Never commit or share private keys (`*.key`)
- Certificates expire after 1 year
