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

# TODO: get the cert dir from the pillar
step_path = '/etc/step'
certificate_based_dir = '{step_path}/certs'.format(step_path=step_path)
cmdline_env = {
  'STEPPATH': step_path
}

def run():
  config = {}

  ssh_key_types = ['ecdsa', 'ed25519', 'rsa']

  step_pillar = __pillar__['step']

  if 'ssh' in step_pillar and 'sign_hosts_certs' in step_pillar['ssh'] and step_pillar['ssh']['sign_hosts_certs']:
    ssh_pillar=step_pillar['ssh']

    for key_type in ssh_key_types:
      host_id      = __grains__['id']
      section_name = 'step_client_{key_type}_ssh_host_key'.format( key_type=key_type, )
      key_path     = '/etc/ssh/ssh_host_{key_type}_key.pub'.format( key_type=key_type, )
      crt_path     = '/etc/ssh/ssh_host_{key_type}_key-cert.pub'.format( key_type=key_type, )
      options      = ''
      token        = ssh_pillar[key_type]['token']

      cmdline      = '/usr/bin/step ssh certificate --force --token="{token}" --sign --host --host-id=machine {options} "{commonname}" "{key_path}"'.format(
        commonname=host_id,
        token=token,
        options=options,
        key_path=key_path,
        crt_path=crt_path
      )

      service      = 'ssh-cert-renewer@{instance}.timer'.format(instance=key_type)

      config[section_name] = {
        'cmd.run': [
          { 'name':    cmdline                   },
          { 'require': [ 'step_client_config', ] },
          { 'creates': [ crt_path, ]             },
        ],
        'service.running': [
          { 'name': service },
          { 'enable': True  },
        ]
      }

    ssh_hosts_keys_config = ""
    for key_type in ssh_key_types:
      ssh_hosts_keys_config += "HostCertificate /etc/ssh/ssh_host_{key_type}_key-cert.pub\n".format(key_type=key_type)

    sshd_config_snippet_file = '/etc/ssh/sshd_config.d/enable_host_certs.conf'
    sshd_reload_cmdline      = '/usr/bin/systemctl is-active sshd > /dev/null && /usr/bin/systemctl reload sshd'

    # TODO: this should be done with our pillar based ssh config
    config['sshd_config_enable_certs'] = {
      'file.managed': [
        { 'name':      sshd_config_snippet_file },
        { 'user':     'root'                    },
        { 'group':    'root'                    },
        { 'mode':     '0644'                    },
        { 'contents': ssh_hosts_keys_config     },
      ],
    }
    config['sshd_reload'] = {
      'cmd.run': [
        { 'name':      sshd_reload_cmdline           },
        # { 'require':   [ sshd_config_snippet_file, ] },
        # { 'onchanges': [ sshd_config_snippet_file, ] },
      ]
    }

  return config