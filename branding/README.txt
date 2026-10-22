======================================================================
 Personnalisation de l'interface web
======================================================================

Deposez votre logo ici, puis relancez setup.bat (ou simplement
"docker compose build webclient && docker compose up -d webclient").
L'interface web n'affichera plus la marque The Lounge.

 logo.svg        Recommande. Vectoriel : net a toutes les tailles.
                 Sert de grand logo (page de connexion, ecran de
                 chargement) ET d'icone d'onglet du navigateur.

 logo.png        Image carree, 512 x 512 recommande, fond transparent.
                 Sert aux icones qui exigent un bitmap : ecran d'accueil
                 des telephones, application installee. Sert aussi de
                 grand logo si logo.svg est absent.

 logo-dark.svg   Facultatif : variante utilisee quand l'interface est en
 logo-dark.png   theme sombre (WEB_THEME=morning). Sans ce fichier, le
                 logo principal est utilise pour les deux themes.
                 Utile si votre logo est tres sombre : il deviendrait
                 illisible sur fond sombre.

Deposez ce que vous voulez parmi ces fichiers. Sans aucun, le logo
d'origine de The Lounge est conserve.

----------------------------------------------------------------------
 Pieges frequents
----------------------------------------------------------------------
 - Un fichier exporte en JPEG puis renomme "logo.png" n'a PAS de
   transparence : le damier de l'editeur se retrouve aplati dans
   l'image. Le script le detecte et vous avertit pendant le build.
   Exportez en PNG avec canal alpha.

 - Un logo blanc sur fond transparent disparait sur le theme clair, un
   logo noir disparait sur le theme sombre. Fournissez alors la variante
   logo-dark, ou choisissez le theme adapte (WEB_THEME dans le .env).

 - Le texte affiche dans l'onglet vient de BRAND_NAME dans le .env
   (par defaut : le nom de votre reseau IRC).

 - Les navigateurs gardent les images en cache. Le script change
   automatiquement l'identifiant de cache du service worker : vos
   utilisateurs voient le nouveau logo a leur visite suivante.
   Attention toutefois : un nouveau service worker ne prend la main
   qu'une fois TOUS les onglets du site fermes. Si vous verifiez un
   changement de logo sans fermer votre onglet, vous verrez encore
   l'ancien et croirez a tort que ca n'a pas marche. Fermez l'onglet,
   ou testez en navigation privee.

 - Si vous utilisez le theme sombre (WEB_THEME=morning), sachez que la
   barre laterale est sombre dans LES DEUX themes : c'est donc toujours
   la variante logo-dark qui y est affichee, si vous en fournissez une.
