<?php

namespace OPNsense\Warpgate\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

/**
 * warpgate's own CLI commands; arguments are validated again in wgctl.py
 */
class ToolsController extends ApiControllerBase
{
    /* copy/migrate may take wgctl.py's LONG_TIMEOUT (600 s); wait a little longer than that */
    const LONG_TIMEOUT = 660;

    private function cli($action, $args = [], $timeout = 120)
    {
        $out = (new Backend())->configdpRun('warpgate cli', array_merge([$action], $args), false, $timeout);
        // configd's own errors may repeat the parameters (a database URL with its password): never echo them
        return json_decode($out ?? '', true) ?? ['ok' => false, 'output' => gettext('No result from the Warpgate command, see the backend log.')];
    }

    private function post($action, $fields = [], $timeout = 120)
    {
        if (!$this->request->isPost()) {
            return ['ok' => false, 'output' => 'POST required'];
        }
        $args = [];
        foreach ($fields as $field) {
            $args[] = trim((string)$this->request->getPost($field));
        }
        return $this->cli($action, $args, $timeout);
    }

    public function versionAction()
    {
        return $this->cli('version');
    }

    public function checkAction()
    {
        return $this->cli('check');
    }

    public function clientKeysAction()
    {
        return $this->cli('client_keys');
    }

    public function initialPasswordAction()
    {
        return $this->cli('initial_password');
    }

    public function dismissInitialPasswordAction()
    {
        return $this->post('dismiss_initial_password');
    }

    public function recoverAccessAction()
    {
        return $this->post('recover_access', ['username']);
    }

    public function createUserAction()
    {
        return $this->post('create_user', ['username', 'role']);
    }

    public function copyDatabaseAction()
    {
        return $this->post('copy_database', ['url'], self::LONG_TIMEOUT);
    }

    public function migrateDatabaseAction()
    {
        $destructive = $this->request->getPost('destructive') == '1' ? 'destructive' : '';
        return $this->request->isPost()
            ? $this->cli('migrate_database', [trim((string)$this->request->getPost('steps')), $destructive], self::LONG_TIMEOUT)
            : ['ok' => false, 'output' => 'POST required'];
    }
}
