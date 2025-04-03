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

# TODO: get the cert dir from the pillar
step_path = "/etc/step"
certificate_based_dir = "{step_path}/certs".format(step_path=step_path)
cmdline_env = {"STEPPATH": step_path}


def run():
    config = {}

    ssh_key_types = ["ecdsa", "ed25519", "rsa"]

    step_pillar = __pillar__["step"]

    client_config_pillar = step_pillar["client_config"]

    certificate_mode = client_config_pillar.get("certificate_mode", "tokens")
    uses_renewer     = client_config_pillar.get("certificate_use_renewer", True)
    force_deploy     = client_config_pillar.get("force_deploy", False)

    service_reload_deps = []

    if "ssh" in step_pillar and "sign_hosts_certs" in step_pillar["ssh"] and step_pillar["ssh"]["sign_hosts_certs"]:
        ssh_pillar = step_pillar["ssh"]["certs"]

        ssh_hosts_keys_config = ""

        for key_type, cert_data in ssh_pillar.items():
            host_id = __grains__["id"]
            section_name = "step_client_{key_type}_ssh_host_key".format(
                key_type=key_type,
            )
            key_path = "/etc/ssh/ssh_host_{key_type}_key.pub".format(
                key_type=key_type,
            )
            crt_path = "/etc/ssh/ssh_host_{key_type}_key-cert.pub".format(
                key_type=key_type,
            )
            service = "ssh-cert-renewer@{instance}.timer".format(instance=key_type)

            options = ""

            ssh_hosts_keys_config += "HostCertificate /etc/ssh/ssh_host_{key_type}_key-cert.pub\n".format(key_type=key_type)

            renewal_check_cmdline = "/usr/sbin/step-ssh-cert-needs-renewal-for-salt {crt_path}".format(crt_path=crt_path)

            section_type = None
            if "token" in cert_data:
                cmdline = '/usr/bin/step ssh certificate --force --token="{token}" --sign --host --host-id=machine {options} "{commonname}" "{key_path}"'.format(
                    commonname=host_id, token=cert_data["token"], options=options, key_path=key_path, crt_path=crt_path
                )

                section_type = "cmd.run"

                config[section_name] = {
                    section_type: [
                        {"name": cmdline},
                        {
                            "require": [
                                "step_client_config",
                            ]
                        },
                        {"hide_output": True},
                        {"output_loglevel": "debug"},
                        {"onlyif": renewal_check_cmdline},
                    ],
                }

            if "cert" in cert_data:
                section_type = "file.managed"

                config[section_name] = {
                    section_type: [
                        {"name": crt_path},
                        {"user": "root"},
                        {"group": "root"},
                        {"mode": "0640"},
                        {"contents": cert_data["cert"]},
                        {"onlyif": renewal_check_cmdline},
                        {
                            "require": [
                                "step_client_config",
                            ]
                        },
                    ]
                }

            if not (force_deploy):
                config[section_name][section_type].append(
                    {
                        "creates": [
                            crt_path,
                        ]
                    }
                )

            service_reload_deps.append(crt_path)

            if uses_renewer:
                config[section_name + "_renewer_service"] = {
                    "service.running": [
                        {"name": service},
                        {"enable": True},
                        {
                            "require": [
                                section_name,
                            ]
                        },
                    ]
                }
            else:
                config[section_name + "_renewer_service"] = {
                    "service.dead": [
                        {"name": service},
                        {"enable": False},
                    ]
                }

        sshd_config_snippet_file = "/etc/ssh/sshd_config.d/enable_host_certs.conf"
        sshd_reload_cmdline = "/usr/bin/systemctl is-active sshd > /dev/null && /usr/bin/systemctl reload sshd"

        service_reload_deps.append(sshd_config_snippet_file)

        # TODO: this should be done with our pillar based ssh config
        config["sshd_config_enable_certs"] = {
            "file.managed": [
                {"name": sshd_config_snippet_file},
                {"user": "root"},
                {"group": "root"},
                {"mode": "0644"},
                {"contents": ssh_hosts_keys_config},
            ],
        }
        config["sshd_reload"] = {
            "cmd.run": [
                {"name": sshd_reload_cmdline},
                {
                    "require": [
                        sshd_config_snippet_file,
                    ]
                },
                {
                    "onchanges": [
                        sshd_config_snippet_file,
                    ]
                },
                {"hide_output": True},
                {"output_loglevel": "debug"},
            ]
        }

    return config
