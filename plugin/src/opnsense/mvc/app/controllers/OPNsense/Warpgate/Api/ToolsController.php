<?php

namespace OPNsense\Warpgate\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

/**
 * warpgate's own CLI commands; arguments are validated again in wgctl.py
 */
class ToolsController extends ApiControllerBase
{
    private function cli($action, $args = [])
    {
        $out = (new Backend())->configdpRun('warpgate cli', array_merge([$action], $args));
        return json_decode($out ?? '', true) ?? ['ok' => false, 'output' => trim((string)$out)];
    }

    private function post($action, $fields = [])
    {
        if (!$this->request->isPost()) {
            return ['ok' => false, 'output' => 'POST required'];
        }
        $args = [];
        foreach ($fields as $field) {
            $args[] = trim((string)$this->request->getPost($field));
        }
        return $this->cli($action, $args);
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
        return $this->post('copy_database', ['url']);
    }

    public function migrateDatabaseAction()
    {
        $destructive = $this->request->getPost('destructive') == '1' ? 'destructive' : '';
        return $this->request->isPost()
            ? $this->cli('migrate_database', [trim((string)$this->request->getPost('steps')), $destructive])
            : ['ok' => false, 'output' => 'POST required'];
    }
}
