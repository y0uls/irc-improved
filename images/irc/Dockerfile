FROM inspircd/inspircd-docker:latest

# conf.d est inclus automatiquement par /inspircd/conf/config.sh.
# Il doit appartenir a l'utilisateur inspircd : l'entrypoint y ecrit la
# configuration du channel par defaut a chaque demarrage.
COPY ./conf.d/ /inspircd/conf.d/
COPY ./entrypoint-wrapper.sh /entrypoint-wrapper.sh
# /conf est le repertoire de reference de l'image : son contenu est copie
# dans /inspircd/conf (volume) au tout premier demarrage. L'entrypoint le
# resynchronise ensuite a chaque demarrage, pour qu'un rebuild suffise a
# mettre le MOTD a jour (sinon il resterait fige au premier demarrage).
COPY ./docker.motd /conf/docker.motd

USER root
# Le sed retire les fins de ligne Windows (CRLF) : avec elles, le conteneur
# ne demarrait pas ("#!/bin/sh\r" introuvable) sur un poste ou Git avait
# converti les fichiers a l'extraction. Voir images/webclient/Dockerfile.
RUN sed -i 's/\r$//' /entrypoint-wrapper.sh /inspircd/conf.d/*.conf /conf/docker.motd && \
    chmod +x /entrypoint-wrapper.sh && \
    chown -R inspircd:inspircd /inspircd/conf.d && \
    chmod 755 /inspircd/conf.d && \
    chmod 644 /inspircd/conf.d/*.conf

USER inspircd

ENTRYPOINT ["/entrypoint-wrapper.sh"]
