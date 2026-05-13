#!/bin/sh
set -e

CONF=/etc/inspircd/inspircd.conf

sed -i "s|IRC_SERVER_NAME_VAR|${IRC_SERVER_NAME:-irc.local}|g"       "$CONF"
sed -i "s|IRC_DESCRIPTION_VAR|${IRC_DESCRIPTION:-IRC Server}|g"      "$CONF"
sed -i "s|IRC_NETWORK_NAME_VAR|${IRC_NETWORK_NAME:-LocalNet}|g"      "$CONF"
sed -i "s|ADMIN_EMAIL_VAR|${ADMIN_EMAIL:-admin@localhost}|g"          "$CONF"
sed -i "s|MAX_USERS_VAR|${MAX_USERS:-100}|g"                          "$CONF"
sed -i "s|OPER_PASSWORD_HASH_VAR|${OPER_PASSWORD_HASH:-changeme}|g"  "$CONF"

exec inspircd --nofork --runasroot
