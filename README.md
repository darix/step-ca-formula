## Required salt master config:

```
file_roots:
  base:
    - /srv/cfgmgmt/salt
    - /srv/cfgmgmt/formulas/step-ca-formula

# load the external pillar module
module_dirs:
  - /srv/cfgmgmt/formulas/step-ca-formula/modules

# this will fill in extra values like tokens/certs into the pillar
ext_pillar:
  - step_ca: {}
```