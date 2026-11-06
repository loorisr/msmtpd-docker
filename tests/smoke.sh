#!/bin/bash
# The literal $, backticks and backslashes in test data are intentional.
# shellcheck disable=SC1003,SC2016
# Runtime tests against a built image: tests/smoke.sh IMAGE
# Uses a fake upstream SMTP server; everything stays on 127.0.0.1.
set -u

IMAGE="${1:?usage: smoke.sh IMAGE}"
DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
CONTAINER="msmtpd-smoke-$$"
UPSTREAM_PORT=12525
PORT=12500
UPSTREAM_LOG="$WORK/upstream.log"
HARDENED=(--read-only --tmpfs /tmp --cap-drop ALL --network host --no-healthcheck)
LISTEN=(msmtpd --interface=127.0.0.1 "--port=$PORT" "--command=/usr/bin/msmtp -C /tmp/msmtprc -f %F --")
UPSTREAM=(-e SMTP_HOST=127.0.0.1 -e "SMTP_PORT=$UPSTREAM_PORT")
failures=0

: > "$UPSTREAM_LOG"
python3 -I "$DIR/fake_smtp.py" "$UPSTREAM_PORT" >> "$UPSTREAM_LOG" 2>&1 &
UPSTREAM_PID=$!

cleanup() {
  kill "$UPSTREAM_PID" 2>/dev/null
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  chmod -R u+rwX "$WORK" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

check() { # description, expected, actual
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]"
    failures=$((failures + 1))
  fi
}

start() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  docker run -d --name "$CONTAINER" "${HARDENED[@]}" "$@" "$IMAGE" "${LISTEN[@]}" >/dev/null
  for _ in $(seq 1 50); do
    python3 -I -c "import socket;socket.create_connection(('127.0.0.1',$PORT),1)" 2>/dev/null && return
    sleep 0.1
  done
  echo "FAIL - container did not start listening"
  docker logs "$CONTAINER"
  failures=$((failures + 1))
}

send() { # mail_from, rcpt: prints the reply code and leaves the upstream log ready to read
  : > "$UPSTREAM_LOG"
  python3 -I "$DIR/smtp_client.py" "$PORT" "$1" "$2"
  sleep 0.3
}

setting() { docker exec "$CONTAINER" msmtp -C /tmp/msmtprc -P 2>&1 | sed -n "s/^$1 = //p"; }
exits_nonzero() { if docker run --rm "$@" >/dev/null 2>&1; then echo no; else echo yes; fi; }

echo "# delivery with the hardened flags and the image's default user"
start "${UPSTREAM[@]}"
check "mail is accepted" 250 "$(send sender@client.example rcpt@x.example)"
check "envelope sender reaches upstream" "CMD|MAIL FROM:<sender@client.example>" "$(grep -a 'MAIL FROM' "$UPSTREAM_LOG")"
check "Bcc header is removed" 0 "$(grep -ac 'DATA|Bcc' "$UPSTREAM_LOG")"
check "runs as non-root" 1000 "$(docker exec "$CONTAINER" id -u)"
check "config is private" "-rw-------" "$(docker exec "$CONTAINER" ls -l /tmp/msmtprc | cut -d' ' -f1)"

echo "# defaults documented in the README"
check "default port" 587 "$(docker run --rm --entrypoint sh -e SMTP_HOST=x "$IMAGE" -c '/usr/local/bin/entrypoint.sh msmtp -C /tmp/msmtprc -P 2>&1' | sed -n 's/^port = //p')"
for expected in "tls off" "tls_starttls on" "tls_certcheck on" "auth none" "domain localhost" \
  "allow_from_override on" "set_from_header auto" "set_date_header auto" "remove_bcc_headers on"; do
  check "default ${expected% *}" "${expected#* }" "$(setting "${expected% *}")"
done

