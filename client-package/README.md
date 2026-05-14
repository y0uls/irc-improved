# Package client HexChat

Ces scripts génèrent un zip prêt à distribuer à tes utilisateurs.  
Le zip contient un dossier de config HexChat pré-rempli avec :
- L'adresse `.onion` de ton serveur
- Le proxy SOCKS5 → `tor` (localhost:9050)
- Le channel par défaut et le mot de passe de connexion

## Utilisation

Lance depuis la racine du projet :

```bash
# Windows
client-package\build-client.bat
```

Le script génère `client-package/IRC-Client.zip`.

## Ce que reçoit l'utilisateur

1. Il extrait le zip `IRC-Client.zip`.
2. Il execute "start.bat".
3. Une fois l'installation de HexChat finie, il ne faut pas l'executer tout de suite mais finir l'installation et laisser le script l'exectuer.
4. Ce connecter !
