<#
  Genere le fichier d'invitation a remettre aux utilisateurs, et le QR code
  de l'adresse web .onion.

  Depuis que le service cache publie aussi The Lounge (HiddenServicePort 80
  dans images/tor/torrc), faire entrer quelqu'un tient en trois lignes :
  Tor Browser, une URL .onion, un identifiant. Ce fichier les rassemble.

  Sorties (toutes dans .gitignore : elles contiennent des mots de passe) :
    invite.txt             invitation generique (sans compte nominatif)
    invite-<pseudo>.txt    invitation personnelle, avec identifiants
    invite-qr.png          QR code de l'adresse web, a photographier

  Usage :
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-invite.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-invite.ps1 -User alice -Password xxxx

  Le QR code est produit par un conteneur alpine jetable (qrencode) : rien
  a installer sur la machine. -NoQr le desactive.
#>
[CmdletBinding()]
param(
  [string]$User,
  [string]$Password,
  [switch]$NoQr
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Appel d'un programme externe sans faire planter le script.
# Avec $ErrorActionPreference = 'Stop', PowerShell 5.1 transforme la moindre
# ligne ecrite sur la sortie d'erreur par un .exe en exception
# (NativeCommandError), et « 2>$null » ne la supprime pas. Un simple
# « docker compose exec » sur un conteneur arrete faisait donc sortir
# make-invite.ps1 sur une trace rouge au lieu de son message d'erreur.
function Invoke-Native {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $args[0] @($args[1..($args.Length - 1)]) 2>&1
    return @{ Code = $LASTEXITCODE; Out = $out }
  } finally {
    $ErrorActionPreference = $old
  }
}

Push-Location $root
try {
  # --- valeurs du .env ------------------------------------------------------
  $cfg = @{}
  $envFile = Join-Path $root '.env'
  if (Test-Path -LiteralPath $envFile) {
    foreach ($line in [IO.File]::ReadAllLines($envFile, [Text.Encoding]::UTF8)) {
      if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
    }
  }
  function Cfg([string]$k, [string]$d) { if ($cfg.ContainsKey($k) -and $cfg[$k]) { return $cfg[$k] } return $d }

  $network = Cfg 'IRC_NETWORK_NAME' 'IRC'
  $channel = Cfg 'DEFAULT_CHANNEL'  '#general'
  $connect = Cfg 'CONNECT_PASSWORD' ''

  # --- adresse .onion -------------------------------------------------------
  # Lue dans le conteneur : c'est la seule source de verite.
  $r = Invoke-Native docker compose exec -T tor cat /var/lib/tor/hidden_service/hostname
  $onion = ''
  if ($r.Code -eq 0 -and $r.Out) {
    $onion = (@($r.Out) | Where-Object { "$_" -match '\.onion\s*$' } | Select-Object -First 1)
    if ($onion) { $onion = "$onion".Trim() }
  }
  if (-not $onion) {
    Write-Host '[ERREUR] Adresse .onion introuvable.'
    Write-Host '         Le conteneur tor est-il demarre ? docker compose ps'
    exit 1
  }

  $webUrl = "http://$onion/"

  # --- texte ----------------------------------------------------------------
  $sep = '=' * 70
  $sub = '-' * 70

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add($sep)
  $lines.Add(" Invitation - $network")
  $lines.Add($sep)
  $lines.Add('')
  $lines.Add(' 1. Installer Tor Browser : https://www.torproject.org/download/')
  $lines.Add('')
  $lines.Add(' 2. Y ouvrir cette adresse (copier-coller : elle est illisible a la main)')
  $lines.Add('')
  $lines.Add("      $webUrl")
  $lines.Add('')
  if ($User) {
    $lines.Add(' 3. Se connecter avec :')
    $lines.Add('')
    $lines.Add("      Identifiant  : $User")
    $lines.Add("      Mot de passe : $Password")
    $lines.Add('')
    $lines.Add('    Ce mot de passe est changeable ensuite dans The Lounge :')
    $lines.Add('    menu en haut a gauche, Settings, Change password.')
  } else {
    $lines.Add(' 3. Se connecter avec l''identifiant et le mot de passe fournis par')
    $lines.Add("    l'administrateur (scripts\add-user.bat les cree).")
  }
  $lines.Add('')
  $lines.Add("    Vous arrivez directement dans le salon $channel : rien a installer,")
  $lines.Add('    rien a telecharger, aucun serveur a saisir.')
  $lines.Add('')
  $lines.Add($sub)
  $lines.Add(' IMPORTANT : niveau de securite de Tor Browser')
  $lines.Add($sub)
  $lines.Add(' Le bouclier en haut a droite de Tor Browser doit rester sur "Standard".')
  $lines.Add(' Au niveau "Safest", Tor Browser desactive JavaScript : la page de chat')
  $lines.Add(' reste alors vide ou bloquee sur son logo, car The Lounge est une')
  $lines.Add(' application web.')
  $lines.Add('')
  $lines.Add($sub)
  $lines.Add(' Variante : client IRC classique (HexChat, WeeChat, Revolution IRC...)')
  $lines.Add($sub)
  $lines.Add(" Serveur : $onion")
  $lines.Add(' Port    : 6667, sans TLS, via un proxy SOCKS5 Tor (127.0.0.1:9050)')
  if ($connect) {
    $lines.Add(" Mot de passe du serveur : $connect")
  } else {
    $lines.Add(' Mot de passe du serveur : aucun')
  }
  $lines.Add(" Salon   : $channel")
  $lines.Add('')
  $lines.Add(' Sous Windows, l''administrateur peut fournir IRC-Client.zip : HexChat et')
  $lines.Add(' Tor deja configures, a decompresser et lancer.')
  $lines.Add('')
  $lines.Add($sub)
  $lines.Add(' Ce fichier contient des mots de passe. Transmettez-le par un canal sur,')
  $lines.Add(' et ne le publiez pas.')
  $lines.Add($sep)

  $text = ($lines -join "`r`n") + "`r`n"

  $outName = if ($User) { "invite-$User.txt" } else { 'invite.txt' }
  $outPath = Join-Path $root $outName
  [IO.File]::WriteAllText($outPath, $text, (New-Object Text.UTF8Encoding $false))
  Write-Host "[OK] $outName"

  # --- QR code de l'adresse web --------------------------------------------
  if (-not $NoQr) {
    # Toujours regenere : apres une restauration de sauvegarde, l'adresse
    # peut avoir change et un QR code perime enverrait les gens nulle part.
    $qr = Join-Path $root 'invite-qr.png'
    Remove-Item -LiteralPath $qr -ErrorAction SilentlyContinue
    $null = Invoke-Native docker run --rm -v "${root}:/out" alpine sh -c "apk add -q libqrencode-tools && qrencode -o /out/invite-qr.png -s 6 -m 2 '$webUrl'"
    if (Test-Path -LiteralPath $qr) {
      Write-Host '[OK] invite-qr.png (QR code de l''adresse web)'
    } else {
      Write-Host '[INFO] QR code non genere (pas de reseau ?). Sans importance.'
    }
  }

  Write-Output $onion
  exit 0
}
finally {
  Pop-Location
}
