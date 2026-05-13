# IRC Server — Docker (InspIRCd + Tor + The Lounge)

Serveur IRC privé accessible via Tor hidden service, avec une interface web intégrée.

## Architecture

```
[Client IRC + proxy SOCKS5]
        │
        ▼
  proxytor (:9050) ──► Tor (.onion:6667) ──► InspIRCd
                                                 ▲
                                    The Lounge (:8080)
```

Le service `proxytor` expose un proxy SOCKS5 sur le port `9050` de ta machine.  
Les clients IRC (HexChat, WeeChat…) s'y connectent pour atteindre le `.onion` sans installer Tor.

---

## Déploiement

```bash
# Windows
setup.bat

# Linux / Mac
bash setup.sh
```

Le script gère automatiquement :
1. La création du `.env` depuis `.env.example`
2. La génération du hash du mot de passe oper
3. La configuration du mot de passe de connexion et du channel par défaut
4. Le build et le démarrage des containers
5. L'affichage de l'adresse `.onion`
6. La création du compte The Lounge

---

## Se connecter

### Option 1 — Interface web The Lounge (recommandé)

1. Ouvre `http://localhost:8080`
2. Connecte-toi avec le compte créé pendant le setup
3. Clique sur **+ Add a network** et configure :
   - **Name** : ce que tu veux
   - **Server** : `irc`
   - **Port** : `6667`
   - **TLS** : désactivé
   - **Channel** : ton channel par défaut (ex: `#general`)
   - **Password** : le mot de passe de connexion (si configuré)
4. Clique sur **Connect**

---

### Option 2 — HexChat via proxytor (inclus dans Docker)

Le proxy Tor tourne déjà dans Docker, exposé sur `localhost:9050`.  
**Pas besoin d'installer Tor sur ta machine.**

#### Configuration HexChat

1. **Settings → Preferences → Network Setup**
   - Hostname : `127.0.0.1`
   - Port : `9050`
   - Type : `Socks5`
   - Laisse "Username" et "Password" vides

2. **HexChat → Network List → Add**
   - Name : `MonServeurIRC`
   - Servers : `<adresse>.onion/6667`
   - Décocher "Use SSL"
   - Server password : ton mot de passe de connexion (si configuré)

3. Clique **Connect**

Pour récupérer ton adresse `.onion` :
```bash
docker compose exec tor cat /var/lib/tor/hidden_service/hostname
```

#### Configuration WeeChat

```
/set proxy.proxies.tor.type socks5
/set proxy.proxies.tor.address 127.0.0.1
/set proxy.proxies.tor.port 9050
/server add monserveur <adresse>.onion/6667 -proxy=tor
/connect monserveur
```

---

## Distribuer HexChat à tes utilisateurs (Windows)

Pour que tes utilisateurs se connectent facilement **sans rien configurer** :

1. Télécharge **HexChat** : https://hexchat.github.io
2. Lance HexChat une fois, configure le réseau + proxy comme ci-dessus
3. Copie le dossier de config HexChat :
   ```
   %APPDATA%\HexChat\
   ```
4. Zippe HexChat + ce dossier de config et distribue l'archive.

Les utilisateurs extraient, lancent HexChat, et tombent directement sur ton serveur.  
> Le proxy `localhost:9050` doit être accessible sur leur machine → ils doivent aussi lancer ton `docker-compose` ou avoir Tor installé.

---

## Devenir oper

Une fois connecté, tape dans ton client IRC :
```
/OPER admin VOTRE_MOT_DE_PASSE
```
(le mot de passe en clair saisi pendant le setup, pas le hash)

---

## Ajouter un compte The Lounge

```bash
docker compose exec webclient thelounge add PSEUDO
```

---
## Supprimer un compte The Lounge

```bash
docker compose exec webclient thelounge remove PSEUDO
```

---

## Commandes utiles

```bash
# Voir les logs
docker compose logs -f irc
docker compose logs -f tor

# Voir l'adresse .onion
docker compose exec tor cat /var/lib/tor/hidden_service/hostname

# Redémarrer un service
docker compose restart irc

# Arrêter tout
docker compose down

# Désinstallation complète
bash uninstall.sh        # Linux/Mac
uninstall.bat            # Windows
```

---

## Sécurité

- Les clés Tor sont dans un **volume Docker** — ton adresse `.onion` persiste entre les redémarrages
- Le mot de passe oper est stocké **hashé** dans le `.env`
- Le `.env` est dans `.gitignore` — ne le commitez jamais
- `INSP_ENABLE_DNSBL=no` est forcé pour que Tor fonctionne correctement
- Le proxy `proxytor` expose `9050` uniquement en local (`127.0.0.1`) — pas accessible depuis l'extérieur
