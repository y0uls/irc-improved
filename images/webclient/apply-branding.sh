#!/bin/sh
# ======================================================================
#  Applique la personnalisation de l'interface web The Lounge.
#
#  Execute en root PENDANT LE BUILD de l'image (les fichiers de
#  l'application appartiennent a root, l'application tourne ensuite sous
#  l'utilisateur node et ne peut donc rien reecrire elle-meme).
#
#  Sources, dans /branding (copie depuis le dossier branding\ du projet) :
#     logo.png / logo.svg            logo principal
#     logo-dark.png / logo-dark.svg  variante pour le theme sombre
#                                    (facultative : a defaut, le logo
#                                    principal est utilise partout)
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

# Variantes utilisees par l'interface. Le choix ne depend PAS seulement
# du theme : il se fait surface par surface, en CSS.
#  - variante normale     : fond clair (page de connexion et ecran de
#                           chargement en theme clair) ;
#  - variante "-inverted" : fond sombre, c'est-a-dire la barre laterale
#                           QUEL QUE SOIT le theme (elle est sombre dans
#                           les deux), plus la page de connexion et
#                           l'ecran de chargement en theme sombre.
# C'est donc cette seconde liste qu'alimente logo-dark : un logo lisible
# sur fond sombre.
SVG_CLAIR="logo-vertical-transparent-bg.svg logo-horizontal-transparent-bg.svg logo-transparent-bg.svg logo-grey-bg.svg icon-black-transparent-bg.svg"
SVG_SOMBRE="logo-vertical-transparent-bg-inverted.svg logo-horizontal-transparent-bg-inverted.svg logo-transparent-bg-inverted.svg"

# ----------------------------------------------------------------------
#  Fabrique un SVG a partir d'une image bitmap.
#
#  Pourquoi : la page de CONNEXION est rendue par l'application Vue, dont
#  le bundle demande un fichier .svg. Tant que ce .svg n'est pas remplace,
#  le logo d'origine reste affiche la, meme si toutes les icones PNG ont
#  ete changees (c'est exactement le symptome "l'ecran de chargement
#  change mais pas la page de connexion").
#  Deposer le bitmap sous une extension .svg ne marche pas : le serveur
#  l'annoncerait en image/svg+xml et le navigateur n'afficherait rien.
#  On enveloppe donc l'image dans un SVG, a sa taille reelle.
#
#  $1 = image source   $2 = fichier SVG a produire
#  Renvoie 1 si le format de l'image n'est pas reconnu.
# ----------------------------------------------------------------------
wrap_bitmap() {
  _src="$1"; _dst="$2"
  _W=0; _H=0; _MIME=""
  # Le format est determine par les octets du fichier, jamais par son
  # extension : un fichier exporte en JPEG puis renomme "logo.png" est un
  # cas frequent, et il n'a par construction aucune transparence.
  eval "$(SRC="$_src" node -e '
    const fs = require("fs");
    const b = fs.readFileSync(process.env.SRC);
    let mime = "", w = 0, h = 0;
    if (b.length > 24 && b[0] === 0x89 && b.toString("ascii", 12, 16) === "IHDR") {
      mime = "image/png"; w = b.readUInt32BE(16); h = b.readUInt32BE(20);
    } else if (b.length > 4 && b[0] === 0xFF && b[1] === 0xD8) {
      mime = "image/jpeg";
      // Parcours des marqueurs JPEG jusqu a un segment SOF, qui porte les
      // dimensions (C4, C8 et CC ne sont pas des SOF).
      let i = 2;
      while (i + 9 < b.length) {
        if (b[i] !== 0xFF) { i++; continue; }
        const m = b[i + 1];
        if (m >= 0xC0 && m <= 0xCF && m !== 0xC4 && m !== 0xC8 && m !== 0xCC) {
          h = b.readUInt16BE(i + 5); w = b.readUInt16BE(i + 7); break;
        }
        i += 2 + b.readUInt16BE(i + 2);
      }
    }
    if (mime && w > 0 && h > 0) { console.log("_MIME=" + mime + "; _W=" + w + "; _H=" + h); }
  ' 2>/dev/null)"

  [ "$_W" -gt 0 ] && [ "$_H" -gt 0 ] || return 1

  _B64=$(base64 -w 0 "$_src" 2>/dev/null || base64 "$_src" | tr -d '\n')
  # Un seul attribut href (SVG 2) : xlink:href, la forme historique,
  # obligeait a ecrire l'image en base64 DEUX fois dans le fichier,
  # soit le double de poids a telecharger a travers Tor pour chaque
  # logo. preserveAspectRatio evite de deformer un logo non carre.
  {
    printf '%s' "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\""
    printf '%s' " viewBox=\"0 0 $_W $_H\" width=\"$_W\" height=\"$_H\">"
    printf '%s' "<image x=\"0\" y=\"0\" width=\"$_W\" height=\"$_H\" preserveAspectRatio=\"xMidYMid meet\""
    printf '%s' " href=\"data:$_MIME;base64,$_B64\"/>"
    printf '%s\n' "</svg>"
  } > "$_dst"
  echo "$_MIME ${_W}x${_H}"
}

