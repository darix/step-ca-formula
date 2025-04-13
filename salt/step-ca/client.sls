#!py
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
                {"pkgs": [ "step-cli", {"step-cli-salt":">= 0.26.0"}, "openssl", "acl" ]},
            ]
        },
        "step_client_config": {
            "file.managed": [
                {"user": "root"},
                {"group": "root"},
                {"mode": "0640"},
                {"template": "jinja"},
                {"require": [ "step_client_package", ]},
                {"name": "{step_dir}/config/defaults.json".format(step_dir=step_dir)},
                {"source": "salt://step-ca/files/etc/step/config/defaults.json.j2"},
                {"context": {"config": context} },
            ]
        },
    }

    if __pillar__.get("step:client_config:deploy_root_from_salt_mine", False):
        ssl_root_cert_mine = __salt__['mine.get'](__grains__['id'], 'step_ca_ssl_root_certificate')
        if len(ssl_root_cert_mine) > 0:

            root_cert_states = []

            for ca_host, cert_data in ssl_root_cert_mine.items():

                cleaned_ca_host = ca_host.replace('.','_')
                root_cert_state = f"step_ca_root_cert_{cleaned_ca_host}"
                root_cert_states.append(root_cert_state)

                config[root_cert_state] = {
                    "file.managed": [
                        {"user": "root"},
                        {"group": "root"},
                        {"mode": "0644"},
                        {"name": f"/usr/share/pki/trust/anchors/{root_cert_state}.pem"},
                        {"contents": cert_data}
                    ]
                }

            config["ca_certificates_update"] = {
                "cmd.run": [
                    {"name": "/usr/sbin/update-ca-certificates"},
                    {"onchanges": root_cert_states},
                    {"require":   root_cert_states},
                ]
            }

    # if __pillar__.get("step:ssh:deploy_user_ca", False):
    #     TODO: this needs some code to handle which domains we expect by this host CA to be signed
    #     ssh_host_mine = __salt__['mine.get'](__grains__['id'], 'step_ca_ssh_host_ca_pubkey')
    #     if len(ssh_host_mine) > 0:
    #         file_content = []
    #         for ca_host, cert_data in ssh_host_mine.items():
    #             file_content.append(f"# {ca_host}")
    #             file_content

    if __pillar__.get("step:ssh:deploy_user_ca", False):
        ssh_user_mine = __salt__['mine.get'](__grains__['id'], 'step_ca_ssh_user_ca_pubkey')

        if len(ssh_user_mine) > 0:
            file_content = []
            for ca_host, cert_data in ssh_user_mine.items():
                file_content.append(f"# CA Host: {ca_host}")
                file_content.append(cert_data)
                root_cert_state = "ssh_user_ca_pubkey"
                config[root_cert_state] = {
                    "file.managed": [
                        {"user": "root"},
                        {"group": "root"},
                        {"mode": "0644"},
                        {"name": f"/etc/ssh/ssh_user_ca_key.pub"},
                        {"contents": "\n".join(file_content)}
                    ],
                }

                config["ssh_user_ca_sshd_reload"] = {
                    "cmd.run" : [
                        {"name":   "/bin/systemctl reload sshd.service"},
                        {"onlyif": "/bin/systemctl is-active sshd.service"},
                        {"onchanges": [root_cert_state]},
                        {"require":   [root_cert_state]}
                    ]
                }


    return config
