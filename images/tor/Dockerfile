FROM alpine:latest

RUN apk update && apk add --no-cache tor

COPY torrc /etc/tor/torrc
RUN chown -R tor /etc/tor

# Hidden service dir will be mounted as volume (keys persist between restarts)
RUN mkdir -p /var/lib/tor/hidden_service && \
    chown -R 100:100 /var/lib/tor/hidden_service && \
    chmod 700 /var/lib/tor/hidden_service

USER tor

ENTRYPOINT ["tor"]
CMD ["-f", "/etc/tor/torrc"]
