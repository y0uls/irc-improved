# IRC Improved

Un serveur IRC privé, joignable uniquement par une adresse `.onion`, qui
s'installe en une commande sur Windows + Docker Desktop.

Pas de nom de domaine, pas de certificat, pas de port ouvert sur Internet :
le serveur n'est accessible que par le réseau Tor, et vos utilisateurs s'y
connectent soit depuis leur navigateur, soit avec un client de bureau
pré-configuré que vous leur distribuez en un fichier.

```
setup.bat                      →  serveur en ligne + invitation prête à envoyer
client-package\build-client.bat →  IRC-Client.zip (3 Mo) pour Windows
```

## Fonctionnalités

- **Installation en une commande.** `setup.bat` configure, construit, démarre,
  attend la publication du service caché et affiche tout ce qu'il faut pour
  faire entrer quelqu'un.
- **Deux chemins d'accès, une seule adresse.** La même adresse `.onion` sert
  l'interface web (`http://<onion>/`) et les clients IRC classiques
  (`<onion>:6667`).
- **Zéro installation pour vos utilisateurs.** Tor Browser, l'adresse, un
  identifiant : ils arrivent directement dans le salon. Fonctionne sous
  Windows, macOS, Linux et Android.
- **Client de bureau clé en main** pour ceux qui préfèrent : un zip de 3 Mo
  contenant HexChat pré-configuré et un Tor portable, qui se connecte seul.
- **Comptes nominatifs et révocables** individuellement, sans toucher aux
  autres utilisateurs.
- **Adresse `.onion` sauvegardable et restaurable** en une commande : c'est
  l'identité du serveur, elle ne doit jamais être perdue.
- **Salon par défaut permanent**, avec son topic, conservé même vide.
- **Désinstallation complète**, qui demande explicitement avant de détruire
  l'identité du serveur.

## Prérequis

- Windows 10 ou 11
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installé et démarré

Aucune autre dépendance : tout le reste tourne dans des conteneurs.

## Installation

```bat
git clone https://github.com/Y0uls/irc-improved.git
cd irc-improved
setup.bat
```

Le script pose quelques questions (nom du réseau, mots de passe, salon par
défaut, premier compte web), puis affiche un récapitulatif :

```
======================================================================
 Serveur IRC demarre
======================================================================
 A donner aux utilisateurs - Tor Browser, niveau de securite Standard :
     http://xxxxxxxx….onion/

 Salon        : #general
 Admin        : /OPER admin ********
 Adresse IRC  : xxxxxxxx….onion:6667   (HexChat, WeeChat...)
 Mot de passe serveur : ********   (clients IRC classiques)
 Interface web locale : http://localhost:8080   (administrateur)

 Invitation a envoyer a alice : invite-alice.txt
 ...
======================================================================
```

Relancer `setup.bat` plus tard permet de revoir cette configuration ; les
valeurs déjà renseignées ne sont pas redemandées sans y être invité.

## Donner l'accès à quelqu'un

### Par le navigateur — recommandé

```bat
scripts\add-user.bat alice
```

Le compte est créé, le réseau IRC y est pré-rempli, et une invitation
personnelle `invite-alice.txt` est générée : elle contient l'adresse, le salon
et les identifiants de cette personne. C'est ce fichier que vous lui envoyez.

