#!/bin/bash
set -e

echo "=== Setup du serveur IRC ==="

if ! command -v docker &>/dev/null; then
  echo "❌ Docker n'est pas installé."
  exit 1
fi

if [ ! -f .env ]; then
  cp .env.example .env
  echo "✅ Fichier .env créé. Éditez-le avant de continuer !"
  echo "   → nano .env"
  exit 0
fi

# IRC_NETWORK_NAME
if grep -q "MonReseau" .env; then
  echo ""
  echo "⚠️ IRC_NETWORK_NAME est toujours MonReseau."
  read -rsp "Nom de mon network IRC : " IRC_NETWORK
  echo ""
  sed -i "s|IRC_NETWORK_NAME=.*|IRC_NETWORK_NAME=$IRC_NETWORK|" .env
  echo "✅ Network name enregistré."
fi

# Hash mot de passe oper
if grep -q "CHANGEME" .env; then
  echo ""
  echo "⚠️  OPER_PASSWORD_HASH est toujours 'CHANGEME'."
  read -rsp "Mot de passe oper (pour /OPER admin) : " OPER_PASS
  echo ""
  HASH=$(docker run --rm inspircd/inspircd-docker:latest /inspircd/bin/inspircd --mkpasswd hmac-sha256 "$OPER_PASS" 2>/dev/null | grep -oP '(?<=Password: ).*')
  sed -i "s|OPER_PASSWORD_HASH=.*|OPER_PASSWORD_HASH=$HASH|" .env
  echo "✅ Hash oper enregistré."
fi

# Mot de passe de connexion
if grep -q "^CONNECT_PASSWORD=$" .env; then
  echo ""
  read -rsp "Mot de passe pour rejoindre le serveur IRC (Entrée = aucun) : " CONN_PASS
  echo ""
  sed -i "s|^CONNECT_PASSWORD=.*|CONNECT_PASSWORD=$CONN_PASS|" .env
  if [ -n "$CONN_PASS" ]; then
    echo "✅ Mot de passe de connexion enregistré."
  else
    echo "ℹ️  Aucun mot de passe de connexion (serveur public)."
  fi
fi

# Channel par défaut
if grep -q "^DEFAULT_CHANNEL=#general$" .env; then
  echo ""
  read -rp "Channel par défaut [#general] : " CHAN
  CHAN=${CHAN:-#general}
  # Ajouter # si oublié
  [[ "$CHAN" != \#* ]] && CHAN="#$CHAN"
  sed -i "s|^DEFAULT_CHANNEL=.*|DEFAULT_CHANNEL=$CHAN|" .env

  read -rp "Topic du channel [$CHAN] : " TOPIC
  TOPIC=${TOPIC:-Bienvenue sur le serveur IRC !}
  sed -i "s|^DEFAULT_TOPIC=.*|DEFAULT_TOPIC=$TOPIC|" .env
  echo "✅ Channel $CHAN configuré."
fi

echo ""
echo "=== Build et démarrage ==="
docker compose build
docker compose up -d

echo ""
echo "=== Attente du démarrage de Tor (~30s) ==="
sleep 30

echo ""
echo "=== Adresse .onion ==="
docker compose exec tor cat /var/lib/tor/hidden_service/hostname 2>/dev/null || \
  echo "⏳ Tor démarre encore, relancez : docker compose exec tor cat /var/lib/tor/hidden_service/hostname"

echo ""
echo "=== Compte The Lounge (interface web) ==="
echo "Il faut créer au moins un compte pour accéder à l'interface web."
read -rp "Pseudo pour The Lounge : " LOUNGE_USER
if [ -n "$LOUNGE_USER" ]; then
  docker compose exec webclient thelounge add "$LOUNGE_USER"
  echo "✅ Compte '$LOUNGE_USER' créé."
else
  echo "⚠️  Créez un compte plus tard : docker compose exec webclient thelounge add PSEUDO"
fi

WCPORT=$(grep WEBCLIENT_PORT .env | cut -d= -f2)
echo ""
echo "✅ Serveur IRC démarré !"
echo "   Interface web : http://localhost:${WCPORT:-8080}"
echo "   Logs IRC      : docker compose logs -f irc"
echo "   Logs Tor      : docker compose logs -f tor"
