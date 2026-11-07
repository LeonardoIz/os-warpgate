#!/bin/sh
# model validation (audit F07) with OPNsense's real MVC framework: see tests/model_validation.php
set -u
exec docker run --rm -v "$CORE/mvc:/core-mvc:ro" -v "$ROOT:/repo:ro" php:8.4-cli sh -c '
mkdir -p /usr/local/opnsense /conf /var/lib/php/tmp && groupadd wwwonly
cp -r /core-mvc /usr/local/opnsense/mvc
cp -r /repo/plugin/src/opnsense/mvc/app/models/OPNsense/Warpgate /usr/local/opnsense/mvc/app/models/OPNsense/
cat > /conf/config.xml <<XML
<?xml version="1.0"?>
<opnsense><system><webgui><port>8888</port></webgui><ssh><enabled>enabled</enabled><port>2222</port></ssh></system></opnsense>
XML
cd /usr/local/opnsense/mvc && php -d include_path=/usr/local/opnsense/mvc /repo/tests/model_validation.php > /tmp/out 2>&1
rc=$?; grep -v "^Warning\|^Deprecated\|^\$" /tmp/out; exit $rc'
