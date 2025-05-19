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

{%-   set salt_root_cert = "/etc/salt/step/config/root.crt" %}

{%- set salt_client = false %}
{%- if 'step_salt_client' in pillar %}
  {%- set salt_client = pillar.step_salt_client %}
{%- endif %}

{%- if salt_client %}
install_step_cli_pkg:
  pkg.installed:
    - pkgs:
      - step-cli

  {%- set ca_defaults = {"ca-url": salt_client["step_url"],
                         "fingerprint": salt_client["step_fingerprint"]}
  %}
  {%- set ca_root_source = salt_client.step_root %}
{% else %}
  {%- set ca_defaults = salt.cp.get_file_str('/var/lib/step-ca/.step/config/defaults.json') | load_json %}
  {%- set ca_root_source = '/var/lib/step-ca/.step/certs/root_ca.crt' %}
{%- endif %}

salt_step_directory:
  file.directory:
    - name: /etc/salt/step
    - user: root
    - group: salt
    - mode: "0750"
    {%- if not salt_client %}
    - require:
      - step_ca_init
    {%- endif %}

salt_step_config_directory:
  file.directory:
    - name: /etc/salt/step/config
    - user: root
    - group: salt
    - mode: "0750"
    - require:
      - salt_step_directory

salt_step_copy_root_crt:
  file.managed:
    - name:     {{ salt_root_cert }}
    - user:     root
    - group:    salt
    - mode:     "0640"
    - require:
      - salt_step_config_directory
    - source: {{ ca_root_source }}

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

{%- if salt_client %}
salt_step_client_password:
  file.managed:
    - user:     root
    - group:    salt
    - mode:     "0640"
    - name:     /etc/salt/step/config/password
    - contents: {{ salt_client.step_pass }}
    - require:
      - salt_step_client_config
{%- endif %}
