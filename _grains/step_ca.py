import salt.utils
import glob
import os.path
import re


def ssh_pub_keys():
    values = {}

    for path in glob.glob("/etc/ssh/ssh_host_*_key.pub"):
        match = re.search(r"/etc/ssh/ssh_host_(?P<key_type>\S+)_key.pub", path)
        # plain "dsa" is not supported by step-ca
        if "dsa" != match.group("key_type"):
            with open(path, "r") as f:
                values[match.group("key_type")] = f.read()

    ret = {"ssh": {"hostkeys": {"pubkeys": values}}}

    return ret
