# Package client

`build-client.bat` fabrique `IRC-Client.zip` (~3 Mo), le dossier à distribuer
aux utilisateurs. Il est généré depuis `config/` et depuis le `.env` du projet :
l'adresse `.onion` est lue directement dans le conteneur `tor`.

```bat
client-package\build-client.bat
```

Le script refuse de produire un zip incohérent : il relit l'archive générée et
vérifie l'adresse, le mot de passe, le channel, le drapeau d'auto-connexion et
la présence de chaque fichier attendu.

## Ce que reçoit l'utilisateur

```
IRC-Client.zip
├── start.bat / start.ps1   ← lancement tout-en-un
├── uninstall.bat
├── README.txt              ← notice utilisateur
├── PACKAGE-INFO.txt        ← date, début de l'adresse, channel
├── profile/
│   ├── hexchat.conf        ← modèle (pseudo et port résolus au lancement)
│   └── servlist.tmpl       ← réseau pré-configuré (onion, channel, mot de passe)
└── tor/
    ├── torrc.tmpl          ← modèle (chemins absolus résolus au lancement)
    └── tor/tor.exe         ← Tor portable
```

Il extrait le zip dans un dossier où il peut écrire, double-clique `start.bat`,
choisit un pseudo au premier lancement, et c'est tout.

## Ce que fait `start.bat`

1. Vérifie que le dossier est inscriptible et retire la marque « venu
   d'Internet » des fichiers extraits (SmartScreen, antivirus)
2. Installe HexChat **via winget** s'il est absent — et pose un témoin, pour
   que la désinstallation ne retire pas un HexChat que l'utilisateur avait déjà
3. Demande le pseudo (une seule fois, mémorisé dans `nick.txt`)
4. Génère un profil HexChat **dédié** dans le dossier du package :
   `%APPDATA%\HexChat` n'est jamais touché
5. Lance Tor sur un port SOCKS libre (9251 par défaut, pas 9050, pour ne pas
   entrer en conflit avec Tor Browser ou Orbot) et **attend le vrai signal de
   disponibilité** (`Bootstrapped 100%`), en affichant la progression
6. Lance HexChat, qui se connecte automatiquement au serveur et rejoint le
   channel
7. À la fermeture de HexChat, arrête **uniquement** le Tor du package (par PID :
   un `taskkill /IM tor.exe` tuerait aussi le Tor Browser de l'utilisateur)

Le premier démarrage prend de 30 s à 3 min (construction des circuits Tor) ;
les suivants quelques secondes, le cache étant conservé dans `tor\data`.

## Points à savoir

- Le zip contient **l'adresse `.onion` et le mot de passe du serveur en clair** :
  c'est un secret, à transmettre par un canal de confiance.
- Il faut régénérer le package après un changement de mot de passe, de channel
  ou d'adresse `.onion`. `PACKAGE-INFO.txt` permet à l'utilisateur de savoir si
  le sien est encore à jour.
- `tor.exe` n'est pas signé numériquement : certains antivirus le mettent en
  quarantaine. C'est le binaire officiel du Tor Project, livré tel quel.
- Aucun fichier geoip ni transport enfichable n'est embarqué (18 Mo inutiles
  pour un simple client) : Tor affiche un avertissement `Can't open GEOIP file`,
  sans conséquence.
