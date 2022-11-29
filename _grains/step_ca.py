import salt.utils
import glob
import os.path
import re


def ssh_pub_keys():
    values = {}

    for filename in glob.glob("/etc/ssh/ssh_host_*_key.pub"):
        match = re.search(r"/etc/ssh/ssh_host_(?P<key_type>\S+)_key.pub", filename)
        # plain "dsa' is not supported by step-ca
        if "dsa" != match.group("key_type") and os.path.exists(filename):
            with open(filename, "r") as f:
                values[match.group("key_type")] = f.read()

    ret = {"ssh": {"hostkeys": {"pubkeys": values}}}

    return ret
