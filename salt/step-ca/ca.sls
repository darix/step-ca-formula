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

import os
import salt.utils.json as sujson
import logging
log = logging.getLogger("step/ca")

def run():
  config={}
  if __salt__['pillar.get']('step:ca:enabled', False):
      ca_pillar = __salt__['pillar.get']('step:ca', {})
      config['step_ca_package'] = {
        'pkg.installed': [
          {'pkgs': ['step-ca', 'jq']},
        ]
      }

      config['step_ca_password_file'] = {
        'file.managed': [
          { 'name':            '/etc/step-ca/password.txt' },
          { 'user':            'root' },
          { 'group':           '_step-ca' },
          { 'mode':            '640' },
          { 'requires':        ['step_ca_package'] },
          { 'contents_pillar': 'step:ca:password' },
        ]
      }

      created_files = [
        '/var/lib/step-ca/.step/secrets/root_ca_key',
        '/var/lib/step-ca/.step/secrets/intermediate_ca_key',
        '/var/lib/step-ca/.step/config/ca.json',
        '/var/lib/step-ca/.step/config/defaults.json',
        '/var/lib/step-ca/.step/certs/intermediate_ca.crt',
        '/var/lib/step-ca/.step/certs/root_ca.crt',
      ]

      cmdline_elements = ['/usr/bin/step', 'ca', 'init', '--password-file="/etc/step-ca/password.txt"']
      cmdline_elements.append('--deployment-type="{deployment_type}"'.format(deployment_type=ca_pillar.get("deployment_type", "standalone")))
      cmdline_elements.append('--address="{address}"'.format(address=ca_pillar.get("address", ":443" )))
      cmdline_elements.append('--with-ca-url="{ca_url}"'.format(ca_url=ca_pillar.get("ca_url", "https://{__salt__.['grains.get']('id')}" )))
      cmdline_elements.append('--provisioner="{provisioner}"'.format(provisioner=ca_pillar['initial_provisioner']))
      cmdline_elements.append('--name="{name}"'.format(name=ca_pillar['name']))

      if ca_pillar.get("ssh", True):
        cmdline_elements.append('--ssh')
        created_files.extend([
          '/var/lib/step-ca/.step/certs/ssh_host_ca_key.pub',
          '/var/lib/step-ca/.step/certs/ssh_user_ca_key.pub',
        ])

      if 'dns' in ca_pillar:
        for dns_name in ca_pillar.get('dns', []):
          cmdline_elements.append('--dns="{dns_name}"'.format(dns_name=dns_name))
      else:
        cmdline_elements.append('--dns="{dns_name}"'.format(dns_name=__salt__['grains.id']))


      config['step_ca_init'] = {
        'cmd.run': [
          {'name': ' '.join(cmdline_elements)},
          {'runas':    '_step-ca'},
          {'requires': ['step_ca_password_file']},
          {'creates':  created_files},
        ]
      }

      config['step_ca_service'] = {
        'service.running': [
          {'name': 'step-ca.service'},
          {'reload': True},
          {'requires': ['step_ca_init']}
        ]
      }

      local_ca_user = __salt__['pillar.get']('local_ca_user', None)

      for provisioner_name, provisioner_data in ca_pillar.get('provisioners',{}).items():

        cmdline_elements = ['/usr/bin/step', 'ca', 'provisioner', 'add', provisioner_name]
        password_file = f'/etc/step-ca/provisioner-{provisioner_name}-password.txt'
        section_name = f'step_ca_add_provisioner_{provisioner_name}'

        provisioner_options=provisioner_data.get('options', {})

        if provisioner_options.get('type') == 'JWK':
          cmdline_elements.append('--create')

        for option_name, value in provisioner_options.items():
          if option_name == 'password':
            value = password_file
            option_name = 'password-file'
          if isinstance(value, bool) and value:
            cmdline_elements.append(f'--{option_name}')
          else:
            cmdline_elements.append(f'--{option_name} "{value}"')

        if 'password' in provisioner_options:
          config[password_file] = {
            'file.managed': [
              {'user':  'root'},
              {'group': '_step-ca'},
              {'mode':  '0640'},
              {'requires': ['step_ca_package']},
              {'require_in': [section_name]},
              {'contents': provisioner_options['password']},
            ]
          }

        config[section_name] = {
          'cmd.run': [
            {'name':  ' '.join(cmdline_elements)},
            {'runas': '_step-ca'},
            {'unless': f'/usr/sbin/step-ca-has-provisioner {provisioner_name}'},
            {'require': ['step_ca_init']},
            {'onchanges_in': ['step_ca_reload']}
          ]
        }

        if 'settings' in provisioner_data:
          settings_section = f"step_ca_provisioner_{provisioner_name}_settings"
          config[settings_section] = {
            'module.run': [
              {'name': 'step_ca.patch_provisioner_config'},
              {'needle': provisioner_name },
              {'config': provisioner_data['settings']},
              {'require': [section_name]},
              {'onchanges_in': ['step_ca_reload']}
            ]
          }

        if local_ca_user and local_ca_user == provisioner_name:
          config['salt_step_directory'] = {
            'file.directory': [
              {'name': '/etc/salt/step'},
              {'user': 'root'},
              {'group': 'salt'},
              {'mode':  '0750'},
              {'requires': [section_name]},
            ]
          }
          config['salt_step_config_directory'] = {
            'file.directory': [
              {'name': '/etc/salt/step/config'},
              {'user': 'root'},
              {'group': 'salt'},
              {'mode':  '0750'},
              {'requires': ['salt_step_directory']},
            ]
          }

          salt_root_cert = "/etc/salt/step/config/root.crt"
          step_ca_defaults = '/var/lib/step-ca/.step/config/defaults.json'

          config['salt_step_copy_root_crt'] = {
            'file.copy': [
              {'name':     salt_root_cert },
              {'user':     'root'},
              {'group':    'salt'},
              {'mode':     "0640"},
              {'require': ['salt_step_config_directory']},
              { 'source': '/var/lib/step-ca/.step/certs/root_ca.crt' },
            ]
          }
          config['salt_step_client_password'] = {
            'file.managed': [
              {'user':     'root'},
              {'group':    'salt'},
              {'mode':     '0640'},
              {'name':     '/etc/salt/step/config/password'},
              {'contents': provisioner_options['password']},
              {'require':  ['salt_step_copy_root_crt']},
            ]
          }
          if os.path.exists(step_ca_defaults):
            ca_defaults = {}
            with open(step_ca_defaults, 'r') as f:
              ca_defaults = sujson.loads(f.read())

            if len(ca_defaults) > 0:
              step_client_config = {
                'ca-url':      ca_defaults["ca-url"],
                'fingerprint': ca_defaults["fingerprint"],
                'root':        salt_root_cert,
              }

              config['salt_step_client_config'] = {
                'file.serialize': [
                  {'name':  '/etc/salt/step/config/defaults.json'},
                  {'user':  'root'},
                  {'group': 'salt'},
                  {'mode':  '0640'},
                  {'require':  ['salt_step_copy_root_crt']},
                  {'serializer': 'json'},
                  {'serializer_opts': {'indent': 2}},
                  {'dataset': step_client_config},
                ]
              }
            else:
              log.error(f"Loading of the defaults from the CA failed {step_ca_defaults}")
          else:
            log.error(f"could not find {step_ca_defaults}")

      config['step_ca_reload'] = {
        'cmd.run': [
          {'name':   '/usr/bin/systemctl reload step-ca.service'},
          {'onlyif': '/usr/bin/systemctl is-active step-ca.service'},
        ]
      }
  return config