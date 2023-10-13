#
# Copyright (C) 2022 SUSE LLC
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

import logging
import json

log = logging.getLogger(__name__)


def patch_provisioner_config(needle, config):
    pathname = "/var/lib/step-ca/.step/config/ca.json"
    log.error(f"New config: {config}")

    with open(pathname, "r+") as open_file:
        parsed_config = json.load(open_file)

    changed_settings = []

    provisioners = parsed_config["authority"]["provisioners"]
    for provisioner in provisioners:
        if provisioner["name"] != needle:
            continue

        for option, value in config.items():
            log.error(f"Checking {option} for {value}")
            if not(option in provisioner) or provisioner[option] != value:
                log.error(f"Setting {option} to {value}")
                changed_settings.append(option)
                provisioner[option] = value


    if len(changed_settings) > 0:
        # dump to a string first to avoid leaving us with a truncated file when dump fails
        json_string = json.dumps(parsed_config, indent=4)
        if json_string:
            with open(pathname, "w+") as open_file:
                open_file.write(json_string)
            return {"Applied settings": changed_settings}
        else:
            log.error("Dumping config failed")

    return None

# if __name__ == "__main__":
#     needle = "saltstack@example.com"
#     config = {
#         "forceCN": True,
#         "claims": {
#             "maxTLSCertDuration": "2160h0m0s",
#             "defaultTLSCertDuration": "2160h0m0s",
#         }
#     }
#     patch_provisioner_config(needle, config)
