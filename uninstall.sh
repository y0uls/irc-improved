#!/bin/bash

echo "=== Désinstallation du serveur IRC ==="
echo ""
echo "⚠️  Cette opération va supprimer :"
echo "   - Tous les containers (irc, tor, webclient, proxytor)"
echo "   - Tous les volumes Docker (clés Tor, config, logs)"
echo "   - Les images Docker buildées"
echo "   - Le fichier .env"
echo ""
read -rp "Confirmer la suppression complète ? [o/N] : " CONFIRM
if [[ "$CONFIRM" != "o" && "$CONFIRM" != "O" ]]; then
  echo "Annulé."
  exit 0
fi

echo ""
echo "--- Arrêt et suppression des containers + volumes ---"
docker compose down -v --remove-orphans 2>/dev/null || true

echo "--- Suppression des images buildées ---"
docker rmi irc-server tor-hidden-service 2>/dev/null || true

echo "--- Suppression du .env ---"
rm -f .env

echo ""
echo "✅ Désinstallation terminée. Aucune trace laissée."
