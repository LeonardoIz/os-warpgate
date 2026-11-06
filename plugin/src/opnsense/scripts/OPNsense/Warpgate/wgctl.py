#!/usr/local/bin/python3
"""Run warpgate's own CLI commands for the OPNsense GUI (via configd), as the warpgate user.

wgctl.py ACTION [ARG ...] -> prints one JSON object: {"ok": bool, "output": str, ["password": str]}
Passwords are generated here and never passed on a command line; arguments are validated before use.
"""
import json
import os
import pty
import pwd
import re
import secrets
import select
import subprocess
import sys
import time

BIN = '/usr/local/bin/warpgate'
CONFIG = '/usr/local/etc/warpgate.yaml'
INITIAL_PASSWORD = '/var/db/warpgate/initial-admin-password'
BASE = [BIN, '--skip-securing-files', '--config', CONFIG]
USERNAME = re.compile(r'^[A-Za-z0-9._@+-]{1,64}$')
ROLE = re.compile(r'^[A-Za-z0-9._@:+-]{1,64}$')  # built-in admin role is warpgate:admin
ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]|\r')


def as_warpgate():
    user = pwd.getpwnam('warpgate')
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def run(args, env=None):
    proc = subprocess.run(BASE + args, preexec_fn=as_warpgate, env={**os.environ, **(env or {})},
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600)
    return {'ok': proc.returncode == 0, 'output': ANSI.sub('', proc.stdout).strip()}


def run_interactive(args, answers):
    """drive a dialoguer prompt sequence: answers = [(prompt regex, keys to send), ...]"""
    pid, fd = pty.fork()
    if pid == 0:
        as_warpgate()
        os.execv(BIN, BASE + args)
    output, deadline = '', time.time() + 120
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


def need(cond, message):
    if not cond:
        print(json.dumps({'ok': False, 'output': message}))
        sys.exit(0)


def main(action, *args):
    if action == 'initial_password':
        try:
            with open(INITIAL_PASSWORD) as f:
                return {'ok': True, 'output': '', 'password': f.read().strip()}
        except FileNotFoundError:
            return {'ok': True, 'output': '', 'password': ''}
    if action == 'dismiss_initial_password':
        if os.path.exists(INITIAL_PASSWORD):
            os.unlink(INITIAL_PASSWORD)
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
        return run(['copy-database', args[0]])
    if action == 'migrate_database':
        need(len(args) in (1, 2) and re.match(r'^-?[0-9]{1,3}$', args[0]), 'invalid number of steps')
        need(len(args) == 1 or args[1] == 'destructive', 'invalid option')
        return run(['migrate-database', args[0]] + (['--destructive'] if len(args) == 2 else []))
    return {'ok': False, 'output': 'unknown action'}


if __name__ == '__main__':
    need(len(sys.argv) > 1, 'usage: wgctl.py ACTION [ARG ...]')
    try:
        # configd fills unused parameter slots with empty strings
        print(json.dumps(main(*[a for a in sys.argv[1:] if a != ''])))
    except Exception as e:  # configd shows nothing on a traceback; report it instead
        print(json.dumps({'ok': False, 'output': f'{type(e).__name__}: {e}'}))
