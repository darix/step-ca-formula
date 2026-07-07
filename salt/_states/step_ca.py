step_ca_password_file = '/etc/step-ca/password.txt'
step_ca_config_file   = '/var/lib/step-ca/.step/config/ca.json'

import salt.utils.x509 as sux
from cryptography.hazmat.primitives import serialization
import os
import logging
import os.path
import salt.utils.json as sujson
from salt.exceptions import SaltConfigurationError, SaltRenderError, CommandExecutionError
from subprocess import PIPE, Popen

log = logging.getLogger(__name__)

def _get_step_executable():
    """
    Return the pass executable or raise an error
    """
    step_exec = salt.utils.path.which("step")
    if step_exec:
        return step_exec
    else:
        raise SaltRenderError("step unavailable")

# def _reencrypt_jwt(old_jwt, new_password):
#   step_executable = _get_step_executable
#   # Make sure environment variable HOME is set, since Pass looks for the
#   # password-store under ~/.password-store.
#   env = os.environ.copy()
#   env["HOME"] = os.path.expanduser("~")
#   cmd_decrypt = "step crypto jwe decrypt --password-file=/etc/step-ca/password.txt".split(' ')
#   cmd_encrypt = "step crypto jwe encrypt --password-file=/etc/step-ca/new_password.txt --alg PBES2-HS256+A128KW".split(' ')
#   cmd_jose    = "step crypto jose format".split(' ')
#   try:
#       # This fails with a complaint "cant not find /dev/tty"
#       proc_decrypt = Popen(cmd_decrypt,                            stdout=PIPE, stderr=PIPE, env=env, encoding="utf-8")
#       proc_encrypt = Popen(cmd_encrypt, stdin=proc_decrypt.stdout, stdout=PIPE, stderr=PIPE, env=env, encoding="utf-8")
#       proc_jose    = Popen(cmd_jose,    stdin=proc_encrypt.stdout, stdout=PIPE, stderr=PIPE, env=env, encoding="utf-8")
#       # proc_decrypt.stdout.close()
#       # proc_encrypt.stdout.close()
#       decrypt_data, decrypt_error = proc_decrypt.communicate(old_jwt)
#       decrypt_returncode          = proc_decrypt.returncode

#       encrypt_data, encrypt_error = proc_encrypt.communicate(input=new_password.strip() + "\n")
#       encrypt_returncode          = proc_encrypt.returncode

#       jose_data, jose_error       = proc_jose.communicate()
#       jose_returncode             = proc_jose.returncode

#   except (OSError, UnicodeDecodeError) as e:
#       step_data, step_error = "", str(e)
#       step_returncode = 1

#   log.error(f"jwe: {old_jwt}")
#   log.error(f"jwe: encrypt: rc:{encrypt_returncode} d:'{encrypt_data}' e:'{encrypt_error}'")
#   log.error(f"jwe: decrypt: rc:{decrypt_returncode} d:'{decrypt_data}' e:'{decrypt_error}'")
#   log.error(f"jwe: jose:    rc:{jose_returncode} d:'{jose_data}' e:'{jose_error}'")

#   return jose_data.rstrip("\r\n")

def _write_file_as_step_ca(new_filename, content, new_umask=0o077):
  old_umask = os.umask(new_umask)
  with open(new_filename, "wb") as f:
    f.write(content)
  uinfo = __salt__["user.info"]('_step-ca')
  os.chown(new_filename, uinfo["uid"], uinfo["gid"])
  os.umask(old_umask)

def update_main_provisioner(name):
  ret = {'name': name, 'result': None, 'changes': {}, 'comment': ""}

  if not(os.path.exists(step_ca_config_file)):
    ret["comment"] = f"File not found {step_ca_config_file}"
    ret["result"] = False
    return ret

  pillar_key = 'step:ca:password_change:new_password'
  new_password = __salt__['pillar.get'](pillar_key, None)

  if new_password is None:
    ret["comment"] = f"Failed to find the new password in {pillar_key}"
    ret["result"] = False
    return ret

  if __opts__["test"]:
    ret["comment"] = f"Private key '{name}' would be reencrypted"
    return ret

  with open(step_ca_config_file) as f:
    current_config = sujson.loads(f.read())

  old_encrypted_jwt = None

  for provisioner_config in current_config["authority"]["provisioners"]:
    if provisioner_config['name'] == name:
      old_encrypted_jwt = provisioner_config['encryptedKey']

  if old_encrypted_jwt is None:
    ret["comment"] = f"Did not find provisioner {name} in {step_ca_config_file}"
    ret["result"] = False
    return ret

  # # decrypted_key = _run_step_sub_command(, expect_output=True)
  new_encrypted_jwt = _reencrypt_jwt(old_encrypted_jwt, new_password)
  _write_file_as_step_ca('/var/lib/step-ca/newjwt', new_encrypted_jwt.encode())

  # ret["comment"] = f"Implementation pending as recreating the shell pipe in python did not work."
  return ret

def read_old_password_file():
  with open(step_ca_password_file) as f:
    return f.read().strip()

def load_private_key(pk, passphrase):
  try:
    return sux.load_privkey(pk=pk, passphrase=passphrase)
  except (CommandExecutionError) as e:
    None

def change_key_password(name):
  ret = {'name': name, 'result': None, 'changes': {}, 'comment': ""}

  if not(os.path.exists(name)):
    ret["comment"] = f"File not found {name}"
    ret["result"] = False
    return ret

  pillar_key = 'step:ca:password_change:new_password'
  new_password = __salt__['pillar.get'](pillar_key, None)

  if new_password is None:
    ret["comment"] = f"Failed to find the new password in pillar key: '{pillar_key}'"
    ret["result"] = False
    return ret

  loaded_key = load_private_key(pk=name, passphrase=new_password)

  if not (loaded_key is None):
    ret["comment"] = f"Key {name} is already using the new password"
    ret["result"] = True
    return ret

  if __opts__["test"]:
    ret["comment"] = f"Private key '{name}' would be reencrypted"
    return ret

  new_filename = name
  new_encrypted_key = loaded_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.TraditionalOpenSSL,
    encryption_algorithm=serialization.BestAvailableEncryption(new_password.encode())
  )

  _write_file_as_step_ca(new_filename, new_encrypted_key, new_umask=0o077)

  if load_private_key(pk=new_filename, passphrase=new_password) is None:
    ret["comment"] = f"Newly written file {new_filename} could not be reopened with the new password"
    ret["result"] = False
    return ret
  else:
    ret["result"] = True
    ret["changes"][name] = f"Private key updated with new passphrase"
    return ret