# Installe une image (SVG tel quel, ou bitmap enveloppe) sur une liste de
# variantes.  $1 = source   $2 = liste de fichiers cibles
installer_logo() {
  _source="$1"; _cibles="$2"
  case "$_source" in
    *.svg)
      # Un SVG exporte en width="100%" height="100%" n'a pas de taille
      # intrinseque : selon le conteneur, le navigateur le rend alors a
      # une taille par defaut, voire pas du tout. On remplace ces valeurs
      # par les dimensions du viewBox, qui donnent une taille propre tout
      # en restant redimensionnables.
      _tmp="$IMG/.brand-source.svg"
      cp "$_source" "$_tmp"
      # Extraction sans reference de groupe : plus simple a relire,
      # et insensible aux surprises d'echappement.
      _vb=$(grep -o 'viewBox="[^"]*"' "$_tmp" | head -1 | tr -d '"' | cut -d= -f2)
      _vw=$(printf '%s' "$_vb" | cut -d' ' -f3)
      _vh=$(printf '%s' "$_vb" | cut -d' ' -f4)
      if [ -n "$_vw" ] && [ -n "$_vh" ]; then
        sed -i "s|width=\"100%\"|width=\"$_vw\"|; s|height=\"100%\"|height=\"$_vh\"|" "$_tmp"
      fi
      for _f in $_cibles; do
        [ -e "$IMG/$_f" ] && cp "$_tmp" "$IMG/$_f"
      done
      rm -f "$_tmp"
      echo "svg${_vw:+ ${_vw}x${_vh}}"
      ;;
    *)
      # L'image The Lounge n'a pas de /tmp : on ecrit le fichier
      # intermediaire dans le dossier des images, puis on le supprime.
      _wrap="$IMG/.brand-wrapper.svg"
      if _info=$(wrap_bitmap "$_source" "$_wrap"); then
        for _f in $_cibles; do
          [ -e "$IMG/$_f" ] && cp "$_wrap" "$IMG/$_f"
        done
        rm -f "$_wrap"
        echo "$_info"
      else
        rm -f "$_wrap"
        return 1
      fi
      ;;
  esac
}

# Avertit une seule fois si le fichier annonce .png est en fait un JPEG :
# ce format ne peut pas porter de transparence, et le damier de l'editeur
# se retrouve alors aplati dans l'image.
avertir_si_jpeg() {
  [ -f "$1" ] || return 0
  case "$1" in *.svg) return 0 ;; esac
  if [ "$(od -An -N2 -tx1 "$1" | tr -d ' 
')" = "ffd8" ]; then
    echo "[ATTENTION] $(basename "$1") est en realite un JPEG." >&2
    echo "            Le JPEG ne gere pas la transparence : si le logo en" >&2
    echo "            avait, elle a ete aplatie a l'export (souvent en damier)." >&2
    echo "            Re-exportez en PNG avec canal alpha pour un fond propre." >&2
  fi
}

# Premier fichier existant parmi ceux passes en argument.
premier_existant() {
  for _c in "$@"; do
    [ -f "$_c" ] && { echo "$_c"; return 0; }
  done
  return 1
}

# ----------------------------------------------------------------------
#  Logo principal (theme clair) et variante sombre.
#  Le SVG est prioritaire sur le bitmap : il reste net a toutes les
#  tailles.
# ----------------------------------------------------------------------
LOGO=$(premier_existant /branding/logo.svg /branding/logo.png /branding/logo.jpg /branding/logo.jpeg || true)
LOGO_DARK=$(premier_existant /branding/logo-dark.svg /branding/logo-dark.png /branding/logo-dark.jpg /branding/logo-dark.jpeg || true)

