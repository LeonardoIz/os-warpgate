<?php

function warpgate_services()
{
    $services = [];

    if ((string)(new \OPNsense\Warpgate\General())->enabled == '1') {
        $services[] = [
            'description' => gettext('Warpgate bastion'),
            'configd' => [
                'restart' => ['warpgate restart'],
                'start' => ['warpgate start'],
                'stop' => ['warpgate stop'],
            ],
            'name' => 'warpgate',
            // warpgate itself, not daemon(8): the supervisor stays alive while it keeps failing to start
            'pidfile' => '/var/run/warpgate.child.pid',
        ];
    }

    return $services;
}

/**
 * lets remote syslog destinations select warpgate; the local log file comes from the Syslog/local template
 */
function warpgate_syslog()
{
    return ['warpgate' => ['facility' => ['warpgate']]];
}
