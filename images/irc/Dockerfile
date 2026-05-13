FROM inspircd/inspircd-docker:latest

# Copie le template permchannels (sera modifié au runtime dans /tmp)
COPY ./permchannels.conf /inspircd/conf.d/permchannels.conf
COPY ./entrypoint-wrapper.sh /entrypoint-wrapper.sh

USER root
RUN chmod +x /entrypoint-wrapper.sh && \
    chmod 644 /inspircd/conf.d/permchannels.conf

USER inspircd

ENTRYPOINT ["/entrypoint-wrapper.sh"]
