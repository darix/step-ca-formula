# Salt Formula for step-ca

## What is step-ca?

https://smallstep.com

You will need the `step` and `step-ca` binary. For openSUSE/SLE you can use the packages
from `home:darix:apps`.

## What can the formula do?

1. setup a CA
2. deploy ssl/ssh certs via a token and optionally enable the renewer services
3. deploy ssl/ssh certs via pillars (no connection from the minion to the CA needed)
4. restart affected services or even run custom commands after installing new certificates
   (for both renewer and salt only mode)

## installation

1. install formula
2. if you have an existing step-ca instance ... add a provisioner to your current instance with

```
su -s /bin/bash - _step-ca
pwgen 64 1 > salt-password
step ca provisioner add saltstack@example.com --create --ssh --password-file=$PWD/salt-password
```

install -D -d -m 0750 /etc/salt/step{,/config}
install -o root -g salt -m 0640 ~_step-ca/salt-password /etc/salt/step/config/password

## Required salt master config:

```
local_ca_user: saltstack@example.com

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