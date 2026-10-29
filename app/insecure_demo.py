import hashlib
import subprocess


def run_command(cmd):
    return subprocess.run(cmd, shell=True)


def weak_hash(data):
    return hashlib.md5(data).hexdigest()
