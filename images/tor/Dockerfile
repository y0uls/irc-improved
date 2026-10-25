FROM alpine:latest

RUN apk update && apk add --no-cache tor

# Les sed retirent les fins de ligne Windows (CRLF) : avec elles, le
# conteneur ne demarrait pas ("#!/bin/sh\r" introuvable) sur un poste ou
# Git avait converti les fichiers a l'extraction. Voir
# images/webclient/Dockerfile.
COPY torrc /etc/tor/torrc
RUN sed -i 's/\r$//' /etc/tor/torrc && \
    chown -R tor /etc/tor

# entrypoint.sh retire la ligne du service cache web quand le conteneur
# webclient est absent : sans lui, tor refuserait toute sa configuration
# et l'acces IRC .onion tomberait avec l'interface web.
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && \
    chmod 0755 /entrypoint.sh

# Hidden service dir will be mounted as volume (keys persist between restarts)
RUN mkdir -p /var/lib/tor/hidden_service && \
    chown -R 100:100 /var/lib/tor/hidden_service && \
    chmod 700 /var/lib/tor/hidden_service

USER tor

ENTRYPOINT ["/entrypoint.sh"]
