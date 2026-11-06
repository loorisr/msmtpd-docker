# msmtpd-docker

Docker image for running an [msmtp](https://marlam.de/msmtp/) SMTP relay daemon. It accepts email submissions on port 2500 and relays them to a configurable upstream SMTP server. It is very lightweight (about 10 MB to download, 35 MB on disk) and available for `linux/amd64` and `linux/arm64`.

It is inspired by https://github.com/crazy-max/docker-msmtpd, but runs as non-root by default and can run read-only. Each build is scanned with [Trivy](https://trivy.dev/) and is not published if a fixable high or critical vulnerability is found.

## Quick start

Store the password in a file readable by UID 1000, the user the image runs as:

```sh
mkdir -p secrets
printf '%s' 'your-app-password' > secrets/smtp_password.txt
chmod 600 secrets/smtp_password.txt
sudo chown 1000:1000 secrets/smtp_password.txt
```

```yaml
# docker-compose.yml
services:
  msmtpd:
    image: ghcr.io/loorisr/msmtpd-docker:latest
    container_name: msmtpd
    init: true
    restart: always
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
    - ALL
    ports:
      - "2500:2500"
    secrets:
      - smtp_password
    environment:
      - SMTP_HOST=smtp.gmail.com
      - SMTP_PORT=587
      - SMTP_AUTH=on
      - SMTP_TLS=on
      - SMTP_STARTTLS=on
      - SMTP_TLS_CHECKCERT=on
      - SMTP_USER=your-email@gmail.com
      - SMTP_PASSWORD_FILE=/run/secrets/smtp_password
      - SMTP_FROM=your-email@gmail.com
      - SMTP_DOMAIN=gmail.com

secrets:
  smtp_password:
    file: ./secrets/smtp_password.txt
```

Applications inside the same Docker network can then send email via `msmtpd:2500` without needing their own SMTP credentials.

With a plain `docker run`, add `--init`: without it, `msmtpd` ignores `SIGTERM` and `docker stop` has to kill it after 10 seconds.

## Image tags

| Tag | Content |
| --- | ------- |
| `latest`, `main` | Latest build of the `main` branch, rebuilt weekly with the latest Alpine packages |
| `YYYYMMDD` | Weekly build of that date; never overwritten |
| `X.Y.Z` | Latest build with that msmtpd version (e.g. `1.8.32`); still rebuilt weekly while Alpine ships it |
| `X.Y` | Latest build with that msmtpd minor version (e.g. `1.8`) |
| `vX.Y.Z` | Build of that git tag of this repository |
| `<commit sha>` | Latest build of that commit; overwritten by the weekly rebuild |

## Delivery failures

The relay has no queue. If the upstream server cannot be reached, the client gets a `451` temporary error and must retry, otherwise the mail is lost.

The image's healthcheck only verifies that port 2500 is open, so the container stays `healthy` while the upstream server is down. Failures appear in the container logs.

## Environment variables

### Required

| Variable       | Description                    |
| -------------- | ------------------------------ |
| `SMTP_HOST`   | Upstream SMTP server hostname  |

### SMTP configuration

| Variable                    | Default | Values      | Description                                        |
| --------------------------- | ------- | ----------- | -------------------------------------------------- |
| `SMTP_PORT`                | `587`   |             | Upstream SMTP server port                          |
| `SMTP_AUTH`                | `off`   | `on` / `off` / method | Enable SMTP authentication, optionally forcing a method such as `plain` |
| `SMTP_TLS`                 | `off`   | `on` / `off` | Use TLS                                            |
| `SMTP_STARTTLS`            | `on`    | `on` / `off` | With TLS, use STARTTLS (`on`) or connect directly in TLS (`off`, usually port 465) |
| `SMTP_TLS_CHECKCERT`      | `on`    | `on` / `off` | Verify the TLS certificate                         |
| `SMTP_USER`                |         |             | SMTP authentication username (required if `SMTP_AUTH=on`) |
| `SMTP_PASSWORD`            |         |             | SMTP authentication password (required if `SMTP_AUTH=on`) |
| `SMTP_DOMAIN`              | `localhost` |         | Domain for EHLO command                            |
| `SMTP_FROM`                |         |             | Envelope-from address, used when the client's cannot be used (see below) |
| `SMTP_ALLOW_FROM_OVERRIDE` | `on`    | `on` / `off` | Let the client choose the envelope-from address (see below) |
| `SMTP_SET_FROM_HEADER`    | `auto`  | `auto` / `on` / `off` | Add/override the From header (see below)    |
| `SMTP_SET_DATE_HEADER`    | `auto`  | `auto` / `on` / `off` | Add/override the Date header                |
| `SMTP_REMOVE_BCC_HEADERS` | `on`    | `on` / `off` | Remove Bcc headers before sending                  |
| `SMTP_UNDISCLOSED_RECIPIENTS` | `off` | `on` / `off` | Replace To/Cc/Bcc with "undisclosed-recipients"   |
| `SMTP_DSN_NOTIFY`          |         | `never` or a list of `failure`, `delay`, `success` | DSN notification conditions (not used if not set). The upstream server must support DSN, otherwise mails are refused |
| `SMTP_DSN_RETURN`          |         | `headers` / `full` | DSN return amount (not used if not set). The upstream server must support DSN, otherwise mails are refused |

Values cannot contain line breaks, and the container refuses to start if one does.

### Forcing the sender

By default, clients choose their sender freely: `SMTP_FROM` alone does not restrict it. To force it, set all three variables:

```yaml
- SMTP_FROM=your-email@gmail.com
- SMTP_ALLOW_FROM_OVERRIDE=off  # forces the envelope sender
- SMTP_SET_FROM_HEADER=on       # forces the From header
```

### Other

| Variable | Default | Description                            |
| -------- | ------- | -------------------------------------- |
| `TZ`    | `UTC`   | Container timezone (e.g. `Europe/Rome`) |

## Docker Secrets

All `SMTP_*` variables support the `_FILE` suffix convention for Docker Secrets. When both the variable and its `_FILE` counterpart are set, the entrypoint exits with an error to prevent ambiguity.

Secret files must be readable by the container's user (UID 1000 by default).

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

## Security

- Runs as non-root (UID 1000) by default; use `user:` in compose to choose another UID. `/tmp` must be writable by that user.
- Can run read-only, with a tmpfs on `/tmp`.
- `SMTP_*` variables are removed from the environment of `msmtpd` once the config file is generated. **A secret passed directly as a variable remains readable** in `docker inspect`, in `docker exec` sessions and, with `init: true`, in `/proc/1/environ`. Use the `_FILE` convention to avoid this.
- Plaintext SMTP credentials are stored only in `/tmp/msmtprc` inside the container (chmod 600), never in process command lines.

## License

AGPL-3.0 — see [LICENSE](LICENSE).
