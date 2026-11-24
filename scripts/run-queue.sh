#!/bin/bash
# Process Idno's pending background events once, then exit. Run it from cron every minute.
#
# A lock stops two runs from overlapping if one takes longer than a minute (a post with many
# slow links can), which would otherwise dispatch the same events twice.
#
# Edit the five settings below. Nothing else needs changing.

WEB_ROOT="/home/youraccount/public_html"   # folder your web server serves the site from
SUBDIR="blog"                              # folder of the Idno install inside WEB_ROOT; leave empty ("") if Idno is at the domain root
DOMAIN="example.com"                       # your site's domain, no https://
PHP_BIN="/usr/bin/php"                     # run `which php` to find it
HELPER="$HOME/subdir-prepend.php"          # where you put subdir-prepend.php (only used when SUBDIR is set)

LOCK="$HOME/idno-queue.lock"
exec 9>"$LOCK"
flock -n 9 || exit 0                       # a previous run is still going

cd "$WEB_ROOT" || exit 1

# HTTPS=on makes Idno build https:// addresses; IDNO_PORT=443 keeps ":443" out of them.
# Remove both lines for a site served over plain http.
export HTTPS=on IDNO_DOMAIN="$DOMAIN" IDNO_PORT=443

if [ -n "$SUBDIR" ]; then
    ASYNC_WM_SUBDIR="$SUBDIR" "$PHP_BIN" -d auto_prepend_file="$HELPER" "$SUBDIR/idno.php" service-event-queue --once >/dev/null 2>&1
else
    "$PHP_BIN" idno.php service-event-queue --once >/dev/null 2>&1
fi
