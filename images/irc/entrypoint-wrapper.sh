#!/bin/sh

# Copie le template dans /tmp (inscriptible) et substitue les variables
TEMPLATE=/inspircd/conf.d/permchannels.conf
TMP=/tmp/permchannels.conf

cp "$TEMPLATE" "$TMP"
sed -i "s|DEFAULT_CHANNEL_VAR|${DEFAULT_CHANNEL:-#general}|g" "$TMP"
sed -i "s|DEFAULT_TOPIC_VAR|${DEFAULT_TOPIC:-Bienvenue !}|g"   "$TMP"
cp "$TMP" "$TEMPLATE" 2>/dev/null || {
  # Si conf.d est en lecture seule, on monte dans conf à la place
  cp "$TMP" /inspircd/conf/permchannels.conf
}

# Trouver l'entrypoint officiel de l'image
for EP in /entrypoint.sh /usr/local/bin/entrypoint.sh /inspircd/docker-entrypoint.sh; do
  if [ -x "$EP" ]; then
    exec "$EP" "$@"
  fi
done

# Fallback : lancer InspIRCd directement
exec /inspircd/bin/inspircd --nofork "$@"
