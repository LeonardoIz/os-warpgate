<?php

namespace OPNsense\Warpgate;

use OPNsense\Base\BaseModel;
use OPNsense\Base\Messages\Message;
use OPNsense\Core\Config;

class General extends BaseModel
{
    /* credential kinds warpgate understands (warpgate-common/src/auth/cred.rs) */
    const CREDENTIAL_KINDS = ['password', 'publickey', 'certificate', 'otp', 'sso', 'web'];

    /* fields each SSO provider type requires, beyond name/client id/secret */
    const SSO_REQUIRED = [
        'custom' => ['issuer_url', 'scopes'],
        'azure' => ['tenant'],
        'apple' => ['key_id', 'team_id'],
        'google' => [],
    ];

    /**
     * semantic checks warpgate would otherwise only report when it fails to start
     */
    public function performValidation($validateFullModel = false)
    {
        $messages = parent::performValidation($validateFullModel);
        $this->validatePorts($messages);

        foreach ($this->sso_providers->provider->iterateItems() as $provider) {
            // like core models: unchanged entries (e.g. saved by an older version) must not block other edits
            if (!$validateFullModel && !$provider->isFieldChanged()) {
                continue;
            }
            $ref = $provider->__reference;
            $type = (string)$provider->type;
            foreach (self::SSO_REQUIRED[$type] ?? [] as $field) {
                if ((string)$provider->$field === '') {
                    $messages->appendMessage(new Message(gettext('Required for this provider type.'), "{$ref}.{$field}"));
                }
            }
            foreach (['role_mappings', 'admin_role_mappings'] as $field) {
                foreach (preg_split('/\R/', (string)$provider->$field) as $line) {
                    if (trim($line) !== '' && !preg_match('/^[^=]+=\s*\S/', $line)) {
                        $messages->appendMessage(new Message(
                            sprintf(gettext('"%s" is not a group=role1,role2 mapping.'), trim($line)),
                            "{$ref}.{$field}"
                        ));
                    }
                }
            }
            foreach (['http', 'ssh', 'mysql', 'postgres'] as $proto) {
                $field = "credential_policy_{$proto}";
                $kinds = array_filter(array_map('trim', explode(',', (string)$provider->$field)), 'strlen');
                $unknown = array_diff($kinds, self::CREDENTIAL_KINDS);
                if ($unknown) {
                    $messages->appendMessage(new Message(sprintf(
                        gettext('Unknown credential kind(s): %s. Valid: %s.'),
                        implode(', ', $unknown),
                        implode(', ', self::CREDENTIAL_KINDS)
                    ), "{$ref}.{$field}"));
                }
            }
        }
        return $messages;
    }

    /**
     * enabled listeners: unprivileged, distinct, not taken by the OPNsense web GUI or SSH
     */
    private function validatePorts($messages)
    {
        $listeners = ['http' => true];
        foreach (['ssh', 'mysql', 'postgres', 'kubernetes', 'vnc', 'rdp'] as $proto) {
            $listeners[$proto] = (string)$this->{$proto . '_enabled'} == '1';
        }

        $system = Config::getInstance()->object()->system;
        $taken = [];
        if (!empty((string)$system->webgui->port)) {
            $taken[(string)$system->webgui->port] = gettext('the OPNsense web GUI');
        }
        if (!empty((string)$system->ssh->enabled) && !empty((string)$system->ssh->port)) {
            $taken[(string)$system->ssh->port] = gettext('the OPNsense SSH server');
        }

        $used = [];
        foreach (array_keys(array_filter($listeners)) as $proto) {
            $field = "{$proto}_port";
            $port = (string)$this->$field;
            if ($port === '') {
                continue;
            }
            if ((int)$port < 1024) {
                $messages->appendMessage(new Message(gettext(
                    'Warpgate runs unprivileged and cannot bind ports below 1024; use a port forward or reverse proxy instead.'
                ), $field));
            } elseif (isset($taken[$port])) {
                $messages->appendMessage(new Message(sprintf(gettext('Port already used by %s.'), $taken[$port]), $field));
            } elseif (isset($used[$port])) {
                $messages->appendMessage(new Message(sprintf(gettext('Port already used by the %s listener.'), $used[$port]), $field));
            }
            $used[$port] = $proto;
        }
    }
}
