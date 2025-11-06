#!/bin/bash
set -x 

# Not sure this is causing other issues but has interfered with the reboot
systemctl disable --now dnf-automatic.timer

# Use local IP for FQDN instead of cluster IP
echo "10.0.2.2 imrhel.${GUID}.${DOMAIN}" >> /etc/hosts

## Convert a system to Image Mode
# Command line created by system-reinstall-bootc 
# Pulls the 9.6 basics image from quay to use as the baseline host in the lab
#
podman run --privileged --pid=host --user=root:root -v /var/lib/containers:/var/lib/containers -v /dev:/dev --security-opt label=type:unconfined_t -v /:/target quay.io/mmicene/im-day2-tgt:9.6 bootc install to-existing-root --acknowledge-destructive --root-ssh-authorized-keys /target/home/rhel/.ssh/authorized_keys

# With the new deployment created, we can copy directly into the /etc directory to make updates we want in the running bootc target
# The deployment checksum and resulting directory will change on each provision, this is how we detect the location
STATEROOT=$(ls -d /ostree/deploy/default/deploy/*/)

# Overwrite the image configs with the lab configs
# Add password root logins to sshD
echo "PermitRootLogin yes" >> $STATEROOT/etc/ssh/sshd_config.d/ansible_permit_root_login.conf

# Copy the existing credentials to the new bootc tree
# don't replace passwd/group files as this will cause issues with UID/GIDs
\cp -f /etc/shadow $STATEROOT/etc/shadow

# Use local IP for FQDN instead of cluster IP
echo "10.0.2.2 imrhel.${GUID}.${DOMAIN}" >> $STATEROOT/etc/hosts

