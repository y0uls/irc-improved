# Interface web The Lounge, personnalisee avec le logo et le nom du projet.
#
# Pourquoi une image derivee plutot qu'un montage de fichiers : les assets
# de l'application appartiennent a root alors que le service tourne sous
# l'utilisateur node, et un montage de fichier absent ferait apparaitre un
# dossier vide a sa place. Ici, tout est applique au build, une fois.
#
# Le contexte de build est la RACINE du projet (pour atteindre branding/),
# restreint par .dockerignore aux seuls dossiers utiles.
FROM ghcr.io/thelounge/thelounge:latest

# Nom affiche dans l'onglet du navigateur et dans l'application installee.
ARG BRAND_NAME=""

COPY branding/ /branding/
COPY images/webclient/apply-branding.sh /apply-branding.sh

USER root
RUN chmod +x /apply-branding.sh && \
    /apply-branding.sh "$BRAND_NAME" && \
    rm -rf /branding /apply-branding.sh

USER node