Elle installe [Tor Browser](https://www.torproject.org/download/), ouvre
l'adresse `.onion`, se connecte avec ses identifiants, et arrive directement
dans le salon — rien à configurer.

`invite.txt` et le QR code `invite-qr.png`, eux, ne contiennent **aucun
identifiant** : ils servent à communiquer l'adresse du serveur, par exemple à
quelqu'un qui utilisera un client de bureau.

> Tor Browser doit être en niveau de sécurité **Standard** : en niveau
> « Safest », JavaScript est désactivé et l'interface web ne s'affiche pas.

### Par un client de bureau

```bat
client-package\build-client.bat
```

Produit `client-package\IRC-Client.zip` (~3 Mo). La personne l'extrait,
double-clique `start.bat`, choisit un pseudo, et HexChat se connecte seul
au travers de son propre Tor portable. Rien n'est installé en dehors du
dossier, à part HexChat lui-même s'il est absent.

Le script refuse de produire un package incohérent : il relit l'archive
générée et vérifie l'adresse, le mot de passe, le salon, l'auto-connexion
et la présence de chaque fichier.

### Révoquer un accès

```bat
docker compose exec webclient thelounge remove alice
```

## Architecture

```
┌──────────────┐        réseau Tor        ┌─────────────────────────────┐
│ Tor Browser  │ ───────────────────────► │  tor  (service caché)       │
│ ou HexChat   │      <onion>:80 / :6667  │   ├─► webclient  :9000      │
└──────────────┘                          │   └─► irc        :6667      │
                                          └─────────────────────────────┘
                                                aucun port ouvert
                                                vers l'extérieur
```

| Service | Rôle | Exposition |
|---|---|---|
| `irc` | Serveur InspIRCd | interne au réseau Docker |
| `tor` | Service caché Tor (web + IRC) | réseau Tor uniquement |
| `webclient` | Interface web The Lounge | `.onion` + `127.0.0.1:8080` (admin) |
| `proxytor` | Proxy SOCKS local, optionnel et déconseillé | `127.0.0.1:9050` (profil `proxy`) |

Le conteneur `tor` résout les cibles de ses services cachés à son démarrage et
refuse toute sa configuration si l'une d'elles manque. Son point d'entrée
attend donc l'interface web une minute, puis démarre sans elle en le signalant
dans les logs : une panne du web n'emporte jamais l'accès IRC.

### Structure du dépôt

```
├── setup.bat                     installation et démarrage
├── uninstall.bat                 désinstallation (protège l'identité .onion)
├── docker-compose.yml
├── .env.example                  modèle de configuration
├── branding/                     votre logo (voir branding\README.txt)
├── tools/                        configuration, invitations, helpers PowerShell
├── scripts/                      add-user, backup-onion, restore-onion
├── images/
│   ├── irc/                      image InspIRCd (+ conf.d, MOTD, entrypoint)
│   ├── tor/                      image Tor (torrc, entrypoint)
│   └── webclient/                interface web + application du logo
└── client-package/               générateur du client Windows
```

## Personnaliser l'interface

L'interface web n'a pas à ressembler à The Lounge. Déposez une image dans
`branding\`, relancez `setup.bat`, c'est tout :

| Fichier | Effet |
|---|---|
| `branding\logo.png` | Icône de l'onglet et de l'écran d'accueil mobile — et grand logo de la page de connexion si aucun SVG n'est fourni. Carré, 512×512 recommandé |
| `branding\logo.svg` | Grand logo de la page de connexion et de l'écran de chargement, net à toutes les tailles |

Déposez l'un, l'autre, ou les deux ; sans fichier, le logo d'origine est
conservé. Deux réglages du `.env` complètent l'habillage :

- `BRAND_NAME` : le texte affiché dans l'onglet du navigateur et dans
  l'application installée sur téléphone (par défaut, le nom du réseau).
- `WEB_THEME` : `default` pour l'apparence claire, `morning` pour la sombre.
  C'est ce que voit un nouveau compte ; chacun peut en changer ensuite dans
  *Settings → Appearance*.

Tout est appliqué à la construction de l'image `webclient`, et le cache des
navigateurs est invalidé automatiquement : les personnes déjà inscrites voient
le nouveau logo à leur visite suivante, sans avoir à vider quoi que ce soit.

```bat
docker compose build webclient && docker compose up -d webclient
```

## Configuration

Tout est dans le `.env`, créé par `setup.bat` depuis `.env.example`.

| Variable | Description | Défaut |
|---|---|---|
| `IRC_NETWORK_NAME` | Nom du réseau affiché par les clients | `MonReseau` |
| `IRC_NET_SUFFIX` | Suffixe du hostname serveur | `.irc.local` |
| `ADMIN_NAME`, `ADMIN_NICK`, `ADMIN_EMAIL` | Identité renvoyée par `/ADMIN` | `admin`, `Admin`, `admin@localhost` |
| `CONNECT_PASSWORD` | Mot de passe du serveur, partagé (vide = aucun) | — |
| `OPER_PASSWORD` | Mot de passe de `/OPER admin` | — |
| `OPER_HASH` | `plaintext` ou `bcrypt` | `plaintext` |
| `DEFAULT_CHANNEL` | Salon créé au démarrage | `#general` |
| `DEFAULT_TOPIC` | Topic de ce salon | `Bienvenue sur le serveur IRC !` |
| `DEFAULT_CHANNEL_MODES` | Modes du salon | `+nt` |
| `BRAND_NAME` | Nom affiché dans l'onglet du navigateur | nom du réseau |
| `WEB_THEME` | Apparence par défaut : `default` (claire) ou `morning` (sombre) | `default` |
| `COMPOSE_PROFILES` | Services optionnels (`proxy`) | vide |
| `WEBCLIENT_PORT` | Port local d'administration | `8080` |

Après une modification manuelle du `.env` :

```bat
docker compose up -d --force-recreate irc webclient
docker compose restart tor
```

Le `restart tor` n'est pas facultatif : un conteneur recréé change d'adresse IP,
et `tor` ne la résout qu'à son propre démarrage.

> Évitez `&`, `"` et `$` dans les mots de passe, ainsi qu'une valeur
> entièrement numérique : ces valeurs traversent une configuration XML et la
> ligne de commande de l'interface web.

## Administration

```bat
REM Adresse .onion
docker compose exec -T tor cat /var/lib/tor/hidden_service/hostname

REM Comptes de l'interface web
scripts\add-user.bat alice
docker compose exec webclient thelounge remove alice

REM Régénérer une invitation
powershell -NoProfile -File tools\make-invite.ps1

REM Logs
docker compose logs -f irc
docker compose logs -f tor

REM Arrêt / redémarrage
docker compose down
docker compose up -d
```

Pour modérer (`/KILL`, `/GLINE`, `/SAMODE`…), passez opérateur depuis votre
client :

```
/OPER admin VOTRE_MOT_DE_PASSE
```

## Sauvegarde de l'identité du serveur

L'adresse `.onion` est entièrement déterminée par une paire de clés stockée
dans le volume `irc-improved_tor_keys`. **Si ce volume est perdu, l'adresse est
irrécupérable** : toutes les invitations et tous les packages clients déjà
distribués cessent de fonctionner.

```bat
scripts\backup-onion.bat                          REM → backup\tor-keys-<date>.tgz
scripts\restore-onion.bat backup\tor-keys-….tgz
```

L'archive contient la clé privée du service caché : conservez-la comme un mot
de passe. `uninstall.bat` propose la sauvegarde avant toute suppression et
demande une confirmation séparée pour détruire l'identité.

## Sécurité

Ce que le montage apporte :

- Le lien client ↔ serveur est chiffré et authentifié de bout en bout par Tor :
  l'adresse `.onion` **est** la clé publique du service, elle ne peut pas être
  usurpée et il n'y a pas de certificat à gérer.
- Aucun port n'est publié vers Internet, et le port d'administration local est
  lié à `127.0.0.1`.
- L'accès web est nominatif : un compte par personne, révocable seul.

Ce qu'il n'apporte pas, et qu'il faut savoir :

- Le serveur voit toutes les conversations en clair ; Tor protège le transport,
  pas le contenu côté serveur.
- Le mot de passe du serveur est partagé par tous et figure en clair dans
  chaque package client distribué : un package qui fuite donne un accès IRC
  complet. Le contrôle d'accès réel, c'est le compte web.
- Tous les utilisateurs arrivent avec l'adresse IP du conteneur Tor : il est
  impossible de les distinguer ou d'en bannir un par son adresse.
- Il n'y a pas de services NickServ/ChanServ : aucun pseudo n'est réservé côté
  client de bureau.
- Le `.env`, les invitations, les sauvegardes et le zip client contiennent des
  secrets. Ils sont exclus du dépôt par `.gitignore` — gardez-les ainsi.

## Dépannage

| Symptôme | Cause et correctif |
|---|---|
| L'adresse `.onion` ne répond plus | `tor` ne résout ses cibles qu'au démarrage. Après recréation d'un conteneur : `docker compose restart tor` |
| `http://<onion>/` ne répond pas, mais l'IRC fonctionne | L'interface web était injoignable au démarrage de `tor`. `docker compose up -d webclient && docker compose restart tor` |
| « Délai d'attente dépassé » puis « la connexion a échoué », surtout sur Android | Le navigateur a ouvert l'adresse en `https://` (comportement par défaut quand on tape une adresse sans schéma). Le service caché ne publie que le port 80 : il faut le préfixe `http://` explicite, idéalement en collant le lien de l'invitation. Tor chiffre déjà tout le trajet, `http` sur une adresse `.onion` n'est pas une connexion en clair |
| Page blanche dans Tor Browser | Niveau de sécurité « Safest » : JavaScript est désactivé. Passer en « Standard » |
| Connexion refusée sans raison visible | Vérifier les bans : `docker compose exec -T irc cat /inspircd/data/xline.db`. Les limites sont dans `images/irc/conf.d/00-limits.conf` |
| `/OPER` échoue | `OPER_PASSWORD` renseigné dans le `.env` ? Puis `docker compose up -d --force-recreate irc` |
| Le client de bureau ne se connecte pas | Le premier démarrage de Tor prend de 30 s à 3 min ; la fenêtre affiche la progression. Les suivants sont quasi instantanés |
| Windows bloque `start.bat` ou met `tor.exe` en quarantaine | Le zip est marqué « venu d'Internet ». Clic droit sur le zip → Propriétés → Débloquer, avant d'extraire |

## Choix techniques

Quelques réglages s'écartent volontairement des valeurs par défaut des
composants utilisés. Ils sont tous liés au même fait : derrière un service
caché, **tous les utilisateurs partagent l'adresse IP du conteneur Tor**.

- **InspIRCd 4** avec des classes de connexion dédiées au réseau Docker : sans
  elles, la classe par défaut limite à 3 connexions par adresse IP, et comme
  tous les utilisateurs Tor partagent l'IP du conteneur `tor`, le serveur
  plafonnait à 3 personnes.
- **`connectban` recalibré** : avec ses valeurs par défaut, 10 connexions
  depuis l'IP partagée suffisaient à bannir tout le monde pour 6 heures.
- **Sonde de santé sans session IRC** (`pgrep`) : une sonde qui ouvrait une
  connexion toutes les 15 s alimentait elle-même l'anti-flood.
- **Salon par défaut généré au démarrage**, avec échappement XML du nom et du
  topic.
- **Toute la configuration passe par PowerShell** : les valeurs ne sont jamais
  interpolées dans une ligne de commande ni utilisées comme chaîne de
  remplacement d'une expression régulière, et le `.env` est écrit en UTF-8 sans
  BOM. Un mot de passe contenant `'`, `$`, `!` ou `=` traverse donc la chaîne
  intact, du setup jusqu'au package client.

## Licence

Aucune licence n'est encore déclarée : par défaut, tous droits réservés.
Ajoutez un fichier `LICENSE` si vous souhaitez autoriser la réutilisation.
