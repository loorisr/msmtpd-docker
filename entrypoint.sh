#!/bin/sh
set -e

CONFIG_FILE="/tmp/msmtprc"

# The config holds credentials: it must never exist with wider permissions.
umask 077

NEWLINE='
'
CARRIAGE_RETURN="$(printf '\r')"

# Each entry is VARIABLE:msmtp_directive. SMTP_HOST and SMTP_PORT are handled apart.
OPTIONS="
SMTP_TLS:tls
SMTP_STARTTLS:tls_starttls
SMTP_TLS_CHECKCERT:tls_certcheck
SMTP_AUTH:auth
SMTP_USER:user
SMTP_PASSWORD:password
SMTP_DOMAIN:domain
SMTP_FROM:from
SMTP_ALLOW_FROM_OVERRIDE:allow_from_override
SMTP_SET_FROM_HEADER:set_from_header
SMTP_SET_DATE_HEADER:set_date_header
SMTP_REMOVE_BCC_HEADERS:remove_bcc_headers
SMTP_UNDISCLOSED_RECIPIENTS:undisclosed_recipients
SMTP_DSN_NOTIFY:dsn_notify
SMTP_DSN_RETURN:dsn_return
"

file_env() {
  var="$1"
  fileVar="${var}_FILE"
  def="${2:-}"

  eval "var_val=\${$var:-}"
  eval "file_var_val=\${$fileVar:-}"

  if [ -n "$var_val" ] && [ -n "$file_var_val" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi

  val="$def"
  if [ -n "$var_val" ]; then
    val="$var_val"
  elif [ -n "$file_var_val" ]; then
    if [ ! -f "$file_var_val" ]; then
      echo >&2 "error: file $file_var_val does not exist"
      exit 1
    fi
    val="$(cat "$file_var_val")"
  fi

  # msmtprc is line-based: a line break would inject another directive.
  case "$val" in
    *"$NEWLINE"* | *"$CARRIAGE_RETURN"*)
      echo >&2 "error: $var must not contain line breaks"
      exit 1
      ;;
  esac

  export "$var=$val"
  unset "$fileVar"
}

# msmtp only strips the surrounding quotes: inner quotes and backslashes are literal,
# so values must not be escaped.
write_option() {
  printf '%s "%s"\n' "$1" "$2" >> "${CONFIG_FILE}"
}

file_env 'SMTP_HOST'
file_env 'SMTP_PORT' '587'

if [ -z "$SMTP_HOST" ]; then
  echo >&2 "ERROR: SMTP_HOST must be defined"
  exit 1
fi

for option in $OPTIONS; do
  file_env "${option%%:*}"
done

echo "Creating configuration at ${CONFIG_FILE}..."

cat > "${CONFIG_FILE}" <<EOL
account default
logfile -
syslog off
EOL

write_option host "$SMTP_HOST"
# shellcheck disable=SC2153 # assigned dynamically by file_env
write_option port "$SMTP_PORT"

for option in $OPTIONS; do
  eval "value=\${${option%%:*}}"
  if [ -n "$value" ]; then
    write_option "${option#*:}" "$value"
  fi
done

unset SMTP_HOST SMTP_PORT value val var_val file_var_val
for option in $OPTIONS; do
  unset "${option%%:*}"
done

echo "Starting: $*"
exec "$@"
