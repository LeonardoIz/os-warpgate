<?php
// run by tests/test_model.sh: the plugin's model validation with OPNsense's real MVC framework.
// The OPNsense GUI port is 8888 and its SSH port 2222 in the test config.xml, to provoke port clashes.
// the framework still instantiates a Phalcon validator next to its own ("temporary dual validation")
namespace Phalcon\Filter\Validation { interface ValidatorInterface {} }
namespace Phalcon\Filter { class Validation { function add($f, $v) {} function validate($d) { return []; } } }
namespace {
// not in the php image; the framework only uses it for message text
if (!function_exists("gettext")) { function gettext($s) { return $s; } }
require_once('script/load_phalcon.php');
use OPNsense\Warpgate\General;
function check($label, $setup, $expect) {
    $m = new General();
    $setup($m);
    $got = [];
    foreach ($m->performValidation(true) as $msg) {
        $got[] = preg_replace('/^sso_providers\.provider\.[0-9a-f-]+\./', 'provider.', $msg->getField()) . ': ' . $msg->getMessage();
    }
    $ok = ($expect === []) ? $got === [] : count(array_filter($expect, fn($e) => count(array_filter($got, fn($g) => str_contains($g, $e))) > 0)) === count($expect);
    printf("%s %s\n", $ok ? 'ok  ' : 'FAIL', $label);
    if (!$ok || getenv('V')) { foreach ($got as $g) echo "       $g\n"; }
    return $ok;
}
$all = true;
$valid = function ($m) { $m->http_port = '18888'; $m->ssh_port = '12222'; };
$all &= check('defaults with free ports are valid', $valid, []);
$all &= check('default http 8888 clashes with the OPNsense GUI', fn($m) => null, ['http_port: Port already used by the OPNsense web GUI']);
$all &= check('ssh 2222 clashes with OPNsense SSH', fn($m) => $m->http_port = '18888', ['ssh_port: Port already used by the OPNsense SSH server']);
$all &= check('two listeners on one port', function ($m) use ($valid) { $valid($m); $m->mysql_enabled = '1'; $m->mysql_port = '18888'; }, ['mysql_port: Port already used by the http listener']);
$all &= check('disabled listener port is ignored', function ($m) use ($valid) { $valid($m); $m->mysql_port = '18888'; }, []);
$all &= check('privileged port', function ($m) use ($valid) { $valid($m); $m->http_port = '443'; }, ['http_port: Warpgate runs unprivileged']);
foreach (['1', '1nonsense', '30 m x'] as $bad) {
    $all &= check("duration '$bad' rejected", function ($m) use ($valid, $bad) { $valid($m); $m->http_session_max_age = $bad; }, ['http_session_max_age']);
}
$all &= check("duration '1h30m' accepted", function ($m) use ($valid) { $valid($m); $m->http_session_max_age = '1h30m'; }, []);
$sso = function ($fields) use ($valid) { return function ($m) use ($valid, $fields) {
    $valid($m); $p = $m->sso_providers->provider->Add();
    foreach (array_merge(['name' => 'x', 'client_id' => 'i', 'client_secret' => 's'], $fields) as $k => $v) { $p->$k = $v; }
}; };
$all &= check('custom OIDC without issuer', $sso(['type' => 'custom']), ['provider.issuer_url: Required']);
$all &= check('custom OIDC complete', $sso(['type' => 'custom', 'issuer_url' => 'https://idp.example.com']), []);
$all &= check('azure without tenant', $sso(['type' => 'azure']), ['provider.tenant: Required']);
$all &= check('apple without key/team', $sso(['type' => 'apple']), ['provider.key_id: Required', 'provider.team_id: Required']);
$all &= check('role mapping line without =', $sso(['type' => 'custom', 'issuer_url' => 'https://i.x', 'role_mappings' => "ops=r1\nbroken"]), ['provider.role_mappings: "broken"']);
$all &= check('unknown credential kind', $sso(['type' => 'custom', 'issuer_url' => 'https://i.x', 'credential_policy_ssh' => 'sso,magic']), ['provider.credential_policy_ssh: Unknown credential kind(s): magic']);
$all &= check('known credential kinds', $sso(['type' => 'custom', 'issuer_url' => 'https://i.x', 'credential_policy_ssh' => 'sso, publickey', 'credential_policy_http' => 'web']), []);
exit($all ? 0 : 1);
}
