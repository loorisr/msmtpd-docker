#!/bin/sh
set -e

TZ=${TZ:-UTC}
SMTP_PORT=${SMTP_PORT:-587}
CONFIG_FILE="/tmp/msmtprc"

export MSMTPRC="${CONFIG_FILE}"

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
  export "$var"="$val"
  unset "$fileVar"
}

file_env 'SMTP_HOST'

if [ -z "$SMTP_HOST" ]; then
  echo >&2 "ERROR: SMTP_HOST must be defined"
  exit 1
fi

echo "Creating configuration at ${CONFIG_FILE}..."

cat > "${CONFIG_FILE}" <<EOL
account default
logfile -
syslog off
host ${SMTP_HOST}
EOL

file_env 'SMTP_USER'
file_env 'SMTP_PASSWORD'

[ -n "$SMTP_PORT" ] && echo "port ${SMTP_PORT}" >> "${CONFIG_FILE}"
[ -n "$SMTP_TLS" ] && echo "tls ${SMTP_TLS}" >> "${CONFIG_FILE}"
[ -n "$SMTP_STARTTLS" ] && echo "tls_starttls ${SMTP_STARTTLS}" >> "${CONFIG_FILE}"
[ -n "$SMTP_TLS_CHECKCERT" ] && echo "tls_certcheck ${SMTP_TLS_CHECKCERT}" >> "${CONFIG_FILE}"
[ -n "$SMTP_AUTH" ] && echo "auth ${SMTP_AUTH}" >> "${CONFIG_FILE}"
[ -n "$SMTP_USER" ] && echo "user ${SMTP_USER}" >> "${CONFIG_FILE}"
[ -n "$SMTP_PASSWORD" ] && echo "password ${SMTP_PASSWORD}" >> "${CONFIG_FILE}"
[ -n "$SMTP_DOMAIN" ] && echo "domain ${SMTP_DOMAIN}" >> "${CONFIG_FILE}"
[ -n "$SMTP_FROM" ] && echo "from ${SMTP_FROM}" >> "${CONFIG_FILE}"
[ -n "$SMTP_ALLOW_FROM_OVERRIDE" ] && echo "allow_from_override ${SMTP_ALLOW_FROM_OVERRIDE}" >> "${CONFIG_FILE}"
[ -n "$SMTP_SET_FROM_HEADER" ] && echo "set_from_header ${SMTP_SET_FROM_HEADER}" >> "${CONFIG_FILE}"
[ -n "$SMTP_SET_DATE_HEADER" ] && echo "set_date_header ${SMTP_SET_DATE_HEADER}" >> "${CONFIG_FILE}"
[ -n "$SMTP_REMOVE_BCC_HEADERS" ] && echo "remove_bcc_headers ${SMTP_REMOVE_BCC_HEADERS}" >> "${CONFIG_FILE}"
[ -n "$SMTP_UNDISCLOSED_RECIPIENTS" ] && echo "undisclosed_recipients ${SMTP_UNDISCLOSED_RECIPIENTS}" >> "${CONFIG_FILE}"
[ -n "$SMTP_DSN_NOTIFY" ] && echo "dsn_notify ${SMTP_DSN_NOTIFY}" >> "${CONFIG_FILE}"
[ -n "$SMTP_DSN_RETURN" ] && echo "dsn_return ${SMTP_DSN_RETURN}" >> "${CONFIG_FILE}"

chmod 600 "${CONFIG_FILE}"

unset SMTP_USER
unset SMTP_PASSWORD

echo "Starting: $*"
exec "$@"
