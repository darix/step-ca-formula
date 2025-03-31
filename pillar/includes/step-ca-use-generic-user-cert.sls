step:
  certificates:
    user:
      generic:
        cn: {{ grains.id }}
        san:
          - {{ grains.host }}
          - {{ grains.id }}
          {%- for hostname in grains.fqdns|sort %}
          - {{ hostname }}
          {%- endfor %}
          {%- if "global_addresses" in grains %}
            {%- for ip in grains.global_addresses|sort %}
          - {{ ip }}
            {%- endfor %}
          {%- endif %}

