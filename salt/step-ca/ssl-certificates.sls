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

from salt.exceptions import SaltConfigurationError

# TODO: get the cert dir from the pillar
step_path = "/etc/step"
certificate_based_dir = "{step_path}/certs".format(step_path=step_path)
cmdline_env = {"STEPPATH": step_path}


def run():
    config = {}

    step_pillar = __pillar__["step"]

    client_config_pillar = step_pillar["client_config"]

    if "certificates" in step_pillar:

        certificates_pillar = __pillar__["step"]["certificates"]

        certificate_mode = "tokens"
        uses_renewer = True
        ssl_generate_dhparams = True
        ssl_merged_certificates = True
        dhparam_length = 2048
        dhparam_file = "{cert_dir}/dhparams".format(cert_dir=certificate_based_dir)
        dhparam_content = None

        drop_in_paths = []

        if "certificate_mode" in client_config_pillar:
            certificate_mode = client_config_pillar["certificate_mode"]

        if "force_deploy" in client_config_pillar:
            force_deploy = client_config_pillar["force_deploy"]

        if "certificate_use_renewer" in client_config_pillar:
            uses_renewer = client_config_pillar["certificate_use_renewer"]

        if "ssl_generate_dhparams" in client_config_pillar:
            ssl_generate_dhparams = client_config_pillar["ssl_generate_dhparams"]

        if "ssl_merged_certificates" in client_config_pillar:
            ssl_merged_certificates = client_config_pillar["ssl_merged_certificates"]

        if "dhparam_length" in client_config_pillar:
            dhparam_length = client_config_pillar["dhparam_length"]

        if ssl_generate_dhparams:
            dhparam_cmdline = "/usr/bin/openssl dhparam -out {dhparam_file} {dhparam_length}".format(
                dhparam_file=dhparam_file,
                dhparam_length=dhparam_length,
            )

            config["generate_dhparams"] = {
                "cmd.run": [
                    {"name": dhparam_cmdline},
                    {"hide_output": True},
                    {"output_loglevel": "debug"},
                    {"creates": dhparam_file},
                    {
                        "require": [
                            "step_client_config",
                        ]
                    },
                ]
            }

            # if not (force_deploy):
            #    config["generate_dhparams"]["cmd.run"].append( {"creates": dhparam_file} )

        for cert_type, scope_cert_pillar in certificates_pillar.items():

            for cert_name, cert_data in scope_cert_pillar.items():

                cert_name_type = "{cert_name}.{cert_type}".format(
                    cert_name=cert_name,
                    cert_type=cert_type,
                )
                base_path = "{basedir}/{cert_name_type}".format(
                    basedir=certificate_based_dir,
                    cert_name_type=cert_name_type,
                )
                csr_path = "{base_path}.{extension}".format(base_path=base_path, extension="csr")
                crt_path = "{base_path}.{extension}".format(base_path=base_path, extension="cert.pem")
                key_path = "{base_path}.{extension}".format(base_path=base_path, extension="key.pem")
                full_path = "{base_path}.{extension}".format(base_path=base_path, extension="full.pem")

                common_name = __grains__["id"]

                if "cn" in cert_data:
                    common_name = cert_data["cn"]

                section_name = "step_client_{cert_type}_{cert_name}".format(
                    cert_type=cert_type,
                    cert_name=cert_name,
                )
                service = "cert-renewer@{instance}.timer".format(instance=cert_name_type)

                service_deps = [
                    section_name + "_drop_in",
                    "stepca_systemd_daemon_reload",
                ]

                combine_filenames = [crt_path, key_path]

                drop_in_dir = "/etc/systemd/system/cert-renewer@{cert_name_type}.service.d".format(cert_name_type=cert_name_type)
                drop_in_path = "{drop_in_dir}/salt.conf".format(drop_in_dir=drop_in_dir)

                drop_in_paths.append(drop_in_path)

                drop_in_deps = []
                combine_deps = []

                if uses_renewer:
                    drop_in_deps.append(section_name + "_drop_in_dir")

                if ssl_generate_dhparams:
                    combine_deps.append("generate_dhparams")
                    drop_in_deps.append("generate_dhparams")
                    combine_filenames.append(dhparam_file)

                combine_cmdline = "/usr/sbin/step-ssl-merge-certs-for-salt {full_path} {combine_filenames}".format(combine_filenames=" ".join(combine_filenames), full_path=full_path)
                drop_in_content = """
[Service]
# Reset env
Environment=
# use our paths
Environment=STEPPATH={step_path} \\
            CERT_LOCATION={certificate_based_dir}/%i.cert.pem \\
            KEY_LOCATION={certificate_based_dir}/%i.key.pem
# disable upstream ExecStartPost=
ExecStartPost=
""".format(
                    certificate_based_dir=certificate_based_dir, step_path=step_path
                )
                if ssl_merged_certificates:
                    drop_in_content += "ExecStartPost={combine_cmdline}\n".format(combine_cmdline=combine_cmdline)

                    if "acls_for_combined_file" in cert_data:
                        for acl_setting in cert_data["acls_for_combined_file"]:
                            acl_type_prefix = acl_setting["acl_type"][0]

                            acl_perms = "r"
                            if "perms" in acl_setting:
                                acl_perms = acl_setting["perms"]

                            for acl_name in acl_setting["acl_names"]:
                                drop_in_content += f"ExecStartPost=/usr/bin/setfacl -m {acl_type_prefix}:{acl_name}:{acl_perms} {full_path}\n"

                if "exec_start_post" in cert_data:
                    if isinstance(cert_data["exec_start_post"], str):
                        drop_in_content += "ExecStartPost={line}\n".format(line=cert_data["exec_start_post"])
                    else:
                        for line in cert_data["exec_start_post"]:
                            drop_in_content += "ExecStartPost={line}\n".format(line=line)

                if "affected_services" in cert_data:
                    # drop_in_content+="ExecStartPost=systemctl try-reload-or-restart {services_list}\n".format(services_list=' '.join(cert_data['affected_services']))
                    for affected_service in cert_data["affected_services"]:
                        drop_in_content += "ExecStartPost=bash -c '/usr/bin/systemctl is-active {affected_service} && /usr/bin/systemctl try-reload-or-restart {affected_service}'\n".format(affected_service=affected_service)

                config[section_name] = {}
                renewal_check_cmdline = "/usr/sbin/step-ssl-cert-needs-renewal-for-salt {crt_path}".format(crt_path=crt_path)

                if "tokens" == certificate_mode:
                    # we do not need to specify the --san entries here as they are encoded in the token.
                    token = cert_data["token"]
                    if token == "":
                        raise SaltConfigurationError(f"Can not create cert for {common_name} with empty token")

                    cmdline = '/usr/bin/step ca certificate --force --token="{token}" {options} "{commonname}" "{crt_path}" "{key_path}"'.format(
                        commonname=common_name,
                        token=cert_data["token"],
                        options=cert_data["options"],
                        crt_path=crt_path,
                        key_path=key_path,
                    )

                    drop_in_deps.append(section_name + "_token_cmd")
                    combine_deps.append(section_name + "_token_cmd")
                    config[section_name + "_token_cmd"] = {
                        "cmd.run": [
                            {"name": cmdline},
                            {"env": cmdline_env},
                            {"hide_output": True},
                            {"output_loglevel": "debug"},
                            {
                                "require": [
                                    "step_client_config",
                                ]
                            },
                        ]
                    }
                    if not (force_deploy):
                        config[section_name + "_token_cmd"]["cmd.run"].append(
                            {"onlyif": renewal_check_cmdline}
                        )
                        config[section_name + "_token_cmd"]["cmd.run"].append(
                            {
                                "creates": [
                                    crt_path,
                                    key_path,
                                ]
                            }
                        )

                elif "certificates" == certificate_mode:

                    drop_in_deps.append(section_name + "_key")
                    drop_in_deps.append(section_name + "_cert")

                    combine_deps.append(section_name + "_key")
                    combine_deps.append(section_name + "_cert")

                    config[section_name + "_key"] = {
                        "file.managed": [
                            {"name": key_path},
                            {"user": "root"},
                            {"group": "root"},
                            {"mode": "0640"},
                            {"contents": cert_data["key"]},
                            {"require": ["step_client_config"]},
                        ]
                    }

                    config[section_name + "_cert"] = {
                        "file.managed": [
                            {"name": crt_path},
                            {"user": "root"},
                            {"group": "root"},
                            {"mode": "0640"},
                            {"contents": cert_data["cert"]},
                            {
                                "require": [
                                    "step_client_config",
                                ]
                            },
                        ]
                    }
                    if not (force_deploy):
                        config[section_name + "_key"]["file.managed"].append(
                            {"onlyif": renewal_check_cmdline}
                        )
                        config[section_name + "_key"]["file.managed"].append(
                            {
                                "creates": [
                                    crt_path,
                                    key_path,
                                ]
                            }
                        )

                        config[section_name + "_cert"]["file.managed"].append(
                            {"onlyif": renewal_check_cmdline}
                        )
                        config[section_name + "_cert"]["file.managed"].append(
                            {
                                "creates": [
                                    crt_path,
                                    key_path,
                                ]
                            }
                        )

                if ssl_merged_certificates:
                    drop_in_deps.append(section_name + "_combined")

                    config[section_name + "_combined"] = {
                        "cmd.run": [
                            {"name": combine_cmdline},
                            {"hide_output": True},
                            {"output_loglevel": "debug"},
                            {"require":   combine_deps},
                            {"onchanges": combine_deps},
                        ]
                    }
                    if not (force_deploy):
                        config[section_name + "_combined"]["cmd.run"].append({"creates": full_path})


                    if "acls_for_combined_file" in cert_data:
                        acl_index = 0
                        for acl_setting in cert_data["acls_for_combined_file"]:
                            acl_perms = "r"
                            if "perms" in acl_setting:
                                acl_perms = acl_setting["perms"]

                            for acl_name in acl_setting["acl_names"]:
                                acl_section = f"{section_name}_acl_{acl_index}"
                                config[acl_section] = {
                                    "acl.present": [
                                        {"name":      full_path},
                                        {"acl_type":  acl_setting["acl_type"]},
                                        {"acl_name":  acl_name},
                                        {"perms":     acl_perms},
                                        {"require":   drop_in_deps},
                                        {"onchanges": drop_in_deps},
                                    ]
                                }
                                acl_index += 1

                    # TODO: this is just an ugly hack until
                    # if True: #"haproxy" in cert_data["affected_services"]:
                    if "affected_services" in cert_data:
                        mapped_services = map(
                            lambda x: "service: {service}".format(service=x),
                            cert_data["affected_services"]
                        )
                        config[section_name + "_combined"]["cmd.run"].append(
                            {
                                "watch_in":   mapped_services,
                                "require_in": mapped_services,
                                "onchanges_in":   mapped_services,
                            }
                        )

                if uses_renewer:

                    config[section_name + "_drop_in_dir"] = {
                        "file.directory": [
                            {"name": drop_in_dir},
                            {"user": "root"},
                            {"group": "root"},
                            {"mode": "0750"},
                        ],
                    }

                    config[section_name + "_drop_in"] = {
                        "file.managed": [
                            {"name": drop_in_path},
                            {"user": "root"},
                            {"group": "root"},
                            {"mode": "0640"},
                            {"contents": drop_in_content},
                            {"require": drop_in_deps},
                        ],
                    }

                    config[section_name + "_service"] = {
                        "service.running": [
                            {"name": service},
                            {"enable": True},
                            {"require": service_deps},
                        ]
                    }

                    config["stepca_systemd_daemon_reload"] = {
                        "module.run": [
                            {"name": "service.systemctl_reload"},
                            {"onchanges": drop_in_paths},
                        ]
                    }
                else:
                    config[section_name + "_service"] = {
                        "service.dead": [
                            {"name": service},
                            {"enable": False},
                        ]
                    }

                    config[section_name + "_drop_in"] = {
                        "file.absent": [
                            {"name": drop_in_path},
                        ],
                    }

                    config[section_name + "_drop_in_dir"] = {
                        "file.absent": [
                            {"name": drop_in_dir},
                        ],
                    }

                    if "exec_start_post" in cert_data:
                        if isinstance(cert_data["exec_start_post"], str):
                            config[section_name + "_exec_start_post"] = {
                                "cmd.run": [
                                    {"name": cert_data["exec_start_post"]},
                                    {"hide_output": True},
                                    {"output_loglevel": "debug"},
                                    {"require": drop_in_deps},
                                    {"onchanges": drop_in_deps},
                                ]
                            }
                        else:
                            for line in cert_data["exec_start_post"]:
                                loop_counter = 0

                                config[section_name + "_exec_start_post_{index}".format(index=loop_counter)] = {
                                    "cmd.run": [
                                        {"name": line},
                                        {"hide_output": True},
                                        {"output_loglevel": "debug"},
                                        {"require": drop_in_deps},
                                        {"onchanges": drop_in_deps},
                                    ]
                                }
                                loop_counter += 1

                    # TODO: we could also use the require_in or so here to trigger services configured via salt
                    if "affected_services" in cert_data:
                        loop_counter = 0

                        for affected_service in cert_data["affected_services"]:
                            config[section_name + "_restart_service_{index}".format(index=loop_counter)] = {
                                "cmd.run": [
                                    {"name":   "/usr/bin/systemctl try-reload-or-restart {affected_service}".format(affected_service=affected_service)},
                                    {"onlyif": "/usr/bin/systemctl is-active {affected_service}".format(affected_service=affected_service)},
                                    {"hide_output": True},
                                    {"output_loglevel": "debug"},
                                    {"require": drop_in_deps},
                                    {"onchanges": drop_in_deps},
                                ]
                            }
                            loop_counter += 1

    return config
