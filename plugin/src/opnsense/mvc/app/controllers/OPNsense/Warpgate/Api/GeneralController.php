<?php

namespace OPNsense\Warpgate\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'general';
    protected static $internalModelClass = 'OPNsense\Warpgate\General';

    public function searchProviderAction()
    {
        return $this->searchBase('sso_providers.provider', ['enabled', 'name', 'label', 'type'], 'name');
    }

    public function getProviderAction($uuid = null)
    {
        return $this->getBase('provider', 'sso_providers.provider', $uuid);
    }

    public function addProviderAction()
    {
        return $this->addBase('provider', 'sso_providers.provider');
    }

    public function setProviderAction($uuid)
    {
        return $this->setBase('provider', 'sso_providers.provider', $uuid);
    }

    public function delProviderAction($uuid)
    {
        return $this->delBase('sso_providers.provider', $uuid);
    }

    public function toggleProviderAction($uuid, $enabled = null)
    {
        return $this->toggleBase('sso_providers.provider', $uuid, $enabled);
    }
}
