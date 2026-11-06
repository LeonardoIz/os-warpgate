<?php

namespace OPNsense\Warpgate;

use OPNsense\Base\IndexController as BaseIndexController;

class IndexController extends BaseIndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Warpgate/index');
        $this->view->formSettings = $this->getForm('settings');
        $this->view->formDialogProvider = $this->getForm('dialogProvider');
        $this->view->formGridProvider = $this->getFormGrid('dialogProvider');
    }
}
