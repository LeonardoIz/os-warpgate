<?php
// minimal stand-ins for OPNsense's framework, for tests/test_export_certs.sh
namespace OPNsense\Trust {
    class Store {
        public static function getCertificate($ref) {
            return $ref === 'missing' ? false : ['crt' => "CERT-$ref", 'prv' => "KEY-$ref", 'ca' => ['crt' => 'CA']];
        }
    }
}
namespace OPNsense\Warpgate {
    class General {
        // settings come from the REFS environment variable, e.g. {"tls_certificate":"a"}
        public function iterateItems() {
            yield from (json_decode(getenv('REFS'), true) + ['http_port' => '8888']);
        }
    }
}
