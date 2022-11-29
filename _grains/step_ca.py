import salt.utils
import glob
import os.path
import re


def ssh_pub_keys():
    values = {}

    for path in glob.glob("/etc/ssh/ssh_host_*_key.pub"):
        match = re.search(r"/etc/ssh/ssh_host_(?P<key_type>\S+)_key.pub", path)
        key_type = match.group("key_type")

        if key_type == "dsa":
            # plain "dsa" is not supported by step-ca
            continue

        with open(path, "r") as f:
            values[key_type] = f.read()

    result = {"ssh": {"hostkeys": {"pubkeys": values}}}
    return result
