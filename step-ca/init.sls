{%- if 'step' in pillar %}
include:
  - .client
  - .ssl-certificates
  - .ssh-certificates
  - .ca
{%- endif %}