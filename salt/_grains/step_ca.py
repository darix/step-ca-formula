#
# step-ca-formula
#
# Copyright (C) 2025   darix
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

import salt.utils
import glob
import os.path
import re

import logging
log = logging.getLogger(__name__)

def ssh_pub_keys():
    pubkeys  = {}

    for path in glob.glob("/etc/ssh/ssh_host_*_key.pub"):
        match = re.search(r"/etc/ssh/ssh_host_(?P<key_type>\S+)_key.pub", path)
        key_type = match.group("key_type")

        if key_type == "dsa":
            # plain "dsa" is not supported by step-ca
            continue

        with open(path, "r") as f:
            pubkeys [key_type] = f.read()

    result = {"ssh": {"hostkeys": {"pubkeys": pubkeys }}}
    client_config = __pillar__.get("step", {}).get("client_config", {})
    force_mode =       client_config.get("force_deploy", False)
    certificate_mode = client_config.get("certificate_mode", "token")
    certificate_mode_compare = (certificate_mode == "certificates")

    if force_mode and certificate_mode_compare:
        needs_refresh = {}
        for path in glob.glob("/etc/ssh/ssh_host_*_key-cert.pub"):
            match = re.search(r"/etc/ssh/ssh_host_(?P<key_type>\S+)_key-cert.pub", path)
            key_type = match.group("key_type")

            if key_type == "dsa":
                # plain "dsa" is not supported by step-ca
                continue

            r = os.system(f"/usr/sbin/step-ssl-cert-needs-renewal-for-salt {path}")
            needs_refresh[key_type] = (r == 0)
        result["ssh"]["hostkeys"]["need_refresh"] = needs_refresh

    return result