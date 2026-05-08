FROM alpine:latest

RUN apk add --no-cache \
    msmtp \
    tzdata \
    ca-certificates

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 2500

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["msmtpd", "--interface=0.0.0.0", "--port=2500", "--command=/usr/bin/msmtp -C /tmp/msmtprc -f %F --"]
