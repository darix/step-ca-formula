# Salt Formula for step-ca

## What is step-ca?

https://smallstep.com

You will need the `step` and `step-ca` binary. For openSUSE/SLE you can use the packages
from `home:darix:apps`.

## Required salt master config:

```
file_roots:
  base:
    - {{ salt_base_dir }}/salt
    - {{ formulas_base_dir }}/step-ca-formula

# load the external pillar module
module_dirs:
  - {{ formulas_base_dir }}/step-ca-formula/modules

# This will fill in extra values like tokens/certs into the pillar
# make the step_ca pillar the last entry.
ext_pillar:
  - step_ca: {}
```

## License

[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html)