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
    - {{ formulas_base_dir }}/step-ca-formula/salt/

pillar_roots:
  base:
    - {{ salt_base_dir }}/pillar/
    - {{ formulas_base_dir }}/step-ca-formula/pillar/

# load the external pillar module
module_dirs:
  - {{ formulas_base_dir }}/step-ca-formula/modules/

# This will fill in extra values like tokens/certs into the pillar
# make the step_ca pillar the last entry.
ext_pillar:
  - step_ca: {}
```

## cfgmgmt-template integration

if you are using our [cfgmgmt-template](https://github.com/darix/cfgmgmt-template) as a starting point the saltmaster you can simplify the setup with:

```
git submodule add https://github.com/darix/step-ca-formula formulas/step-ca
ln -s /srv/cfgmgmt/formulas/step-ca/config/enable_step_ca.conf /etc/salt/master.d/
systemctl restart saltmaster
```

then all you need is creating another config drop in for `local_ca_user: saltstack@example.com` as part of the /srv/cfgmgmt/config/ directory as it specific to your instance and should match what you configure in the pillar for your step-ca.

## Certificate mode

One way to deploy certificates is in certificate mode. Then the final certs will be injected into the pillar and then rolled out via the salt formula

```
nodegroups:
  step_ca_cert_mode_force_deploy_nodes: "I@step:client_config:certificate_mode:certificates and I@step:client_config:force_deploy:True"
```

That allows you to add a systemd timer/service around:

```
salt -N step_ca_cert_mode_force_deploy_nodes state.apply step-ca
```

That will deploy certificates and also do all the associated scriptlets.  

## Standalone Salt Master Step-CA Client  

This formula configures a Salt master to act as a Step-CA client. It enables the master to use an external Step CA to request tokens required for minion.  

Include only the Salt client state to your exsiting salt master:
```
include:
  - step-ca.salt-client
```
Set the pillar data for the Step CLI configuration:
```
step_salt_client:
  step_url: "https://step-external.example.org"
  step_fingerprint: "9c71f3ad9d931d4c4172efcd9bfc457c157dfef34a6829ab72dbb181ed29a083"
  step_root: "/etc/pki/trust/anchors/TRUSTED-STEP-EXTERNAL-CA.crt.pem"
  step_pass: "step-external_SUPER_SECRET"
```

## License

[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html)
