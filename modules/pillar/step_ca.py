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

from salt.modules.cmdmod import run_stdout as cmdrun
import salt.utils.data
import logging
import os.path
import os
import tempfile

from salt.exceptions import SaltConfigurationError, SaltRenderError

log = logging.getLogger(__name__)


class StepCACLient:
    def __init__(self, minion_id, pillar):
        self.minion_id = minion_id
        self.pillar = pillar
        self.master_config = __opts__

        # TODO: this needs to be moved to a better path in the pillar tree.
        self.mode = self.master_setting_or_pillar_or_default("certificate_mode", "step:client_config:certificate_mode", "tokens")

        self.step_binary = "/usr/bin/step"
        self.salt_step_dir = "/etc/salt/step"

        # those values should be configurable in the long term.
        self.step_dir = "/etc/step"

        self.ssl_cert_dir = "{step_dir}/certs".format(step_dir=self.step_dir)
        self.ssl_name_pattern = "{cert_dir}/{cert_name}.{cert_type}.{extension}"

        # we do user and host certificates for SSL
        self.cert_scopes = ["user", "host"]

        # ssh_host_dsa_key.pub  ssh_host_ecdsa_key.pub  ssh_host_ed25519_key.pub  ssh_host_rsa_key.pub
        self.ssh_key_types = ["ecdsa", "ed25519", "rsa"]
        self.step_pillar = {}

        self.cmd_env = {
            "STEPPATH": self.salt_step_dir,
        }

        if "step" in self.pillar:
            if self.initialize_auth_data():
                self.step_pillar["step"] = {}

                log.info("Getting SSH related data")
                self.do_ssh_tokens()

                log.info("Processing SSL certificates")
                self.do_ssl_certificates()

    def new_pillar(self):
        return self.step_pillar

    def initialize_auth_data(self):
        self.provisioner = self.master_setting_or_pillar_or_default("local_ca_user", "local_ca_user", None)

        if self.provisioner:
            log.info("Using provisioner {provisioner}".format(provisioner=self.provisioner))
            self.provisioner_password_file = self.master_setting_or_pillar_or_default(
                "local_ca_password_file",
                "local_ca_password_file",
                "{salt_step_dir}/config/password".format(salt_step_dir=self.salt_step_dir),
            )
            self.token_timeout = self.master_setting_or_pillar_or_default("step_ca_token_lifetime", "step:defaults:token:lifetime", "30m")
            self.cert_timeout = self.master_setting_or_pillar_or_default("step_ca_cert_lifetime", "step:defaults:certificate:lifetime", "720h")
            return True
        else:
            log.error("Can not find provisioner to use for {minion_id}".format(minion_id=self.minion_id))
            return False

    def list_to_options_string(self, option_name, list):
        return " ".join(
            map(
                lambda entry: '--{option_name}="{entry}"'.format(entry=entry, option_name=option_name),
                list,
            )
        )

    def options_to_string(self, cert_data):
        if "config" in cert_data:
            config_items = []
            # TODO: move this to a function
            #
            #
            if "crv" in cert_data["config"] and not("kty" in cert_data["config"]):
                cert_data["config"]["kty"] = "EC"
            for option_name, value in cert_data["config"].items():
                config_items.append('--{option_name}="{value}"'.format(option_name=option_name, value=value))
            return " ".join(config_items)
        else:
            return ""

    def master_setting_or_pillar_or_default(self, setting_name, pillar_path, default_value):

        value = salt.utils.data.traverse_dict_and_list(self.pillar, pillar_path)
        if value:
            return value

        if setting_name in self.master_config:
            value = self.master_config[setting_name]
            return value

        return default_value

    def run_token_command(self, common_name, cmd_line_options):
        cmd_line = "{step} ca token --provisioner {provisioner} --provisioner-password-file={provisioner_password_file} --not-after={token_timeout} --cert-not-after={cert_timeout} {options} {common_name}".format(
            step=self.step_binary,
            provisioner=self.provisioner,
            provisioner_password_file=self.provisioner_password_file,
            cert_timeout=self.cert_timeout,
            token_timeout=self.token_timeout,
            common_name=common_name,
            options=cmd_line_options,
        )

        token = cmdrun(
            cmd=cmd_line,
            env=self.cmd_env,
        )

        if token and token != "":
            return token
        else:
            raise SaltRenderError(f"Failed to get token from {self.provisioner} for {common_name}")

    def read_and_cleanup(self, filename):
        return_data = None
        with open(filename, "r") as f:
            return_data = f.read()
        os.remove(filename)
        return return_data

    def tempfile_name(self):
        # TODO: this needs better error handling
        fd, tmpfile = tempfile.mkstemp()
        # without the close salt keeps the file open and step cli doesnt want to write to it.
        os.close(fd)
        return tmpfile

    def run_ssl_cert_command(self, common_name, token, cert_options):
        key_tmp_filename = self.tempfile_name()
        cert_tmp_filename = self.tempfile_name()

        cmd_line = "{step} ca certificate --force --token {token} --provisioner {provisioner} --provisioner-password-file={provisioner_password_file} --not-after={cert_timeout} {cert_options} {common_name} {cert_tmp_filename} {key_tmp_filename}".format(
            step=self.step_binary,
            provisioner=self.provisioner,
            provisioner_password_file=self.provisioner_password_file,
            cert_timeout=self.cert_timeout,
            token=token,
            common_name=common_name,
            cert_options=cert_options,
            key_tmp_filename=key_tmp_filename,
            cert_tmp_filename=cert_tmp_filename,
        )

        cmdrun(
            cmd=cmd_line,
            env=self.cmd_env,
        )

        return self.read_and_cleanup(key_tmp_filename), self.read_and_cleanup(cert_tmp_filename)

    def run_ssh_cert_command(self, token, key, common_name, options):

        key_tmp_filename = self.tempfile_name()
        cert_tmp_filename = "{key_filename}-cert.pub".format(key_filename=key_tmp_filename)

        with open(key_tmp_filename, "w") as f:
            f.write(key)

        cmd_line = '/usr/bin/step ssh certificate --force --token="{token}" --sign --host --host-id=machine {options} "{commonname}" "{key_path}"'.format(
            commonname=common_name,
            token=token,
            options=options,
            key_path=key_tmp_filename,
        )

        log.info(cmd_line)

        cmdrun(
            cmd=cmd_line,
            env=self.cmd_env,
        )

        os.remove(key_tmp_filename)

        if not (os.path.exists(cert_tmp_filename)):
            return None

        return self.read_and_cleanup(cert_tmp_filename)

    def do_ssh_tokens(self):
        if "ssh" in self.pillar["step"] and "sign_hosts_certs" in self.pillar["step"]["ssh"] and self.pillar["step"]["ssh"]["sign_hosts_certs"]:
            self.step_pillar["step"]["ssh"] = {}
            self.step_pillar["step"]["ssh"]["certs"] = {}

            cmd_line_options = "--ssh --host "

            principal_options = ""
            if "principals" in self.pillar["step"]["ssh"]:
                principal_options = self.list_to_options_string("principal", self.pillar["step"]["ssh"]["principals"])
            cmd_line_options += principal_options

            pubkey_grains = __grains__["ssh"]["hostkeys"]["pubkeys"]
            for key_type, key in pubkey_grains.items():
                # TODO: throw error if key_type is not in ssh_key_types list
                token = self.run_token_command(self.minion_id, cmd_line_options)

                if "certificates" == self.mode:
                    cert = self.run_ssh_cert_command(token, key, self.minion_id, principal_options)
                    if cert:
                        self.step_pillar["step"]["ssh"]["certs"][key_type] = {
                            "cert": cert,
                        }
                elif "tokens" == self.mode:
                    self.step_pillar["step"]["ssh"]["certs"][key_type] = {
                        "token": token,
                    }

    def do_ssl_certificates(self):
        if "step" in self.pillar and "certificates" in self.pillar["step"]:
            self.step_pillar["step"]["certificates"] = {}

            cert_pillar = self.pillar["step"]["certificates"]

            # TODO: maybe replace this with a .items() loop and only verify that we know the cert_type
            for cert_type in self.cert_scopes:

                if cert_type in cert_pillar:
                    scope_cert_pillar = cert_pillar[cert_type]

                    self.step_pillar["step"]["certificates"][cert_type] = {}

                    for cert_name, cert_data in scope_cert_pillar.items():
                        log.error(
                            "Processing cert_type {cert_type} with cert_name {cert_name} and cert_data {cert_data}".format(
                                cert_type=cert_type,
                                cert_name=cert_name,
                                cert_data=cert_data,
                            )
                        )
                        if "cn" in cert_data:
                            common_name = cert_data["cn"]
                        else:
                            common_name = self.minion_id

                        san_entries = ""
                        if "san" in cert_data:
                            san_entries = self.list_to_options_string("san", cert_data["san"])
                        else:
                            san_entries = self.list_to_options_string("san", [common_name])

                        options = self.options_to_string(cert_data)

                        cmd_line_options = san_entries

                        token = self.run_token_command(common_name, cmd_line_options)

                        cert_filename = self.ssl_name_pattern.format(
                            cert_dir=self.ssl_cert_dir,
                            cert_name=cert_name,
                            cert_type=cert_type,
                            extension="cert.pem",
                        )

                        key_filename = self.ssl_name_pattern.format(
                            cert_dir=self.ssl_cert_dir,
                            cert_name=cert_name,
                            cert_type=cert_type,
                            extension="key.pem",
                        )

                        if "certificates" == self.mode:
                            key, cert = self.run_ssl_cert_command(common_name, token, options)
                            self.step_pillar["step"]["certificates"][cert_type][cert_name] = {
                                "key_filename": key_filename,
                                "cert_filename": cert_filename,
                                "cert": cert,
                                "key": key,
                            }
                        elif "tokens" == self.mode:
                            self.step_pillar["step"]["certificates"][cert_type][cert_name] = {
                                "key_filename": key_filename,
                                "cert_filename": cert_filename,
                                "token": token,
                                "options": options,
                            }
                        # else:
                        # raise error similar to what dmach does in pass


def __virtual__():
    """
    This module has no external dependencies
    """
    return os.path.exists("/usr/bin/step")


def ext_pillar(minion_id, pillar):
    step_ca_client = StepCACLient(minion_id, pillar)
    return step_ca_client.new_pillar()