echo "# every option is accepted by msmtp"
start "${UPSTREAM[@]}" -e SMTP_TLS=off -e SMTP_STARTTLS=off -e SMTP_TLS_CHECKCERT=off -e SMTP_AUTH=plain \
  -e SMTP_USER=u -e SMTP_PASSWORD=p -e SMTP_DOMAIN=d.example -e SMTP_FROM=f@x.example \
  -e SMTP_ALLOW_FROM_OVERRIDE=off -e SMTP_SET_FROM_HEADER=on -e SMTP_SET_DATE_HEADER=off \
  -e SMTP_REMOVE_BCC_HEADERS=off -e SMTP_UNDISCLOSED_RECIPIENTS=on -e SMTP_DSN_NOTIFY=never -e SMTP_DSN_RETURN=headers
check "mail is accepted" 250 "$(send sender@client.example rcpt@x.example)"
check "domain is applied" "CMD|EHLO d.example" "$(grep -a EHLO "$UPSTREAM_LOG")"
check "recipients are hidden" "DATA|To: undisclosed-recipients:;" "$(grep -a 'DATA|To' "$UPSTREAM_LOG")"
check "DSN options are sent" "CMD|RCPT TO:<rcpt@x.example> NOTIFY=NEVER" "$(grep -a 'RCPT TO' "$UPSTREAM_LOG")"
start "${UPSTREAM[@]}" -e SMTP_REMOVE_BCC_HEADERS=off
send sender@client.example rcpt@x.example >/dev/null
check "Bcc is kept when asked" 1 "$(grep -ac 'DATA|Bcc' "$UPSTREAM_LOG")"
start "${UPSTREAM[@]}" -e SMTP_TLS=on -e SMTP_STARTTLS=off -e SMTP_TLS_CHECKCERT=off
check "SMTP_TLS is applied" on "$(setting tls)"
check "SMTP_STARTTLS is applied" off "$(setting tls_starttls)"
check "SMTP_TLS_CHECKCERT is applied" off "$(setting tls_certcheck)"

echo "# sender control"
start "${UPSTREAM[@]}" -e SMTP_FROM=real@corp.example -e SMTP_ALLOW_FROM_OVERRIDE=off -e SMTP_SET_FROM_HEADER=on
send sender@client.example rcpt@x.example >/dev/null
check "envelope sender is forced" "CMD|MAIL FROM:<real@corp.example>" "$(grep -a 'MAIL FROM' "$UPSTREAM_LOG")"
check "From header is forced" "DATA|From: real@corp.example" "$(grep -a 'DATA|From' "$UPSTREAM_LOG")"

echo "# passwords reach upstream unchanged"
for password in 'simple' 'with space' 'has#hash' '#start' 'qu"ote' '"start' 'end"' 'back\slash' 'end\' \
  ' leading' 'trailing ' '"wrapped"' "sq'uote" '$HOME`x`' 'a"b c'; do
  start "${UPSTREAM[@]}" -e SMTP_AUTH=plain -e SMTP_USER=u -e "SMTP_PASSWORD=$password" -e SMTP_FROM=f@x.example
  send a@x.example r@x.example >/dev/null
  check "password [$password]" "PASSWORD|[$password]" "$(grep -a 'PASSWORD|' "$UPSTREAM_LOG")"
done

