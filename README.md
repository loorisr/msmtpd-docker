# msmtpd-docker

Docker image for running an [msmtp](https://marlam.de/msmtp/) SMTP relay daemon. It accepts email submissions on port 2500 and relays them to a configurable upstream SMTP server (e.g., Gmail, SendGrid, Mailgun, or a self-hosted server).

## Quick start

```yaml
# docker-compose.yml
services:
  mail:
    image: ghcr.io/loorisr/msmtpd-docker:latest
    container_name: mail_relay
    restart: always
    ports:
      - "2500:2500"
    environment:
      - SMTP_HOST=smtp.gmail.com
      - SMTP_PORT=587
      - SMTP_AUTH=on
      - SMTP_TLS=on
      - SMTP_STARTTLS=on
      - SMTP_TLS_CHECKCERT=on
      - SMTP_USER=your-email@gmail.com
      - SMTP_PASSWORD=your-app-password
      - SMTP_FROM=your-email@gmail.com
      - SMTP_DOMAIN=gmail.com
```

Applications inside the same Docker network can then send email via `mail_relay:2500` without needing their own SMTP credentials.

## Environment variables

### Required

| Variable       | Description                    |
| -------------- | ------------------------------ |
| `SMTP_HOST`   | Upstream SMTP server hostname  |

### SMTP configuration

| Variable                    | Default | Values      | Description                                        |
| --------------------------- | ------- | ----------- | -------------------------------------------------- |
| `SMTP_PORT`                | `587`   |             | Upstream SMTP server port                          |
| `SMTP_AUTH`                |         | `on` / `off` | Enable SMTP authentication                         |
| `SMTP_TLS`                 |         | `on` / `off` | Use TLS                                            |
| `SMTP_STARTTLS`            |         | `on` / `off` | Use STARTTLS (upgrade plain connection to TLS)    |
| `SMTP_TLS_CHECKCERT`      |         | `on` / `off` | Verify the TLS certificate                         |
| `SMTP_USER`                |         |             | SMTP authentication username                       |
| `SMTP_PASSWORD`            |         |             | SMTP authentication password                       |
| `SMTP_DOMAIN`              |         |             | Domain for EHLO command                            |
| `SMTP_FROM`                |         |             | Default envelope-from address                      |
| `SMTP_ALLOW_FROM_OVERRIDE` |         | `on` / `off` | Allow submitted messages to override the from address |
| `SMTP_SET_FROM_HEADER`    |         | `auto` / `on` / `off` | Add/override the From header                |
| `SMTP_SET_DATE_HEADER`    |         | `auto` / `on` / `off` | Add/override the Date header                |
| `SMTP_REMOVE_BCC_HEADERS` |         | `on` / `off` | Remove Bcc headers before sending                  |
| `SMTP_UNDISCLOSED_RECIPIENTS` |     | `on` / `off` | Replace To/Cc/Bcc with "undisclosed-recipients"   |
| `SMTP_DSN_NOTIFY`          |         |             | DSN notification conditions                        |
| `SMTP_DSN_RETURN`          |         |             | DSN return amount                                  |

### Other

| Variable | Default | Description                            |
| -------- | ------- | -------------------------------------- |
| `TZ`    | `UTC`   | Container timezone (e.g. `Europe/Rome`) |

## Docker Secrets

All environment variables support the `_FILE` suffix convention for Docker Secrets. When both the variable and its `_FILE` counterpart are set, the entrypoint exits with an error to prevent ambiguity.

```yaml
services:
  mail:
    image: ghcr.io/loorisr/msmtpd-docker:latest
    secrets:
      - smtp_user
      - smtp_password
    environment:
      - SMTP_HOST=smtp.gmail.com
      - SMTP_USER_FILE=/run/secrets/smtp_user
      - SMTP_PASSWORD_FILE=/run/secrets/smtp_password

secrets:
  smtp_user:
    file: ./secrets/smtp_user.txt
  smtp_password:
    file: ./secrets/smtp_password.txt
```

## Healthcheck

```yaml
healthcheck:
  test: ["CMD", "nc", "-z", "localhost", "2500"]
  interval: 30s
  timeout: 10s
  retries: 3
```

The container exposes a TCP healthcheck on port 2500. Ensure `netcat-openbsd` or equivalent is installed if adding a healthcheck to your compose file.

## Running as non-root

The container is designed to run as an unprivileged user. Override the UID/GID in your compose file:

```yaml
services:
  mail:
    image: ghcr.io/loorisr/msmtpd-docker:latest
    user: "1000:1000"
```

The configuration is written to `/tmp/msmtprc` with mode `0600`. The `--command` in the Docker CMD includes `-C /tmp/msmtprc` to ensure `msmtp` finds it regardless of environment inheritance.

## Security

- No root privileges required at runtime — drop privileges via `user:` in compose.
- Sensitive environment variables (`SMTP_USER`, `SMTP_PASSWORD`) are unset after the config file is generated.
- Plaintext SMTP credentials are stored only in `/tmp/msmtprc` inside the container (chmod 600), never in process command lines.
- Use Docker Secrets (`_FILE` convention) for credential injection in production.

## Build

```sh
docker build -t msmtpd .
```

## License

AGPL-3.0 — see [LICENSE](LICENSE).
