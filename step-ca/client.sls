#!py

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

step_dir = "/etc/step"


def run():
    ca_pillar = __pillar__["step"]["client_config"]["ca"]
    context = {"ca-url": ca_pillar["url"], "fingerprint": ca_pillar["root_cert"]["fingerprint"]}

    if "contact_email" in ca_pillar:
        context["contact"] = ca_pillar["contact_email"]

    if "path" in ca_pillar["root_cert"]:
        context["root"] = ca_pillar["root_cert"]["path"]

    config = {
        "step_client_package": {
            "pkg.installed": [
                {
                    "names": [
                        "step-cli",
                        "step-cli-salt",
                    ]
                },
            ]
        },
        "step_client_config": {
            "file.managed": [
                {"user": "root"},
                {"group": "root"},
                {"mode": "0640"},
                {"template": "jinja"},
                {
                    "require": [
                        "step_client_package",
                    ]
                },
                {"name": "{step_dir}/config/defaults.json".format(step_dir=step_dir)},
                {"source": "salt://step-ca/files/etc/step/config/defaults.json.j2"},
                {
                    "context": {"config": context},
                },
            ]
        },
    }
    return config
