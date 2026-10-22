======================================================================
 Personnalisation de l'interface web
======================================================================

Deposez ici votre logo, puis relancez setup.bat : l'interface web
n'affichera plus la marque The Lounge.

 logo.png   Image carree, 512 x 512 recommande, fond transparent ou
            colore. Sert d'icone (onglet du navigateur, ecran d'accueil
            du telephone) et, si logo.svg est absent, de logo sur la
            page de connexion.

 logo.svg   Version vectorielle, utilisee en priorite pour le grand
            logo de la page de connexion et de l'ecran de chargement
            (elle reste nette a toutes les tailles).

Deposez l'un, l'autre, ou les deux. Sans fichier ici, le logo d'origine
de The Lounge est conserve.

Le texte affiche dans l'onglet du navigateur vient de BRAND_NAME dans
le .env (par defaut : le nom de votre reseau IRC).

Apres avoir change un fichier :
    docker compose build webclient
    docker compose up -d webclient
(ou simplement relancer setup.bat)