if [ -n "$LOGO" ]; then
  avertir_si_jpeg "$LOGO"
  [ "$LOGO_DARK" != "$LOGO" ] && avertir_si_jpeg "$LOGO_DARK"
  if INFO=$(installer_logo "$LOGO" "$SVG_CLAIR"); then
    CHANGED=1
    echo "[OK] Logo applique ($(basename "$LOGO"), $INFO)."
  else
    echo "[ATTENTION] Format de $(basename "$LOGO") non reconnu (ni PNG, ni JPEG, ni SVG)." >&2
    echo "            Le logo d'origine est conserve." >&2
  fi

  # Theme sombre : variante dediee si elle est fournie, sinon le meme logo.
  DARK_SRC="$LOGO"
  DARK_LABEL="le meme logo"
  if [ -n "$LOGO_DARK" ]; then
    DARK_SRC="$LOGO_DARK"
    DARK_LABEL="$(basename "$LOGO_DARK")"
  fi
  if installer_logo "$DARK_SRC" "$SVG_SOMBRE" >/dev/null; then
    CHANGED=1
    echo "[OK] Theme sombre : $DARK_LABEL."
  fi
fi

# ----------------------------------------------------------------------
#  Icones bitmap : onglet du navigateur, ecran d'accueil des telephones,
#  notification avec mention non lue.
#  index.html pointe vers favicon.ico ; on redirige ce lien vers le PNG
#  plutot que de deposer un bitmap sous une extension .ico, que le serveur
#  servirait avec le mauvais type MIME.
#  L'ecran de chargement, lui, est du HTML statique : il suffit d'y faire
#  pointer les <img> vers le bitmap.
# ----------------------------------------------------------------------
ICONE=$(premier_existant /branding/logo.png /branding/logo.jpg /branding/logo.jpeg || true)
if [ -n "$ICONE" ]; then
  for f in \
      logo-grey-bg-120x120px.png \
      logo-grey-bg-152x152px.png \
      logo-grey-bg-167x167px.png \
      logo-grey-bg-180x180px.png \
      logo-grey-bg-192x192px.png \
      logo-grey-bg-512x512px.png \
      icon-alerted-grey-bg-192x192px.png \
      icon-alerted-black-transparent-bg-72x72px.png ; do
    [ -e "$IMG/$f" ] && cp "$ICONE" "$IMG/$f"
  done

  sed -i 's|href="favicon.ico"|href="img/logo-grey-bg-192x192px.png"|g' "$INDEX"
  # Ecran de chargement : deux <img>, l'une affichee sur fond clair,
  # l'autre sur fond sombre. Si une variante sombre bitmap est fournie,
  # on la sert a la seconde ; sinon les deux pointent vers la meme.
  INV_PNG=img/logo-grey-bg-512x512px.png
  if [ -n "$LOGO_DARK" ]; then
    case "$LOGO_DARK" in
      *.png|*.jpg|*.jpeg)
        cp "$LOGO_DARK" "$IMG/brand-inverted.png"
        INV_PNG=img/brand-inverted.png
        ;;
    esac
  fi
  sed -i "s|img/logo-vertical-transparent-bg-inverted[.]svg|$INV_PNG|g" "$INDEX"
  sed -i 's|img/logo-vertical-transparent-bg\.svg|img/logo-grey-bg-512x512px.png|g' "$INDEX"
  # Le type declare suivait encore l'ancienne icone .ico.
  sed -i 's|type="image/x-icon"|type="image/png"|' "$INDEX"
  CHANGED=1
  echo "[OK] Icones et ecran de chargement : $(basename "$ICONE")."
fi

# ----------------------------------------------------------------------
#  Icone de l'onglet quand un SVG est disponible.
#  Les navigateurs acceptent une icone au format SVG : l'onglet affiche
#  alors le logo vectoriel, net a toutes les resolutions, sans dependre
#  d'un export PNG. Les icones de l'ecran d'accueil des telephones, elles,
#  doivent rester en PNG (le manifeste l'exige).
# ----------------------------------------------------------------------
if [ -n "$LOGO" ] && [ "${LOGO##*.}" = "svg" ]; then
  sed -i 's|href="img/logo-grey-bg-192x192px.png"|type="image/svg+xml" href="img/logo-vertical-transparent-bg.svg"|' "$INDEX"
  sed -i 's|href="favicon.ico"|type="image/svg+xml" href="img/logo-vertical-transparent-bg.svg"|' "$INDEX"
  CHANGED=1
  echo "[OK] Icone d'onglet : logo vectoriel."
fi

