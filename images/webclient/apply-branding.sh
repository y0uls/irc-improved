#!/bin/sh
# ======================================================================
#  Applique la personnalisation de l'interface web The Lounge.
#
#  Execute en root PENDANT LE BUILD de l'image (les fichiers de
#  l'application appartiennent a root, l'application tourne ensuite sous
#  l'utilisateur node et ne peut donc rien reecrire elle-meme).
#
#  Sources, dans /branding (copie depuis le dossier branding\ du projet) :
#     logo.svg   grand logo de la page de connexion
#     logo.png   icones (onglet, ecran d'accueil mobile), et grand logo
#                si logo.svg est absent
#  Nom affiche : premier argument du script (BRAND_NAME).
#
#  Sans fichier dans /branding et sans nom fourni, le script ne touche a
#  rien : l'image reste celle d'origine.
# ======================================================================
set -e

NAME="$1"
CHANGED=0

# Racine du paquet thelounge, deduite du binaire : le chemin exact depend
# de l'installation yarn globale de l'image et peut changer d'une version
# a l'autre.
PKG=$(dirname "$(readlink -f "$(command -v thelounge)")")
PUB="$PKG/public"
IMG="$PUB/img"

if [ ! -d "$PUB" ]; then
  echo "[ERREUR] Dossier public de The Lounge introuvable (cherche : $PUB)" >&2
  exit 1
fi

INDEX="$PUB/index.html"
MANIFEST="$PUB/thelounge.webmanifest"

# ----------------------------------------------------------------------
#  Logo vectoriel : remplace toutes les variantes livrees.
#  La page de connexion utilise logo-vertical-transparent-bg.svg et sa
#  variante -inverted (theme sombre) ; les autres servent ailleurs dans
#  l'interface. On met le meme fichier partout : une seule image a
#  fournir, et aucune variante oubliee qui laisserait reapparaitre la
#  marque d'origine.
# ----------------------------------------------------------------------
if [ -f /branding/logo.svg ]; then
  for f in \
      logo-vertical-transparent-bg.svg \
      logo-vertical-transparent-bg-inverted.svg \
      logo-horizontal-transparent-bg.svg \
      logo-horizontal-transparent-bg-inverted.svg \
      logo-transparent-bg.svg \
      logo-transparent-bg-inverted.svg \
      logo-grey-bg.svg \
      icon-black-transparent-bg.svg ; do
    [ -e "$IMG/$f" ] && cp /branding/logo.svg "$IMG/$f"
  done
  CHANGED=1
  echo "[OK] logo.svg applique (page de connexion et interface)."
fi

# ----------------------------------------------------------------------
#  Logo bitmap : icones de toutes tailles + favicon.
#  index.html pointe vers favicon.ico ; on redirige ce lien vers le PNG
#  plutot que de deposer un PNG sous une extension .ico, que le serveur
#  servirait avec le mauvais type MIME.
# ----------------------------------------------------------------------
if [ -f /branding/logo.png ]; then
  for f in \
      logo-grey-bg-120x120px.png \
      logo-grey-bg-152x152px.png \
      logo-grey-bg-167x167px.png \
      logo-grey-bg-180x180px.png \
      logo-grey-bg-192x192px.png \
      logo-grey-bg-512x512px.png \
      icon-alerted-grey-bg-192x192px.png \
      icon-alerted-black-transparent-bg-72x72px.png ; do
    [ -e "$IMG/$f" ] && cp /branding/logo.png "$IMG/$f"
  done

  sed -i 's|href="favicon.ico"|href="img/logo-grey-bg-192x192px.png"|g' "$INDEX"

  # Pas de SVG fourni : on fait aussi pointer le grand logo vers le PNG,
  # sinon le navigateur recevrait du PNG annonce comme du SVG et
  # n'afficherait rien.
  CHANGED=1
  if [ ! -f /branding/logo.svg ]; then
    sed -i 's|img/logo-vertical-transparent-bg-inverted\.svg|img/logo-grey-bg-512x512px.png|g' "$INDEX"
    sed -i 's|img/logo-vertical-transparent-bg\.svg|img/logo-grey-bg-512x512px.png|g' "$INDEX"
    echo "[OK] logo.png applique (icones + page de connexion)."
  else
    echo "[OK] logo.png applique (icones)."
  fi
fi

# ----------------------------------------------------------------------
#  Nom affiche : onglet du navigateur, application installee (PWA) et
#  titre dynamique construit par le client ("#salon - <nom>").
# ----------------------------------------------------------------------
if [ -n "$NAME" ] && [ "$NAME" != "The Lounge" ]; then
  # Caracteres qui casseraient le HTML, le JSON du manifeste ou une
  # chaine JavaScript du bundle.
  SAFE=$(printf '%s' "$NAME" | tr -d '"\\<>$`' | cut -c1-40)
  if [ -n "$SAFE" ]; then
    sed -i "s|<title>The Lounge</title>|<title>$SAFE</title>|" "$INDEX"
    sed -i "s|\"The Lounge\"|\"$SAFE\"|g" "$MANIFEST"
    sed -i "s|Self-hosted web IRC client|Messagerie privee|" "$MANIFEST"

    # Le titre affiche pendant l'utilisation est une chaine du bundle
    # client (minifie) et du service worker : on remplace le litteral,
    # ce qui laisse le JavaScript valide.
    for f in "$PUB"/assets/*.js "$PUB"/service-worker.js ; do
      [ -e "$f" ] && sed -i "s|\"The Lounge\"|\"$SAFE\"|g" "$f"
    done
    CHANGED=1
    echo "[OK] Nom affiche : $SAFE"
  fi
fi

# ----------------------------------------------------------------------
#  Cache des navigateurs.
#
#  The Lounge installe un service worker qui garde les images en cache et
#  les ressert meme apres remplacement cote serveur : sans cette etape,
#  les personnes ayant deja ouvert le site continueraient a voir l'ancien
#  logo, parfois pendant des jours. Le script du service worker supprime
#  tous les caches dont le nom differe du sien ; il suffit donc de changer
#  ce nom pour que tout soit recharge proprement a la visite suivante.
#
#  Le nom derive du contenu applique : il ne change que si le logo ou le
#  nom changent vraiment.
# ----------------------------------------------------------------------
if [ "$CHANGED" = "1" ]; then
  SW="$PUB/service-worker.js"
  if [ -f "$SW" ]; then
    SIG=$( { cat /branding/logo.svg /branding/logo.png 2>/dev/null; printf '%s' "$NAME"; }            | md5sum | cut -c1-10 )
    sed -i "s|^const cacheName = \"[^\"]*\";|const cacheName = \"brand$SIG\";|" "$SW"
    echo "[OK] Cache navigateur invalide (service worker : brand$SIG)."
  fi
fi

exit 0
