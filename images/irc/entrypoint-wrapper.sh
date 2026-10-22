#!/bin/sh
# ======================================================================
#  Genere la configuration du channel par defaut, puis passe la main a
#  l'entrypoint officiel de l'image inspircd.
#
#  Historique : ce script copiait un template et y substituait les
#  variables avec sed. L'ecriture dans /inspircd/conf.d echouait en
#  silence (dossier root, process inspircd) et le fallback ecrivait dans
#  /inspircd/conf, qui n'est JAMAIS inclus par config.sh. Resultat : le
#  serveur chargeait un salon nomme litteralement "DEFAULT_CHANNEL_VAR",
#  nom invalide, ignore - donc aucun channel par defaut, aucun topic.
#  On genere maintenant le fichier directement, et on echoue bruyamment.
# ======================================================================
set -e

CONF_D=/inspircd/conf.d
PERMCHAN="$CONF_D/permchannels.conf"

# Echappement XML : un & ou un " dans le nom du channel ou le topic
# casserait la configuration et empecherait le serveur de demarrer.
esc() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g" -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

CHAN="${DEFAULT_CHANNEL:-#general}"
# InspIRCd rejette (en silence) un nom de channel sans prefixe.
case "$CHAN" in
  \#*|\&*) ;;
  *) CHAN="#$CHAN" ;;
esac
CHAN_X=$(esc "$CHAN")
TOPIC_X=$(esc "${DEFAULT_TOPIC:-Bienvenue !}")

if [ ! -w "$CONF_D" ]; then
  echo "[ERREUR] $CONF_D n'est pas inscriptible par $(id -un) :" >&2
  echo "         le channel par defaut ne peut pas etre cree." >&2
  echo "         Reconstruisez l'image : docker compose build irc" >&2
  exit 1
fi

cat > "$PERMCHAN" <<EOF
# Fichier genere au demarrage par /entrypoint-wrapper.sh - ne pas editer.
<module name="permchannels">

# La base est dans /inspircd/conf, qui est un volume : le channel, son
# topic et ses modes survivent donc au redemarrage du conteneur.
<permchanneldb filename="/inspircd/conf/permchannels.db" listmodes="yes">

# +n : pas de messages depuis l'exterieur du salon
# +t : seuls les operateurs changent le topic
# (le mode +s - salon secret - est volontairement absent : avec lui, le
#  salon n'apparaissait pas dans /LIST, meme pour ses membres)
<permchannels channel="$CHAN_X"
              topic="$TOPIC_X"
              modes="${DEFAULT_CHANNEL_MODES:-+nt}">
EOF

echo "[OK] Channel par defaut : $CHAN"

# Resynchronise le MOTD : l'entrypoint de l'image ne copie /conf/* que si
# /inspircd/conf/inspircd.conf est absent, donc une modification de
# docker.motd resterait invisible tant que le volume irc_conf existe.
if [ -f /conf/docker.motd ] && [ -w /inspircd/conf ]; then
  if ! cmp -s /conf/docker.motd /inspircd/conf/docker.motd 2>/dev/null; then
    cp /conf/docker.motd /inspircd/conf/docker.motd && echo "[OK] MOTD mis a jour."
  fi
fi

# Entrypoint officiel de l'image (il genere la config puis lance InspIRCd).
for EP in /entrypoint.sh /usr/local/bin/entrypoint.sh /inspircd/docker-entrypoint.sh; do
  if [ -x "$EP" ]; then
    exec "$EP" "$@"
  fi
done

echo "[ATTENTION] entrypoint officiel introuvable, lancement direct." >&2
exec /inspircd/bin/inspircd --nofork "$@"
