{% if salt['pillar.get']('step:ca:password_change:new_password', '') != '' %}
{%- set new_password_file = "/etc/step-ca/new_password.txt" %}
{%- set main_keys = ['intermediate_ca_key', 'root_ca_key', 'ssh_host_ca_key', 'ssh_user_ca_key',] %}

step_cli_salt_pkg:
  pkg.latest:
    - pkgs:
      - step-ca-salt: '>= 0.28'
    - require_in:
      - rotate_jwk_key_encryption

step_ca_new_password:
  file.managed:
    - name: {{ new_password_file }}
    - user: root
    - group: _step-ca
    - mode: 0640
    - contents_pillar: 'step:ca:password_change:new_password'

# TODO: still not working
rotate_jwk_key_encryption:
  cmd.run:
    - name:   /usr/sbin/step-ca-change-jwe-passphrase change darix@nordisch.org
    - unless: /usr/sbin/step-ca-change-jwe-passphrase check  darix@nordisch.org
    - runas: _step-ca
    - require:
      - step_ca_new_password
    - require_in:
      - restart_step_ca

{%- for keyname in main_keys %}
rotate_key_file_{{ keyname }}:
  step_ca.change_key_password:
    - name: /var/lib/step-ca/.step/secrets/{{ keyname }}
    - require:
      - rotate_jwk_key_encryption
    - require_in:
      - restart_step_ca
{%- endfor %}

cleanup_new_password_file:
  file.absent:
    - name: {{ new_password_file }}
    - require_in:
      - restart_step_ca

step_ca_password_file:
  file.managed:
    - name: /etc/step-ca/password.txt
    - user: root
    - group: _step-ca
    - mode: 0640
    - contents_pillar: 'step:ca:password_change:new_password'
    - require_in:
      - restart_step_ca

restart_step_ca:
  service.restart:
    - name: step-ca.service
{%- endif %}
