  - if we have a timer based refresh without exposing the CA to the minion
    then that mode should enforce the force mode flag or we need to get the
    check-renewal call working within salt

- nothing deploys /etc/salt/step/config/defaults.json
- error handling for step calls
- we should have code that verifies that all SAN entries are present in the cert and force the deployment if not
- find out if there is a function to query if a certain state is defined and skip defining our cmd.run states in that case