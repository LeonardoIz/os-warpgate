#!/usr/local/bin/php
<?php

/*
 * Export the trust store certificates selected in the Warpgate settings to
 * /var/db/warpgate/certs/<refid>.pem (certificate + CA chain) and <refid>.key,
 * readable by the warpgate user only. Called by rc.d/warpgate before each start.
 */

require_once('script/load_phalcon.php');

use OPNsense\Trust\Store;
use OPNsense\Warpgate\General;

$dir = '/var/db/warpgate/certs';
$mdl = new General();
$refs = [(string)$mdl->tls_certificate];
foreach (['http', 'mysql', 'postgres', 'kubernetes', 'vnc', 'rdp'] as $proto) {
    $refs[] = (string)$mdl->{$proto . '_certificate'};
}
$refs = array_merge($refs, explode(',', (string)$mdl->http_sni_certificates));
$refs = array_unique(array_filter($refs));

if (!is_dir($dir)) {
    mkdir($dir, 0700);
}
chown($dir, 'warpgate');
chmod($dir, 0700);

$written = [];
foreach ($refs as $ref) {
    $cert = Store::getCertificate($ref);
    if (!$cert || empty($cert['prv'])) {
        fwrite(STDERR, "certificate {$ref} not found or has no private key\n");
        continue;
    }
    $chain = !empty($cert['ca']['crt']) ? "\n" . $cert['ca']['crt'] : '';
    foreach (["{$ref}.pem" => $cert['crt'] . $chain, "{$ref}.key" => $cert['prv']] as $name => $data) {
        file_put_contents("{$dir}/{$name}", $data);
        chmod("{$dir}/{$name}", 0600);
        chown("{$dir}/{$name}", 'warpgate');
        $written[] = $name;
    }
}

foreach (scandir($dir) as $name) {
    if ($name[0] != '.' && !in_array($name, $written)) {
        unlink("{$dir}/{$name}");
    }
}
