# Local Foundation Setup

## Prerequisites

Install Docker Desktop, Homebrew, `mise`, `mkcert`, and Make. Docker Desktop must be running.

```bash
brew install mise mkcert
mise install
make bootstrap
```

`mkcert -install` adds the local development CA to the macOS trust store and may prompt for the macOS administrator password. Run it interactively; never provide that password to a script.

## Configure the environment

Create an ignored local environment file and replace both `change-me` passwords:

```bash
cp .env.example .env
```

For iOS Simulator, set `COMMERCE_HOST=localhost`. The application base URL is `https://localhost:8443`.

For a physical iPhone, use the Mac's Bonjour hostname so the client sends TLS SNI and the device can resolve the Mac on the LAN:

```bash
scutil --get LocalHostName
```

If the command returns `My-Mac`, set `COMMERCE_HOST=My-Mac.local` in `.env`. The application base URL is `https://My-Mac.local:8443`. Keep the iPhone and Mac on the same Wi-Fi network and disable client isolation on the access point. A literal IP address is not the preferred TLS endpoint because IP-based TLS clients may not send SNI.

## Create certificates and start services

```bash
mkcert -install
make certs
make infra-up
make smoke
```

The expected final smoke output is:

```text
foundation smoke passed
```

Inspect failures with `make infra-logs`. Stop services without deleting named data volumes with:

```bash
make infra-down
```

## Trust the CA on iOS Simulator

1. Print the CA directory with `mkcert -CAROOT`.
2. Drag `rootCA.pem` from that directory onto the booted Simulator.
3. In Simulator Settings, open **General → About → Certificate Trust Settings**.
4. Enable full trust for the mkcert development CA.

Only the CA certificate is transferred. Never install or copy `Infrastructure/certs/commerce.local-key.pem` outside the Mac development environment.

## Trust the CA on a physical iPhone

1. Transfer only `rootCA.pem` from the directory printed by `mkcert -CAROOT` to the iPhone.
2. Install the downloaded profile under **Settings → General → VPN & Device Management**.
3. Enable full trust under **Settings → General → About → Certificate Trust Settings**.
4. Open `https://<Mac-LocalHostName>.local:8443/healthz` from Safari to verify LAN routing and trust.

Delete the development CA profile when the device no longer needs local testing. Never transfer the CA private key (`rootCA-key.pem`) or the server private key.

## Security boundaries

- `.env`, generated certificates, private keys, and infrastructure data are ignored by Git.
- Caddy is the only service that publishes an application port to the host.
- PostgreSQL, Redis, Kafka, and the API remain on the internal Docker network.
- Do not use `curl -k`, disable ATS, or add arbitrary-load exceptions to bypass trust failures.
