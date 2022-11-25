- Implement a force flag for step:ssh and step:certificates
  force: disabled
    creates: flag is added to each step certificate cmd.run block
  force: enabled
    creates flag is not added and certs will be auto generated
  - if we have a timer based refresh without exposing the CA to the minion
    then that mode should enforce the force mode flag or we need to get the
    check-renewal call working within salt