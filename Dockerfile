FROM alpine:3.24

RUN apk add --no-cache \
    msmtp \
    tzdata \
    ca-certificates

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 2500

USER 1000:1000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["nc", "-z", "127.0.0.1", "2500"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["msmtpd", "--interface=0.0.0.0", "--port=2500", "--command=/usr/bin/msmtp -C /tmp/msmtprc -f %F --"]
