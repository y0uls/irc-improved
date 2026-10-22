#!/bin/sh
# ======================================================================
#  Demarrage de tor.
#
#  tor resout les cibles des lignes HiddenServicePort au demarrage, et
#  refuse sa configuration ENTIERE des qu'une seule d'entre elles ne
#  resout pas :
#      [warn] Unparseable address in hidden service port configuration.
#      [err]  Reading config failed--see warnings above.
#  Le conteneur part alors en boucle de redemarrage et le service cache
#  tombe EN ENTIER : l'acces IRC .onion:6667 disparait lui aussi, alors
#  que seule l'interface web manquait.
#
#  On verifie donc la configuration complete avant de lancer tor, et on
#  repart sans la ligne de l'interface web si elle ne passe pas. Le
#  service IRC reste joignable quoi qu'il arrive.
#
#  L'attente : docker compose fait demarrer webclient avant tor
#  (depends_on), mais cette garantie ne vaut QUE pour "docker compose up".
#  Quand Docker Desktop redemarre et relance les conteneurs lui-meme
#  (restart: unless-stopped), l'ordre n'est pas garanti : sans cette
#  boucle, tor demarrerait en mode repli et l'interface web resterait
#  injoignable jusqu'a un "docker compose restart tor" manuel.
# ======================================================================
set -e

SRC=/etc/tor/torrc
RUN=/tmp/torrc

WEB_LINE='^HiddenServicePort 80 '
# Chaque essai coute deja ~5 s : "tor --verify-config" attend le timeout du
# resolveur DNS de Docker avant d'echouer. Avec DELAY=5, un essai vaut donc
# ~10 s de temps reel, et 6 essais ~60 s. Ne pas augmenter a la legere :
# pendant cette attente, l'acces IRC .onion n'est pas publie non plus.
TRIES=6
DELAY=5

cp "$SRC" "$RUN"

# Pas de ligne web a attendre : on demarre directement.
if ! grep -q "$WEB_LINE" "$SRC"; then
    exec tor -f "$RUN"
fi

i=0
while [ "$i" -lt "$TRIES" ]; do
    if tor --verify-config -f "$RUN" >/dev/null 2>&1; then
        [ "$i" -gt 0 ] && echo "[info] webclient resolu apres $((i * DELAY)) s."
        exec tor -f "$RUN"
    fi
    i=$((i + 1))
    [ "$i" -eq 1 ] && echo "[info] webclient pas encore joignable, attente (~60 s max)..."
    sleep "$DELAY"
done

# Repli : meme configuration, sans le service cache de l'interface web.
grep -v "$WEB_LINE" "$SRC" > "$RUN"
if tor --verify-config -f "$RUN" >/dev/null 2>&1; then
    echo "[warn] Le conteneur webclient est reste injoignable."
    echo "[warn] Le service cache web est desactive ; http://<onion>/ ne repondra pas."
    echo "[warn] L'acces IRC <onion>:6667 reste disponible."
    echo "[warn] Pour retablir l'interface web :"
    echo "[warn]     docker compose up -d webclient && docker compose restart tor"
    exec tor -f "$RUN"
fi

echo "[err] Configuration tor invalide meme sans l'interface web :"
tor --verify-config -f "$RUN" 2>&1 | tail -n 20
exit 1
