#!/bin/bash

echo "=== Génération du package client HexChat ==="
echo ""

# Récupérer l'adresse .onion
ONION=$(docker compose exec tor cat /var/lib/tor/hidden_service/hostname 2>/dev/null | tr -d '\r\n')
if [ -z "$ONION" ]; then
  echo "❌ Impossible de récupérer l'adresse .onion."
  echo "   Vérifiez que les containers sont démarrés."
  exit 1
fi
echo "✅ Adresse .onion : $ONION"

# Récupérer les variables du .env
CONN_PASS=$(grep "^CONNECT_PASSWORD=" ../.env | cut -d= -f2)
CHAN=$(grep "^DEFAULT_CHANNEL=" ../.env | cut -d= -f2)
CHAN=${CHAN:-#general}

# Créer le dossier de config
OUTDIR="./HexChat-config/HexChat"
rm -rf ./HexChat-config
mkdir -p "$OUTDIR"

# servlist.conf — réseau pré-configuré
cat > "$OUTDIR/servlist.conf" << CONF
[Networks]
n0=${ONION}\p0
[Network ${ONION}]
N=MonServeurIRC
E=UTF-8 (Unicode)
F=19
S=${ONION}/6667
P=${CONN_PASS}
J=${CHAN}
B=
CONF

# hexchat.conf — proxy SOCKS5 vers proxytor
cat > "$OUTDIR/hexchat.conf" << CONF
net_proxy_host = 127.0.0.1
net_proxy_port = 9050
net_proxy_type = 3
net_proxy_auth = 0
CONF

# README utilisateur
cat > "./HexChat-config/README.txt" << TXT
# Connexion au serveur IRC

## Pré-requis

Le serveur doit être démarré (docker compose up -d).
Le proxy Tor est accessible sur 127.0.0.1:9050.

## Installation

1. Télécharge et installe HexChat : https://hexchat.github.io
2. Copie le dossier HexChat/ dans ~/.config/
   (Linux/Mac : ~/.config/hexchat/)
   (Windows  : %APPDATA%\HexChat\)
3. Lance HexChat
4. Le réseau "MonServeurIRC" apparaît déjà configuré
5. Connecte-toi !

## Adresse du serveur

${ONION}:6667
TXT

# Zipper
zip -r HexChat-IRC-Client.zip HexChat-config/
echo ""
echo "✅ Package généré : HexChat-IRC-Client.zip"
echo "   Distribue ce zip à tes utilisateurs."
