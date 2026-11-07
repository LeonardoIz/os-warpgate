"""Generated config: file modes and secret placement with OPNsense's real template engine (audit F02), the
result against warpgate's schema and `warpgate check`, and the model's duration mask against warpgate itself."""
import copy
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET

import jinja2
import jsonschema
import yaml

ROOT, WG, SCHEMA, CORE = Path(os.environ['ROOT']), os.environ['WG'], os.environ['SCHEMA'], os.environ['CORE']
sys.path.insert(0, CORE + '/service')
from modules.template import Template  # noqa: E402

MODEL = ET.parse(ROOT / 'plugin/src/opnsense/mvc/app/models/OPNsense/Warpgate/General.xml').getroot()
TEMPLATES = ROOT / 'plugin/src/opnsense/service/templates'
failures = []


def expect(cond, what):
    print(('ok   ' if cond else 'FAIL ') + what)
    if not cond:
        failures.append(what)


def mode(path):
    return stat.S_IMODE(path.stat().st_mode)


def render(settings, root):
    engine = Template(str(root))
    engine._template_dir = str(TEMPLATES) + '/'
    engine._j2_env.loader = jinja2.FileSystemLoader(str(TEMPLATES))
    engine.set_config({'OPNsense': {'Warpgate': settings}})
    return engine._generate('OPNsense/Warpgate')


def warpgate_check(config_path):
    return subprocess.run([WG, '--skip-securing-files', '--config', str(config_path), 'check'],
                          capture_output=True, text=True)


def test_templates(tmp):
    root = Path(tmp)
    # the modes setup_dirs.sh gives these directories
    for p, m in [('etc/rc.conf.d', 0o755), ('usr/local/etc/warpgate', 0o750),
                 ('usr/local/etc/warpgate/certs', 0o750), ('usr/local/etc/warpgate/private', 0o700)]:
        (root / p).mkdir(parents=True, exist_ok=True)
        (root / p).chmod(m)
    yml = root / 'usr/local/etc/warpgate/warpgate.yaml'
    env = root / 'usr/local/etc/warpgate/private/warpgate.env'
    rc = root / 'etc/rc.conf.d/warpgate'

    settings = {e.tag: e.findtext('Default') or '' for e in MODEL.find('items') if e.tag != 'sso_providers'}
    provider = {e.tag: e.findtext('Default') or '' for e in MODEL.find('items/sso_providers/provider')}
    settings.update(enabled='1', admin_token='tok_abcdefghijklmnop')
    settings['sso_providers'] = {'provider': {**provider, 'name': 'corp', 'type': 'custom', 'client_id': 'id',
                                              'client_secret': 'SSOSECRET', 'issuer_url': 'https://idp.example.com',
                                              'role_mappings': 'admins=warpgate:admin\nops=a,b'}}
    render(settings, root)
    expect(mode(yml) == 0o640, f'yaml is 0640 (got {oct(mode(yml))})')
    expect(mode(env) == 0o600, f'env file is 0600 (got {oct(mode(env))})')
    expect('tok_abcdefghijklmnop' in env.read_text(), 'admin token in the private env file')
    expect('tok_' not in rc.read_text(), 'no admin token in rc.conf.d (0644)')
    jsonschema.validate(yaml.safe_load(yml.read_text()), json.loads(Path(SCHEMA).read_text()))
    print('ok   yaml valid against the upstream schema')

    yml.chmod(0o644)  # a loose file left by anything else is fixed by the next generation
    settings['enabled'] = '0'
    render(settings, root)
    expect(mode(yml) == 0o640 and 'SSOSECRET' in yml.read_text(), 'disabled: secrets stay, file stays 0640')
    expect(mode(env) == 0o600, 'disabled: env file stays 0600')

    # `warpgate check` on what the template produced (certificate paths pointed at a test certificate)
    subprocess.run(['openssl', 'req', '-x509', '-nodes', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
                    '-days', '1', '-subj', '/CN=t', '-keyout', f'{tmp}/k.pem', '-out', f'{tmp}/c.pem'],
                   capture_output=True, check=True)
    text = (yml.read_text().replace('/usr/local/etc/warpgate/certs/self-signed.pem', f'{tmp}/c.pem')
            .replace('/usr/local/etc/warpgate/certs/self-signed.key', f'{tmp}/k.pem')
            .replace('sqlite:/var/db/warpgate/db', f'sqlite:{tmp}/db'))
    (root / 'check.yaml').write_text(text)
    r = warpgate_check(root / 'check.yaml')
    expect(r.returncode == 0, 'warpgate check accepts the generated config' + ('' if r.returncode == 0 else ': ' + r.stdout[-400:]))
    return root


def test_duration_mask(root):
    """the model's duration mask must accept exactly what warpgate accepts"""
    mask = next(e.findtext('Mask') for e in MODEL.find('items') if e.tag == 'http_session_max_age')
    regex = re.compile(mask.strip('/').replace('\\/', '/'))
    cfg = root / 'duration.yaml'
    for value in ['30m', '1day', '7days', '11months 30days 3h 50m 24s', '1h30m', '2 days', '500ms', '1.5h', '1M',
                  '10mins', '3hrs', '1', '1nonsense', '', 'm', '-1d', '1D', '1.h', '1d,2h']:
        cfg.write_text(f'database_url: "sqlite:{root}/db"\nhttp:\n  listen: "127.0.0.1:18888"\n'
                       f'  certificate: {root}/c.pem\n  key: {root}/k.pem\n  session_max_age: "{value}"\n')
        accepted = warpgate_check(cfg).returncode == 0
        expect(bool(regex.match(value)) == accepted, f'duration {value!r}: warpgate {"accepts" if accepted else "rejects"}, mask agrees')


with tempfile.TemporaryDirectory() as tmp:
    test_duration_mask(test_templates(tmp))
sys.exit(1 if failures else 0)
