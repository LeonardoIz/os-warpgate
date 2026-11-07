"""wgctl.py safeguards: no planted links followed when root reads the old initial password (audit F01),
database maintenance refused while the service runs or another one holds the lock (F08), the database
URL and its password kept out of the result (F10)."""
import contextlib
import fcntl
import importlib.util
import io
import json
import os
import sys
import tempfile

sys.dont_write_bytecode = True  # no __pycache__ inside plugin/ (it would be packaged)
spec = importlib.util.spec_from_file_location(
    'wgctl', os.environ['ROOT'] + '/plugin/src/opnsense/scripts/OPNsense/Warpgate/wgctl.py')
wgctl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wgctl)
failures = []


def expect(cond, what):
    print(('ok   ' if cond else 'FAIL ') + what)
    if not cond:
        failures.append(what)


def refused(fn, *args):
    """wgctl.need() prints the refusal and exits 0; return that message, or None if fn returned normally"""
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            fn(*args)
    except SystemExit:
        return json.loads(out.getvalue())['output']
    return None


with tempfile.TemporaryDirectory() as d:
    os.chdir(d)
    uid = os.getuid()
    open('secret', 'w').write('ROOTSECRET')
    open('ok', 'w').write('pw123\n')
    os.symlink('secret', 'symlink')
    os.link('secret', 'hardlink')
    os.mkfifo('fifo')
    expect(wgctl.read_nofollow('ok', uid) == 'pw123', 'reads a plain file')
    for name in ['symlink', 'hardlink', 'fifo']:
        try:
            wgctl.read_nofollow(name, uid)
            expect(False, f'{name} rejected')
        except OSError:
            expect(True, f'{name} rejected')

    wgctl.SUPERVISOR_PIDFILE = d + '/warpgate.pid'
    wgctl.MAINTENANCE_LOCK = d + '/maintenance.lock'
    url = 'postgres://wg:S3cr%t@db.example.com/warpgate'
    wgctl.run = lambda args, env=None, timeout=100: {'ok': False, 'output': f'error connecting to {url}: password S3cr%t rejected'}

    open(wgctl.SUPERVISOR_PIDFILE, 'w').write(str(os.getpid()))  # a live process
    msg = refused(wgctl.maintenance, ['copy-database', url], url)
    expect(msg is not None and 'stop the Warpgate service' in msg, 'refused while the service runs')

    open(wgctl.SUPERVISOR_PIDFILE, 'w').write('999999')  # stale pid
    with open(wgctl.MAINTENANCE_LOCK, 'w') as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        msg = refused(wgctl.maintenance, ['copy-database', url], url)
    expect(msg is not None and 'another database operation' in msg, 'refused while another operation holds the lock')

    result = wgctl.maintenance(['copy-database', url], url)
    expect('S3cr%t' not in result['output'] and url not in result['output'], 'URL and password removed from the output')

sys.exit(1 if failures else 0)
