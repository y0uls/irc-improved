// ======================================================================
//  Pre-renseigne le reseau IRC dans le compte The Lounge qui vient d'etre
//  cree, pour que l'utilisateur n'ait rien d'autre a faire que se
//  connecter avec son identifiant.
//
//  Sans ce fichier, The Lounge affiche son formulaire « Connect » apres
//  la premiere connexion : meme pre-rempli par les options defaults.*,
//  il reste un ecran de plus, et le pseudo IRC y serait aleatoire
//  (defaults.nick = thelounge%%).
//
//  Le format attendu est celui que The Lounge ecrit lui-meme :
//  client.js -> networkFromConfig() complete tout le reste (lodash.defaults),
//  et « join » est la cle historique des channels a rejoindre, toujours
//  acceptee en 4.5.
//
//  Lance DANS le conteneur webclient :
//      docker compose exec -T -e TL_... webclient sh -c "cat > /tmp/p.js && node /tmp/p.js" < scripts\provision-network.js
//  Le conteneur doit etre redemarre ensuite : The Lounge ne relit les
//  reseaux d'un compte deja charge qu'au demarrage (clientManager.loadUser
//  ne reprend que le mot de passe d'un client deja en memoire).
// ======================================================================
"use strict";

const fs = require("fs");

const name = process.env.TL_USER;
const file = "/var/opt/thelounge/users/" + name + ".json";

const user = JSON.parse(fs.readFileSync(file, "utf8"));

user.networks = [
    {
        name: process.env.TL_NETWORK || "IRC",
        // host / port / tls sont de toute facon forces par lockNetwork,
        // mais doivent correspondre a defaults.host sinon The Lounge
        // refuse le reseau (« The hostname you specified is not allowed »).
        host: "irc",
        port: 6667,
        tls: false,
        rejectUnauthorized: false,
        password: process.env.TL_PASSWORD || "",
        nick: name,
        username: name,
        realname: name,
        join: process.env.TL_CHANNEL || "",
    },
];

fs.writeFileSync(file, JSON.stringify(user, null, "\t"), {mode: 0o600});
console.log("[OK] Reseau pre-renseigne pour " + name);
