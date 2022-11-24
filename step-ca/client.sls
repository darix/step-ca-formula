{%- set step_dir = '/etc/step' %}
step_client_package:
  pkg.installed:
    - names:
      - step-cli

step_client_config:
  file.managed:
    - user: root
    - group: root
    - mode: 0640
    - template: jinja
    - require:
      - step_client_package
    - names:
      - {{ step_dir }}/config/defaults.json:
        - source: salt://step-ca/files/etc/step/config/defaults.json.j2