echo "# _FILE variables"
printf 'file-from@x.example\n' > "$WORK/from"
printf '%s' "$UPSTREAM_PORT" > "$WORK/port"
printf 'multi\nline\n' > "$WORK/multiline"
printf 'crlf\r\n' > "$WORK/crlf"
chmod 644 "$WORK"/*
chmod 755 "$WORK"
start -e SMTP_HOST=127.0.0.1 -v "$WORK/from:/s/from:ro" -v "$WORK/port:/s/port:ro" \
  -e SMTP_FROM_FILE=/s/from -e SMTP_PORT_FILE=/s/port
check "SMTP_FROM_FILE" "file-from@x.example" "$(setting from)"
check "SMTP_PORT_FILE does not conflict with the default port" "$UPSTREAM_PORT" "$(setting port)"

echo "# invalid configuration is refused"
check "missing SMTP_HOST" yes "$(exits_nonzero "$IMAGE" true)"
check "variable and _FILE both set" yes "$(exits_nonzero -v "$WORK/from:/s/from:ro" -e SMTP_HOST=x -e SMTP_FROM=a -e SMTP_FROM_FILE=/s/from "$IMAGE" true)"
check "missing _FILE target" yes "$(exits_nonzero -e SMTP_HOST=x -e SMTP_PASSWORD_FILE=/nope "$IMAGE" true)"
check "line break in a variable" yes "$(exits_nonzero -e SMTP_HOST=x -e "SMTP_DOMAIN=$(printf 'a\npasswordeval touch /tmp/x')" "$IMAGE" true)"
check "line break in a _FILE" yes "$(exits_nonzero -v "$WORK/multiline:/s/f:ro" -e SMTP_HOST=x -e SMTP_PASSWORD_FILE=/s/f "$IMAGE" true)"
check "CRLF in a _FILE" yes "$(exits_nonzero -v "$WORK/crlf:/s/f:ro" -e SMTP_HOST=x -e SMTP_PASSWORD_FILE=/s/f "$IMAGE" true)"

echo "# secrets"
printf 'S3CRET-FILE' > "$WORK/password"
chmod 644 "$WORK/password"
start --init "${UPSTREAM[@]}" -v "$WORK/password:/s/password:ro" -e SMTP_PASSWORD_FILE=/s/password
check "_FILE secret is absent from the container config" 0 "$(docker inspect "$CONTAINER" --format '{{json .Config.Env}}' | grep -c S3CRET-FILE)"
check "_FILE secret is absent from PID 1" 0 "$(docker exec "$CONTAINER" sh -c 'tr "\0" "\n" < /proc/1/environ' | grep -c S3CRET-FILE)"
check "_FILE secret is absent from msmtpd" 0 "$(docker exec "$CONTAINER" sh -c 'tr "\0" "\n" < /proc/$(pidof msmtpd | cut -d" " -f1)/environ' | grep -c S3CRET-FILE)"
check "msmtpd keeps no SMTP_ variable" 0 "$(docker exec "$CONTAINER" sh -c 'tr "\0" "\n" < /proc/$(pidof msmtpd | cut -d" " -f1)/environ' | grep -c '^SMTP_')"

echo "# hostile addresses are rejected"
start "${UPSTREAM[@]}"
check "shell syntax in MAIL FROM" 501 "$(send 'a$(touch${IFS}/tmp/pwned)@x.example' r@x.example)"
check "shell syntax in RCPT TO" 501 "$(send a@x.example 'b;touch${IFS}/tmp/pwned;@x.example')"
check "option injection in RCPT TO" 501 "$(send a@x.example '--host=evil.example')"
check "nothing was executed" 0 "$(docker exec "$CONTAINER" sh -c 'ls /tmp | grep -c pwned')"

echo "# upstream failure is reported to the client"
start -e SMTP_HOST=127.0.0.1 -e SMTP_PORT=1
check "temporary failure" 451 "$(send a@x.example r@x.example)"

echo "# image defaults: command, entrypoint, healthcheck"
docker rm -f "$CONTAINER" >/dev/null 2>&1
docker run -d --name "$CONTAINER" --read-only --tmpfs /tmp --cap-drop ALL --health-interval=1s --health-start-period=0s \
  -e SMTP_HOST=127.0.0.1 "$IMAGE" >/dev/null
status=starting
for _ in $(seq 1 15); do
  status="$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}')"
  [ "$status" = healthy ] && break
  sleep 1
done
check "healthcheck turns healthy" healthy "$status"
docker rm -f "$CONTAINER" >/dev/null 2>&1
docker run -d --name "$CONTAINER" --read-only --tmpfs /tmp --cap-drop ALL --health-interval=1s --health-retries=2 \
  --health-start-period=0s --entrypoint sh "$IMAGE" -c 'sleep 60' >/dev/null
status=starting
for _ in $(seq 1 15); do
  status="$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}')"
  [ "$status" = unhealthy ] && break
  sleep 1
done
check "healthcheck detects a closed port" unhealthy "$status"

echo
if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
