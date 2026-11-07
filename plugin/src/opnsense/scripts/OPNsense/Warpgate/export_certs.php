#!/usr/local/bin/php
<?php

/*
 * Export the trust store certificates selected in the Warpgate settings to
 * /usr/local/etc/warpgate/certs/<refid>.pem (certificate + CA chain) and <refid>.key.
 *
 * The directory is root:warpgate 0750 (setup_dirs.sh): the service can read the files but cannot create
 * links or replace anything there, so these root writes cannot be redirected. Files are written to a
 * temporary name and renamed into place, root:warpgate 0640. If a selected certificate is missing,
 * nothing is changed (the last good export stays) and the script exits 1.
 * Called by rc.d/warpgate (prepare) before each start.
 */

require_once('script/load_phalcon.php');

use OPNsense\Trust\Store;
use OPNsense\Warpgate\General;

$dir = '/usr/local/etc/warpgate/certs';
$keep = ['self-signed.pem', 'self-signed.key'];  // managed by rc.d/warpgate

// every *_certificate(s) setting (global, per listener, SNI list): no protocol list to keep in sync
$refs = [];
foreach ((new General())->iterateItems() as $name => $node) {
    if (preg_match('/_certificates?$/', $name)) {
        $refs = array_merge($refs, explode(',', (string)$node));
    }
}
$refs = array_unique(array_filter($refs));

$st = @lstat($dir);
if ($st === false || ($st['mode'] & 0170000) != 0040000 || $st['uid'] != 0) {
    fwrite(STDERR, "{$dir} must be a root-owned directory (run setup_dirs.sh)\n");
    exit(1);
}

$files = [];
foreach ($refs as $ref) {
    $cert = Store::getCertificate($ref);
    if (!$cert || empty($cert['crt']) || empty($cert['prv'])) {
        fwrite(STDERR, "certificate {$ref} not found in System: Trust or has no private key; nothing exported\n");
        exit(1);
    }
    $chain = !empty($cert['ca']['crt']) ? "\n" . $cert['ca']['crt'] : '';
    $files["{$ref}.pem"] = $cert['crt'] . $chain;
    $files["{$ref}.key"] = $cert['prv'];
}

foreach ($files as $name => $data) {
    $tmp = tempnam($dir, '.export-');
    if ($tmp === false || file_put_contents($tmp, $data) !== strlen($data) ||
        !chmod($tmp, 0640) || !chgrp($tmp, 'warpgate') || !rename($tmp, "{$dir}/{$name}")) {
        if ($tmp !== false) {
            @unlink($tmp);
        }
        fwrite(STDERR, "failed to write {$dir}/{$name}\n");
        exit(1);
    }
}

foreach (scandir($dir) as $name) {
    $stale_tmp = strpos($name, '.export-') === 0;
    if ($stale_tmp || ($name[0] != '.' && !isset($files[$name]) && !in_array($name, $keep))) {
        unlink("{$dir}/{$name}");
    }
}
