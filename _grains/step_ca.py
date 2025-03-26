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
