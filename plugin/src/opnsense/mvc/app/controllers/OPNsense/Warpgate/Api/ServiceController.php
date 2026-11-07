<?php

namespace OPNsense\Warpgate\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Warpgate\General';
    protected static $internalServiceEnabled = 'enabled';
    protected static $internalServiceTemplate = 'OPNsense/Warpgate';
    protected static $internalServiceName = 'warpgate';

    /**
     * validate the new configuration with `warpgate check` before stopping anything:
     * a rejected configuration leaves the running instance alone and is reported to the GUI
     */
    public function reconfigureAction()
    {
        if (!$this->request->isPost() || !$this->serviceEnabled()) {
            return parent::reconfigureAction();
        }
        $backend = new Backend();
        if (trim($backend->configdpRun('template reload', [static::$internalServiceTemplate])) !== 'OK') {
            return ['status' => 'failed', 'status_msg' => gettext('Template generation failed, see the backend log.')];
        }
        $prepared = trim((string)$backend->configdRun('warpgate prepare'));
        if (substr($prepared, -2) !== 'OK') {
            return ['status' => 'failed', 'status_msg' => gettext('Preparing Warpgate failed:') . "\n" . $prepared];
        }
        $check = json_decode((string)$backend->configdpRun('warpgate cli', ['check']), true);
        if (empty($check['ok'])) {
            return ['status' => 'failed', 'status_msg' =>
                gettext('Warpgate rejected the configuration; the running service was left unchanged.') .
                "\n" . ($check['output'] ?? '')];
        }
        return parent::reconfigureAction();
    }
}
