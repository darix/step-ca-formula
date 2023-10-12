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
{%- if 'ca' in pillar.step and 'enabled' in pillar.step.ca and pillar.step.ca.enabled %}
  {%- set ca_pillar = pillar.step.ca %}

# TODO: Install salt config
step_ca_package:
  pkg.installed:
    - names:
      - step-ca
      - jq

step_ca_password_file:
  file.managed:
    - name: /etc/step-ca/password.txt
    - user: root
    - group: '_step-ca'
    - mode: 640
    - requires:
      - step_ca_package
    - contents: {{ pillar.step.ca.password }}

  {%- set cmdline_elements = ['/usr/bin/step', 'ca', 'init', '--password-file="/etc/step-ca/password.txt"'] %}

  {%- do cmdline_elements.append('--deployment-type="{deployment_type}"'.format(deployment_type=ca_pillar.get("deployment_type", "standalone"))) %}
  {%- do cmdline_elements.append('--address="{address}"'.format(address=ca_pillar.get("address", ":443" ))) %}
  {%- do cmdline_elements.append('--with-ca-url="{ca_url}"'.format(ca_url=ca_pillar.get("ca_url", "https://" ~ grains.id ))) %}
  {%- do cmdline_elements.append('--provisioner="{provisioner}"'.format(provisioner=ca_pillar.initial_provisioner)) %}
  {%- do cmdline_elements.append('--name="{name}"'.format(name=ca_pillar.name)) %}

  {%- if 'dns' in ca_pillar %}
    {%- for dns_name in ca_pillar.dns %}
      {%- do cmdline_elements.append('--dns="{dns_name}"'.format(dns_name=dns_name)) %}
    {%- endfor %}
  {%- else %}
    {%- do cmdline_elements.append('--dns="{dns_name}"'.format(dns_name= grains.id)) %}
  {%- endif %}

step_ca_init:
  cmd.run:
    - name: {{ ' '.join(cmdline_elements) }}
    - runas: _step-ca
    - requires:
      - step_ca_password_file:
    - creates:
      - /var/lib/step-ca/.step/secrets/root_ca_key
      - /var/lib/step-ca/.step/secrets/intermediate_ca_key
      - /var/lib/step-ca/.step/config/ca.json
      - /var/lib/step-ca/.step/config/defaults.json
      - /var/lib/step-ca/.step/certs/intermediate_ca.crt
      - /var/lib/step-ca/.step/certs/root_ca.crt

step_ca_service:
  service.running:
    - name: step-ca.service
    - reload: True
    - requires:
      - step_ca_init

  {%- set local_ca_user = pillar.get("local_ca_user", None) %}

  {%- set active_provisioners = [] %}
  {%- if 'provisioners' in ca_pillar %}
    {%- for provisioner_name, provisioner_data in ca_pillar.provisioners.items() %}

      {%- set cmdline_elements = ['/usr/bin/step', 'ca', 'provisioner', 'add', provisioner_name] %}
      {%- set password_file = '/etc/step-ca/provisioner-' ~ provisioner_name ~ '-password.txt'%}

      {%- if provisioner_data.options.type == 'JWK' %}
        {%- do cmdline_elements.append('--create') %}
      {%- endif %}

      {%- for option_name, value in provisioner_data.options.items() %}
        {%- if option_name == 'password' %}
          {%- set value = password_file %}
          {%- set option_name = 'password-file' %}
        {%- endif %}
        {%- if  (value is sameas true) %}
          {%- do cmdline_elements.append('--{option_name}'.format(option_name=option_name)) %}
        {%- else %}
          {%- do cmdline_elements.append('--{option_name} "{option_value}"'.format(option_name=option_name, option_value=value )) %}
        {%- endif %}
      {%- endfor %}

      {%- if 'settings' in provisioner_data %}
      {%- endif %}

      {%- if 'password' in provisioner_data.options %}
{{ password_file }}:
  file.managed:
    - user: root
    - group: '_step-ca'
    - mode: 640
    - requires:
      - step_ca_package
    - contents: {{ provisioner_data.options.password }}
      {%- endif %}

      {%- set section_name = 'step_ca_add_provisioner_{provisioner_name}'.format(provisioner_name=provisioner_name) %}
      {%- do active_provisioners.append(section_name) %}
{{ section_name }}:
  cmd.run:
    - name:  {{ ' '.join(cmdline_elements) }}
    - runas: _step-ca
    - unless: /usr/sbin/step-ca-has-provisioner {{ provisioner_name }}
    - require:
      - step_ca_init
      {%- if 'password' in provisioner_data.options %}
      - {{ password_file }}
      {%- endif %}

      {%- if 'settings' in provisioner_data %}
step_ca_provisioner_{{ provisioner_name }}_settings:
  module.run:
    - name: step_ca.patch_provisioner_config
    - needle: {{ provisioner_name }}
    - config: {{ provisioner_data.settings | json }}
      {%- endif %}

      {%- if local_ca_user and local_ca_user == provisioner_name %}
salt_step_directory:
  file.directory:
    - name: /etc/salt/step
    - user: root
    - group: salt
    - mode: "0750"
    - require:
      - step_ca_init

salt_step_config_directory:
  file.directory:
    - name: /etc/salt/step/config
    - user: root
    - group: salt
    - mode: "0750"
    - require:
      - salt_step_directory

{%-   set ca_defaults = salt.cp.get_file_str('/var/lib/step-ca/.step/config/defaults.json') | load_json %}

{%-   set salt_root_cert = "/etc/salt/step/config/root.crt" %}

salt_step_copy_root_crt:
  file.managed:
    - name:     {{ salt_root_cert }}
    - user:     root
    - group:    salt
    - mode:     "0640"
    - require:
      - salt_step_config_directory
    - source: '/var/lib/step-ca/.step/certs/root_ca.crt'

salt_step_client_config:
  file.managed:
    - user:     root
    - group:    salt
    - mode:     "0640"
    - template: jinja
    - requires:
      - salt_step_copy_root_crt
    - name:     "/etc/salt/step/config/defaults.json"
    - source:   "salt://step-ca/files/etc/step/config/defaults.json.j2"
    - context:
      "config":
        "ca-url":       {{ ca_defaults["ca-url"] }}
        "fingerprint":  {{ ca_defaults["fingerprint"] }}
        "root":         {{ salt_root_cert }}

salt_step_client_password:
  file.managed:
    - user:     root
    - group:    salt
    - mode:     "0640"
    - name:     /etc/salt/step/config/password
    - contents: {{ provisioner_data.options.password }}
    - require:
      - salt_step_client_config
      {%- endif %}
    {%- endfor %}

step_ca_reload:
  cmd.run:
    - name: /usr/bin/systemctl reload step-ca.service
    - onlyif: /usr/bin/systemctl is-active step-ca.service
  {%- endif %}
{%- endif %}