#!/usr/local/bin/python3
"""Run warpgate's own CLI commands for the OPNsense GUI (via configd), as the warpgate user.

wgctl.py ACTION [ARG ...] -> prints one JSON object: {"ok": bool, "output": str, ["password": str]}
Passwords are generated here and never passed on a command line; arguments are validated before use.
"""
import fcntl
import json
import os
import pty
import pwd
import re
import secrets
import select
import subprocess
import stat
import sys
import time

BIN = '/usr/local/bin/warpgate'
CONFIG = '/usr/local/etc/warpgate/warpgate.yaml'
INITIAL_PASSWORD = '/usr/local/etc/warpgate/private/initial-admin-password'
# earlier versions kept it in the service's own directory: read without following links
LEGACY_INITIAL_PASSWORD = '/var/db/warpgate/initial-admin-password'
BASE = [BIN, '--skip-securing-files', '--config', CONFIG]
USERNAME = re.compile(r'^[A-Za-z0-9._@+-]{1,64}$')
ROLE = re.compile(r'^[A-Za-z0-9._@:+-]{1,64}$')  # built-in admin role is warpgate:admin
SUPERVISOR_PIDFILE = '/var/run/warpgate.pid'
MAINTENANCE_LOCK = '/var/run/warpgate-maintenance.lock'
LONG_TIMEOUT = 600  # copy/migrate; the API waits LONG_TIMEOUT + 60 (ToolsController.php)
ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]|\r')


def as_warpgate():
    user = pwd.getpwnam('warpgate')
    os.initgroups(user.pw_name, user.pw_gid)  # drop root's supplementary groups too
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def read_nofollow(path, owner=0):
    """read a small file that must be a regular, singly linked file of `owner` (no planted links)"""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)  # a planted FIFO must not block
    with os.fdopen(fd) as f:
        st = os.fstat(f.fileno())
        if st.st_uid != owner or st.st_nlink != 1 or not stat.S_ISREG(st.st_mode):
            raise PermissionError(path)
        return f.read().strip()


def run(args, env=None, timeout=100):  # under the API's default 120 s wait
    proc = subprocess.run(BASE + args, preexec_fn=as_warpgate, env={**os.environ, **(env or {})},
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
    return {'ok': proc.returncode == 0, 'output': ANSI.sub('', proc.stdout).strip()}


def run_interactive(args, answers):
    """drive a dialoguer prompt sequence: answers = [(prompt regex, keys to send), ...]"""
    pid, fd = pty.fork()
    if pid == 0:
        as_warpgate()
        os.execv(BIN, BASE + args)
    output, deadline = '', time.time() + 100  # under the API's default 120 s wait
    while time.time() < deadline:
        if select.select([fd], [], [], 1)[0]:
            try:
                chunk = os.read(fd, 4096).decode(errors='replace')
            except OSError:  # child closed the pty
                break
            if not chunk:
                break
            output += chunk
        if answers and re.search(answers[0][0], ANSI.sub('', output)):
            time.sleep(0.5)  # let dialoguer switch the terminal mode (echo off) before typing
            os.write(fd, answers.pop(0)[1].encode())
    else:
        os.kill(pid, 9)
    status = os.waitpid(pid, 0)[1]
    return {'ok': status == 0 and not answers, 'output': ANSI.sub('', output).strip()}


def service_running():
    try:
        with open(SUPERVISOR_PIDFILE) as f:
            os.kill(int(f.read().strip() or 0), 0)
        return True
    except (OSError, ValueError):
        return False


def maintenance(args, secret=None):
    """database maintenance: only with the service stopped, one at a time, secret kept out of the output"""
    need(not service_running(), 'stop the Warpgate service first (Services: Warpgate), then retry')
    lock = open(MAINTENANCE_LOCK, 'w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        need(False, 'another database operation is still running')
    try:
        result = run(args, timeout=LONG_TIMEOUT)
    except subprocess.TimeoutExpired:
        result = {'ok': False, 'output': f'timed out after {LONG_TIMEOUT} s'}
    for s in filter(None, [secret, *(re.findall(r'://[^:/@]*:([^@]+)@', secret or ''))]):
        result['output'] = result['output'].replace(s, '***')
    return result


def need(cond, message):
    if not cond:
        print(json.dumps({'ok': False, 'output': message}))
        sys.exit(0)


def main(action, *args):
    if action == 'initial_password':
        for path, owner in ((INITIAL_PASSWORD, 0), (LEGACY_INITIAL_PASSWORD, pwd.getpwnam('warpgate').pw_uid)):
            try:
                return {'ok': True, 'output': '', 'password': read_nofollow(path, owner)}
            except (OSError, KeyError):  # missing, no warpgate user yet, or a link planted in the service's directory
                continue
        return {'ok': True, 'output': '', 'password': ''}
    if action == 'dismiss_initial_password':
        for path in (INITIAL_PASSWORD, LEGACY_INITIAL_PASSWORD):
            if os.path.lexists(path):
                os.unlink(path)  # unlink removes a link itself, never its target
        return {'ok': True, 'output': 'initial password removed'}

    need(os.path.exists(BIN) and os.path.exists(CONFIG), 'warpgate is not configured yet: enable it and apply first')
    if action in ('version', 'check', 'client_keys'):
        return run([action.replace('_', '-')])
    if action == 'recover_access':
        need(len(args) == 1 and USERNAME.match(args[0]), 'invalid username')
        password = secrets.token_urlsafe(18)
        result = run_interactive(['recover-access', args[0]],
                                 [(r'New password', password + '\r'), (r'Continue\?', 'y')])
        # the transcript is prompt noise (and could contain the password): keep the last line only
        result['output'] = result['output'].replace(password, '***').splitlines()[-1:][0] if result['output'] else ''
        return {**result, 'password': password if result['ok'] else ''}
    if action == 'create_user':
        need(len(args) in (1, 2) and USERNAME.match(args[0]), 'invalid username')
        need(len(args) == 1 or ROLE.match(args[1]), 'invalid role')
        password = secrets.token_urlsafe(18)
        result = run(['create-user', args[0]] + (['--role', args[1]] if len(args) == 2 else []),
                     env={'WARPGATE_NEW_USER_PASSWORD': password})
        created = result['ok'] and 'already exists' not in result['output']
        return {**result, 'password': password if created else ''}
    if action == 'copy_database':
        need(len(args) == 1 and re.match(r'^(sqlite:|postgres(ql)?://|mysql://)\S+$', args[0]),
             'invalid database URL (sqlite:, postgres:// or mysql://)')
        return maintenance(['copy-database', args[0]], secret=args[0])
    if action == 'migrate_database':
        need(len(args) in (1, 2) and re.match(r'^-?[0-9]{1,3}$', args[0]), 'invalid number of steps')
        need(len(args) == 1 or args[1] == 'destructive', 'invalid option')
        return maintenance(['migrate-database', args[0]] + (['--destructive'] if len(args) == 2 else []))
    return {'ok': False, 'output': 'unknown action'}


if __name__ == '__main__':
    need(len(sys.argv) > 1, 'usage: wgctl.py ACTION [ARG ...]')
    try:
        # configd fills unused parameter slots with empty strings
        print(json.dumps(main(*[a for a in sys.argv[1:] if a != ''])))
    except Exception as e:  # configd shows nothing on a traceback; report it instead
        print(json.dumps({'ok': False, 'output': f'{type(e).__name__}: {e}'}))
