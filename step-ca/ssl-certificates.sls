#!py

# TODO: get the cert dir from the pillar
step_path = '/etc/step'
certificate_based_dir = '{step_path}/certs'.format(step_path=step_path)
cmdline_env = {
  'STEPPATH': step_path
}

def run():
    config = {}

    step_pillar = __pillar__['step']

    if 'certificates' in step_pillar:

      certificates_pillar = __pillar__['step']['certificates']

      certificate_mode = 'tokens'
      certificate_mode_uses_renewer = True

      drop_in_paths = []

      if 'mode' in certificates_pillar:
        certificate_mode = certificates_pillar['mode']

      if 'certificate_mode_uses_renewer' in certificates_pillar:
        certificate_mode_uses_renewer = certificates_pillar['certificate_mode_uses_renewer']

      for cert_type in ['host', 'user']:
          scope_cert_pillar = certificates_pillar[cert_type]

          for cert_name, cert_data in scope_cert_pillar.items():

            cert_name_type='{cert_name}.{cert_type}'.format( cert_name=cert_name, cert_type=cert_type, )
            base_path = '{basedir}/{cert_name_type}'.format( basedir=certificate_based_dir, cert_name_type=cert_name_type, )
            csr_path = '{base_path}.{extension}'.format(base_path=base_path, extension='csr')
            crt_path = '{base_path}.{extension}'.format(base_path=base_path, extension='cert.pem')
            key_path = '{base_path}.{extension}'.format(base_path=base_path, extension='key.pem')

            common_name = __grains__['id']

            if 'cn' in cert_data:
              common_name = cert_data['cn']

            section_name = 'step_client_{cert_type}_{cert_name}'.format( cert_type=cert_type, cert_name=cert_name, )
            service = 'cert-renewer@{instance}.timer'.format(instance=cert_name_type)

            service_deps = [ section_name+'_drop_in', 'stepca_systemd_daemon_reload', ]

            drop_in_dir  = '/etc/systemd/system/cert-renewer@{cert_name_type}.service.d'.format(cert_name_type=cert_name_type)
            drop_in_path = '{drop_in_dir}/salt.conf'.format(drop_in_dir=drop_in_dir)

            drop_in_paths.append(drop_in_path)

            drop_in_deps = [ section_name+'_drop_in_dir' ]

            drop_in_content="""
[Service]
# Reset env
Environment=
# use our paths
Environment=STEPPATH={step_path} \\
            CERT_LOCATION={certificate_based_dir}/%i.cert.pem \\
            KEY_LOCATION={certificate_based_dir}/%i.key.pem
# disable upstream ExecStartPost=
ExecStartPost=
""".format(certificate_based_dir=certificate_based_dir,step_path=step_path)

            if 'affected_services' in cert_data:
              # drop_in_content+="ExecStartPost=systemctl try-reload-or-restart {services_list}\n".format(services_list=' '.join(cert_data['affected_services']))
              for service in cert_data['affected_services']:
                drop_in_content+="ExecStartPost=/usr/bin/systemctl is-active {service} && /usr/bin/systemctl try-reload-or-restart {service}\n".format(service=service)

            if 'exec_start_post' in cert_data:
              if isinstance(cert_data['exec_start_post'], str):
                  drop_in_content+="ExecStartPost={line}\n".format(line=cert_data['exec_start_post'])
              else:
                for line in cert_data['exec_start_post']:
                  drop_in_content+="ExecStartPost={line}\n".format(line=line)

            config[section_name] = {}

            if 'tokens' == certificate_mode:
              # we do not need to specify the --san entries here as they are encoded in the token.
              cmdline='/usr/bin/step ca certificate --force --token="{token}" {options} "{commonname}" "{crt_path}" "{key_path}"'.format(
                commonname=common_name,
                token=cert_data['token'],
                options=cert_data['options'],
                crt_path=crt_path,
                key_path=key_path,
              )

              drop_in_deps.append(section_name+'_token_cmd')

              config[section_name+'_token_cmd'] = {
                'cmd.run': [
                  { 'name':    cmdline                   },
                  { 'env':     cmdline_env               },
                  { 'require': [ 'step_client_config', ] },
                  { 'creates': [ crt_path, key_path, ]   },
                ]
              }

            elif 'certificates' == certificate_mode:

              drop_in_deps.append(section_name+'_key')
              drop_in_deps.append(section_name+'_cert')

              config[section_name+'_key'] = {
                'file.managed': [
                  { 'name':     key_path                 },
                  { 'user':     'root'                   },
                  { 'group':    'root'                   },
                  { 'mode':     '0640'                   },
                  { 'contents': cert_data['key']         },
                  { 'require':  [ 'step_client_config' ] },
                ]
              }

              config[section_name+'_cert'] = {
                'file.managed': [
                  { 'name':     crt_path                  },
                  { 'user':     'root'                    },
                  { 'group':    'root'                    },
                  { 'mode':     '0640'                    },
                  { 'contents': cert_data['cert']         },
                  { 'require':  [ 'step_client_config', ] },
                ]
              }

            if certificate_mode_uses_renewer:

              config[section_name+'_drop_in_dir'] = {
                'file.directory': [
                  { 'name':  drop_in_dir },
                  { 'user':  'root'      },
                  { 'group': 'root'      },
                  { 'mode':  '0750'      },
                ],
              }

              config[section_name+'_drop_in'] = {
                'file.managed': [
                  { 'name':     drop_in_path    },
                  { 'user':     'root'          },
                  { 'group':    'root'          },
                  { 'mode':     '0640'          },
                  { 'contents': drop_in_content },
                  { 'require':  drop_in_deps    },
                ],
              }

              config[section_name+'_service'] = {
                'service.running': [
                  { 'name':     service      },
                  { 'enable':   True         },
                  { 'require':  service_deps },
                ]
              }

              config['stepca_systemd_daemon_reload'] = {
                'module.run': [
                  { 'name':       'service.systemctl_reload' },
                  { 'onchanges':  drop_in_paths              },
                ]
              }
            else:
              config[section_name+'_service'] = {
                'service.dead': [
                  { 'name':     service      },
                  { 'enable':   False        },
                ]
              }

              if 'affected_services' in cert_data:
                for service in cert_data['affected_services']:
                  config[section_name + '_restart_service_{index}'.format(index=loop.counter)] = {
                    'cmd.run': [
                      { 'name': "/usr/bin/systemctl is-active {service} && /usr/bin/systemctl try-reload-or-restart {service}\n".format(service=service) }
                    ]
                  }

              if 'exec_start_post' in cert_data:
                if isinstance(cert_data['exec_start_post'], str):
                    config[section_name + '_exec_start_post'] = {
                      'cmd.run': [
                        { 'name': cert_data['exec_start_post'] }
                      ]
                    }
                else:
                  for line in cert_data['exec_start_post']:
                    config[section_name + '_exec_start_post_{index}'.format(index=loop.counter)] = {
                      'cmd.run': [
                        { 'name': line }
                      ]
                    }

    return config
