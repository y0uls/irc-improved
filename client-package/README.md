# Package client HexChat

Ces scripts génèrent un zip prêt à distribuer à tes utilisateurs.  
Le zip contient un dossier de config HexChat pré-rempli avec :
- L'adresse `.onion` de ton serveur
- Le proxy SOCKS5 → `proxytor` (localhost:9050)
- Le channel par défaut et le mot de passe de connexion

## Utilisation

Lance depuis la racine du projet :

```bash
# Windows
client-package\build-client.bat

# Linux / Mac
bash client-package/build-client.sh
```

Le script génère `client-package/HexChat-IRC-Client.zip`.

## Ce que reçoit l'utilisateur

1. Il extrait le zip
2. Il copie le dossier `HexChat/` dans `%APPDATA%\` (Windows) ou `~/.config/` (Linux)
3. Il installe HexChat depuis https://hexchat.github.io
4. Il lance HexChat → le serveur est déjà là, il clique Connect

> Le proxy `localhost:9050` doit être accessible sur sa machine.
> Si l'utilisateur est sur la même machine que le serveur, c'est automatique.
> Sinon, il faut lui donner accès au port 9050 ou lui faire installer Tor séparément.
