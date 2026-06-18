{% if salt['pillar.get']('step:ca:password_change:new_password', '') != '' %}
{%- set main_keys = ['intermediate_ca_key', 'root_ca_key', 'ssh_host_ca_key', 'ssh_user_ca_key',] %}
stop_step_ca:
  service.dead:
    - name: step-ca.service

# TODO: still not working
# rotate_jwk_key_encryption:
#   step_ca.update_main_provisioner:
#     - name: { { pillar.step.ca.initial_provisioner } }
#     - require:
#       - stop_step_ca
#     - require_in:
#       - restart_step_ca

{%- for keyname in main_keys %}
rotate_key_file_{{ keyname }}:
  step_ca.change_key_password:
    - name: /var/lib/step-ca/.step/secrets/{{ keyname }}
    - require:
      - stop_step_ca
    - require_in:
      - restart_step_ca
{%- endfor %}

restart_step_ca:
  service.running:
    - name: step-ca.service
{%- endif %}