# ----------------------------------------------------------------------
#  Nom affiche : onglet du navigateur, application installee (PWA) et
#  titre dynamique construit par le client ("#salon - <nom>").
# ----------------------------------------------------------------------
if [ -n "$NAME" ] && [ "$NAME" != "The Lounge" ]; then
  # Caracteres qui casseraient le HTML, le JSON du manifeste ou une
  # chaine JavaScript du bundle.
  # Caracteres retires : ceux qui casseraient le HTML, le JSON du
  # manifeste ou une chaine JavaScript, PLUS le | (delimiteur de tous
  # les sed de ce script : un nom comme "Chez Jo | IRC" faisait
  # echouer le build en entier) et le & (sed le remplace par le texte
  # trouve, ce qui reinjectait silencieusement "The Lounge").
  SAFE=$(printf '%s' "$NAME" | tr -d '"\<>$`|&' | cut -c1-40)
  if [ -n "$SAFE" ]; then
    # Remplacement du nom en clair, sans se soucier du contexte : le
    # bundle Vue est minifie et ses chaines sont delimitees par des
    # backticks (`The Lounge`), le manifeste par des guillemets, le HTML
    # par des balises. Cibler les guillemets ne remplacait donc RIEN dans
    # le bundle : la page d'aide, la banniere de mise a jour, les
    # reglages et le texte affiche sans JavaScript gardaient la marque
    # d'origine.
    # Les URL (thelounge.chat, github.com/thelounge) ne contiennent ni
    # espace ni majuscule : elles ne sont pas touchees, et les liens vers
    # le projet amont restent fonctionnels.
    NB=0
    for f in "$INDEX" "$MANIFEST" "$PUB"/assets/*.js "$PUB"/service-worker.js ; do
      [ -e "$f" ] || continue
      NB=$((NB + $(grep -o "The Lounge" "$f" 2>/dev/null | wc -l)))
      sed -i "s|The Lounge|$SAFE|g" "$f"
    done
    sed -i "s|Self-hosted web IRC client|Messagerie privee|" "$MANIFEST"
    # "maskable" autorise Android a rogner environ 20 % du bord pour
    # mettre l'icone a la forme du systeme : un logo qui occupe tout
    # son carre y perd ses bords. On ne garde que "any".
    sed -i 's|"purpose": "maskable any"|"purpose": "any"|g' "$MANIFEST"
    CHANGED=1
    echo "[OK] Nom affiche : $SAFE ($NB occurrences remplacees)."
  fi
fi

# ----------------------------------------------------------------------
#  Icones restantes : favicon servi a la racine du site et variante
#  "mention non lue" (l'onglet bascule dessus des qu'un message vous
#  mentionne - sans cette etape il repassait au logo d'origine a ce
#  moment precis).
#
#  Les .ico sont remplaces par le bitmap : les navigateurs identifient le
#  format d'une icone par son contenu, pas par son extension.
#  Contrepartie assumee : la pastille rouge qui distinguait l'etat
#  "mention" disparait ; le compteur du titre de l'onglet, "(2) #salon",
#  prend le relais.
#
#  mask-icon (onglet epingle dans Safari) exige un SVG vectoriel
#  monochrome : un SVG qui enveloppe une image matricielle n'en est pas
#  un, et la couleur declaree reste celle de The Lounge. On retire la
#  ligne, Safari se rabat alors sur le favicon.
# ----------------------------------------------------------------------
if [ -n "$ICONE" ]; then
  for f in "$PUB/favicon.ico" "$IMG/favicon-alerted.ico" ; do
    [ -e "$f" ] && cp "$ICONE" "$f"
  done
  CHANGED=1
  echo "[OK] Favicon et icone de mention remplaces."
fi
if [ -n "$LOGO" ]; then
  sed -i '/rel="mask-icon"/d' "$INDEX"
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
    # La signature porte sur les fichiers REELLEMENT installes : une
    # correction du script seul changeait sinon le resultat servi sans
    # changer la signature, et les navigateurs gardaient leur cache.
    SIG=$( cat "$INDEX" "$MANIFEST" "$IMG"/logo-vertical-transparent-bg*.svg "$IMG"/logo-grey-bg-512x512px.png 2>/dev/null | md5sum | cut -c1-10 )
    sed -i "s|^const cacheName = \"[^\"]*\";|const cacheName = \"brand$SIG\";|" "$SW"
    echo "[OK] Cache navigateur invalide (service worker : brand$SIG)."
  fi
fi

exit 0
