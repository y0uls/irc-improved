# IRC Server — Docker (InspIRCd + Tor + The Lounge)

Serveur IRC privé accessible via un hidden service Tor, avec interface web intégrée et package client Windows clé en main.

## Structure du projet

```
├── setup.bat                       ← Setup et démarrage du serveur
├── uninstall.bat                   ← Désinstallation complète
├── .env.example                    ← Template de configuration
├── docker-compose.yml
├── images/
│   ├── irc/
|   |   ├── docker.motd             ← Page d'acceuil du serveur IRC
|   |   ├── Dockerfile              ← Crée l'image InspIRCd
|   |   ├── entrypoint-wrapper.sh   ← Crée le channel par défaut
|   |   └── permchannels.conf       ← Fichier channel par défaut
│   └── tor/
|       ├── Dockerfile              ← Crée l'image Tor
|       └── torrc                   ← Fichier de création du hidden service
└── client-package/
    ├── build-client.bat            ← Génère IRC-Client.zip
    └── config/
        ├── start.bat               ← Wrapper client (Tor + HexChat)
        ├── uninstall.bat           ← Désinstalleur côté client
        ├── hexchat.conf            ← Config HexChat complète (proxy inclus)
        └── servlist.conf           ← Template réseau IRC (placeholders)
            └── tor/                ← Tous les fichiers utiles pour faire fonctionner tor
```

---

## Déploiement du serveur

### Prérequis

- Docker Desktop installé et démarré
- Windows 10/11

### Démarrage

```bat
setup.bat
```

Le script gère automatiquement :

1. Création du `.env` depuis `.env.example`
2. Configuration du nom du réseau IRC
3. Génération du hash du mot de passe oper (`hmac-sha256`)
4. Configuration du mot de passe de connexion et du channel par défaut
5. Build et démarrage des containers
6. Affichage de l'adresse `.onion`
7. Création optionnelle d'un compte The Lounge

### Services disponibles

| Service | Description | Port |
|---|---|---|
| `irc` | Serveur InspIRCd | interne |
| `tor` | Hidden service Tor | interne |
| `proxytor` | Proxy SOCKS5 Tor (optionnel) | `9050`, `8118` |
| `webclient` | Interface web The Lounge (optionnel) | `8080` |

`proxytor` et `webclient` sont optionnels — le script de setup te demande si tu veux les démarrer.

---

## Variables d'environnement (`.env`)

| Variable | Description | Défaut |
|---|---|---|
| `IRC_NETWORK_NAME` | Nom du réseau IRC | `MonReseau` |
| `IRC_NET_SUFFIX` | Suffixe hostname serveur | `.irc.local` |
| `ADMIN_NAME` | Nom de l'admin | `admin` |
| `ADMIN_NICK` | Pseudo de l'admin | `Admin` |
| `ADMIN_EMAIL` | Email admin | `admin@localhost` |
| `CONNECT_PASSWORD` | Mot de passe de connexion au serveur (vide = aucun) | — |
| `OPER_PASSWORD_HASH` | Hash `hmac-sha256` du mot de passe oper | — |
| `DEFAULT_CHANNEL` | Channel créé au démarrage | `#general` |
| `DEFAULT_TOPIC` | Topic du channel par défaut | — |
| `WEBCLIENT_PORT` | Port de The Lounge | `8080` |

---

## Générer le package client Windows

Une fois le serveur démarré :

```bat
cd client-package
build-client.bat
```

Cela génère `client-package\IRC-Client.zip` en récupérant automatiquement l'adresse `.onion` depuis le container Tor et en l'injectant dans la configuration HexChat.

### Contenu du zip distribué

```
IRC-Client.zip
├── HexChat\
│   ├── servlist.conf     ← Réseau .onion préconfiguré
│   └── hexchat.conf      ← Config complète avec proxy SOCKS5
├── tor\                  ← Tous les fichiers utiles pour faire fonctionner tor
├── start.bat             ← Lancement tout-en-un
├── uninstall.bat         ← Désinstallation côté client
└── README.txt
```

### Ce que fait `start.bat` côté client

1. Télécharge et installe **HexChat** silencieusement si absent
2. Copie la configuration HexChat préconfigurée dans `%APPDATA%\HexChat\`
3. Lance `tor.exe` en arrière-plan
4. Attend que le proxy SOCKS5 soit disponible sur `127.0.0.1:9050`
5. Lance **HexChat** (connecté automatiquement au serveur)
6. Quand HexChat est fermé, arrête `tor.exe`

L'utilisateur n'a qu'à double-cliquer `start.bat`. Tout est automatique.

### Ce que fait `uninstall.bat` côté client

- Arrête Tor et HexChat si actifs
- Supprime `%APPDATA%\HexChat\` (config, logs)
- Désinstalle HexChat silencieusement

---

## Connexion via The Lounge (interface web)

1. Ouvre `http://localhost:8080` (si configuré pendant le setup)
2. Connecte-toi avec le compte créé pendant le setup
3. Clique sur **+ Add a network** :
   - **Server** : `irc`
   - **Port** : `6667`
   - **TLS** : désactivé
   - **Channel** : ton channel par défaut (ex: `#general`)
   - **Password** : le mot de passe de connexion (si configuré)

---

## Connexion via WeeChat (avancé)

```
/set proxy.proxies.tor.type socks5
/set proxy.proxies.tor.address 127.0.0.1
/set proxy.proxies.tor.port 9050
/server add monserveur <adresse>.onion/6667 -proxy=tor
/connect monserveur
```

---

## Devenir oper

Une fois connecté au serveur IRC :

```
/OPER admin VOTRE_MOT_DE_PASSE_EN_CLAIR
```

---

## Commandes utiles

```bat
# Voir l'adresse .onion
docker compose exec tor cat /var/lib/tor/hidden_service/hostname

# Logs en direct
docker compose logs -f irc
docker compose logs -f tor

# Redémarrer un service
docker compose restart irc

# Arrêter tout
docker compose down

# Ajouter un compte The Lounge
docker compose exec webclient thelounge add PSEUDO

# Supprimer un compte The Lounge
docker compose exec webclient thelounge remove PSEUDO

# Désinstallation complète (containers, volumes, images, .env)
uninstall.bat
```

---

## Sécurité

- Les clés Tor sont stockées dans un **volume Docker** — l'adresse `.onion` persiste entre les redémarrages
- Le mot de passe oper est stocké **hashé** (`hmac-sha256`) dans le `.env`
- `INSP_ENABLE_DNSBL=no` est forcé pour la compatibilité Tor
- Le `.env` doit être dans `.gitignore` — **ne jamais le committer**
- Le zip client ne contient aucune clé privée ni donnée sensible du serveur
