import logging
import json

log = logging.getLogger(__name__)

def patch_provisioner_config( needle, config):
  pathname='/var/lib/step-ca/.step/config/ca.json'

  log.error("New config: {config}".format(config=config))
  json_string=''

  with open(pathname, 'r+') as open_file:
    parsed_config=json.load(open_file)

    provisioners= parsed_config['authority']['provisioners']

    for provisioner in provisioners:
      if provisioner['name'] == needle:
        changed_settings=[]
        for option, value in config.items():
            log.error("Setting {option} for {value}".format(option=option, value=value))
            if provisioner[option]!=value:
              changed_settings.append(option)
              provisioner[option]=value
        json_string=json.dumps(parsed_config, indent=4)
        open_file.seek(0)
        open_file.truncate()
        open_file.write(json_string)
  if len(changed_settings) > 0:
    return {'Applied settings': changed_settings}

  return None