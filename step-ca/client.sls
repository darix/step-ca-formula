#!py
step_dir = '/etc/step'
def run():
  ca_pillar = __pillar__['step']['client_config']['ca']
  context = {
    'ca-url': ca_pillar['url'],
    'fingerprint': ca_pillar['root_cert']['fingerprint']
  }

  if 'contact_email' in ca_pillar:
    context['contact'] = ca_pillar['contact_email']

  if 'path' in ca_pillar['root_cert']:
    context['root'] = ca_pillar['root_cert']['path']

  config = {
    'step_client_package': {
      'pkg.installed': [
          { 'names': [ 'step-cli',  ] },
        ]
      },
    'step_client_config': {
      'file.managed': [
        { 'user':     'root' },
        { 'group':    'root' },
        { 'mode':     '0640' },
        { 'template': 'jinja' },
        { 'require':  [ 'step_client_package', ] },
        { 'name':     '{step_dir}/config/defaults.json'.format(step_dir=step_dir) },
        { 'source':   'salt://step-ca/files/etc/step/config/defaults.json.j2' },
        { 'context':
          { 'config': context },
        }
      ]
    }
  }
  return config