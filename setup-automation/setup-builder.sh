#!/bin/bash
set -x

# Packages are in instances.yaml, turn on libvirtd and set up nss support
systemctl enable --now libvirtd
sed -i 's/hosts:\s\+ files/& libvirt libvirt_guest/' /etc/nsswitch.conf

# Log into terms based registry and stage bootc and bib images
mkdir -p ~/.config/containers
cat<<EOF> ~/.config/containers/auth.json
{
    "auths": {
      "registry.redhat.io": {
        "auth": "${REGISTRY_PULL_TOKEN}"
      }
    }
  }
EOF

# Pull the needed images to minimize waiting during the lab
# Will also need staging and creds for testing
# UBI
podman pull registry.access.redhat.com/ubi9/ubi
# RHEL 9.6 bases
BOOTC_RHEL_VER=9.6
podman pull registry.redhat.io/rhel9/rhel-bootc:$BOOTC_RHEL_VER registry.redhat.io/rhel9/bootc-image-builder:$BOOTC_RHEL_VER
# RHEL 10 bases
BOOTC_RHEL_VER=10.0
podman pull registry.redhat.io/rhel10/rhel-bootc:$BOOTC_RHEL_VER registry.redhat.io/rhel10/bootc-image-builder:$BOOTC_RHEL_VER

# set up SSL for fully functioning registry
# Enable EPEL for RHEL 10
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
dnf install -y certbot

# request certificates but don't log keys
set +x
certbot certonly --eab-kid "${ZEROSSL_EAB_KEY_ID}" --eab-hmac-key "${ZEROSSL_HMAC_KEY}" --server "https://acme.zerossl.com/v2/DV90" --standalone --preferred-challenges http -d registry-"${GUID}"."${DOMAIN}" --non-interactive --agree-tos -m trackbot@instruqt.com -v

# Don't leak password to users
rm /var/log/letsencrypt/letsencrypt.log

# reset tracing
set -x

# run a local registry with the provided certs
podman run --privileged -d \
  --name registry \
  -p 443:5000 \
  -p 5000:5000 \
  -v /etc/letsencrypt/live/registry-"${GUID}"."${DOMAIN}"/fullchain.pem:/certs/fullchain.pem \
  -v /etc/letsencrypt/live/registry-"${GUID}"."${DOMAIN}"/privkey.pem:/certs/privkey.pem \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/fullchain.pem \
  -e REGISTRY_HTTP_TLS_KEY=/certs/privkey.pem \
  quay.io/mmicene/registry:2

# For the target bootc system build, we need to set up a few config files to operate in the lab environment
# create sudoers drop in and etc structure to add to container
mkdir -p ~/etc/sudoers.d/
echo "%wheel  ALL=(ALL)   NOPASSWD: ALL" >> ~/etc/sudoers.d/wheel

# turn off complexity checks in target for passwords to ease the learner experience
mkdir -p ~/etc/security
cat <<EOF> ~/etc/security/pwquality.conf
# Configuration for systemwide password quality limits
# Defaults:
#
# Number of characters in the new password that must not be present in the
# old password.
# difok = 1
#
# Minimum acceptable size for the new password (plus one if
# credits are not disabled which is the default). (See pam_cracklib manual.)
# Cannot be set to lower value than 6.
minlen = 6
#
# The maximum credit for having digits in the new password. If less than 0
# it is the minimum number of digits in the new password.
# dcredit = 0
#
# The maximum credit for having uppercase characters in the new password.
# If less than 0 it is the minimum number of uppercase characters in the new
# password.
# ucredit = 0
#
# The maximum credit for having lowercase characters in the new password.
# If less than 0 it is the minimum number of lowercase characters in the new
# password.
# lcredit = 0
#
# The maximum credit for having other characters in the new password.
# If less than 0 it is the minimum number of other characters in the new
# password.
# ocredit = 0
#
# The minimum number of required classes of characters for the new
# password (digits, uppercase, lowercase, others).
# minclass = 0
#
# The maximum number of allowed consecutive same characters in the new password.
# The check is disabled if the value is 0.
# maxrepeat = 0
#
# The maximum number of allowed consecutive characters of the same class in the
# new password.
# The check is disabled if the value is 0.
# maxclassrepeat = 0
#
# Whether to check for the words from the passwd entry GECOS string of the user.
# The check is enabled if the value is not 0.
# gecoscheck = 0
#
# Whether to check for the words from the cracklib dictionary.
# The check is enabled if the value is not 0.
dictcheck = 0
#
# Whether to check if it contains the user name in some form.
# The check is enabled if the value is not 0.
# usercheck = 0
#
# Length of substrings from the username to check for in the password
# The check is enabled if the value is greater than 0 and usercheck is enabled.
# usersubstr = 0
#
# Whether the check is enforced by the PAM module and possibly other
# applications.
# The new password is rejected if it fails the check and the value is not 0.
enforcing = 0
#
# Path to the cracklib dictionaries. Default is to use the cracklib default.
# dictpath =
#
# Prompt user at most N times before returning with error. The default is 1.
# retry = 3
#
# Enforces pwquality checks on the root user password.
# Enabled if the option is present.
# enforce_for_root
#
# Skip testing the password quality for users that are not present in the
# /etc/passwd file.
# Enabled if the opt
EOF

# create config.json for BIB to add a user / pass
cat <<EOF> ~/config.json
{
  "blueprint": {
    "customizations": {
      "user": [
        {
          "name": "core",
          "password": "redhat",
           "groups": [
	            "wheel"
	          ]
        }
      ]
    }
  }
}
EOF

# create basic UBI containerfile
cat <<EOF> /root/Containerfile
FROM registry.access.redhat.com/ubi9/ubi

RUN dnf install -y httpd
RUN echo "Hello Red Hat" > /var/www/html/index.html

ENTRYPOINT /usr/sbin/httpd -DFOREGROUND
EOF

# create basic bootc containerfile
cat <<EOF> /root/Containerfile.el10
FROM registry.redhat.io/rhel10/rhel-bootc:$BOOTC_RHEL_VER

ADD etc /etc

RUN dnf install -y httpd
RUN systemctl enable httpd

EOF

# Add name based resolution for internal IPs
echo "10.0.2.2 builder.${GUID}.${DOMAIN}" >> /etc/hosts
echo "10.0.2.2 registry-${GUID}.${DOMAIN}" >> /etc/hosts
cp /etc/hosts ~/etc/hosts

# Script that manages the VM SSH session tab
# Waits for the domain to start and networking before attempting to SSH to guest
cat <<'EOF'> /root/wait_for_bootc_vm.sh
echo "Waiting for VM 'bootc-vm' to be running..."
VM_READY=false
VM_STATE=""
VM_NAME=bootc-vm
while true; do
    VM_STATE=$(virsh domstate "$VM_NAME" 2>/dev/null)
    if [[ "$VM_STATE" == "running" ]]; then
        VM_READY=true
        break
    fi
    sleep 10
done
echo "Waiting for SSH to be available..."
NODE_READY=false
while true; do
    if ping -c 1 -W 1 ${VM_NAME} &>/dev/null; then
        NODE_READY=true
        break
    fi
    sleep 5
done
ssh core@${VM_NAME}
EOF

chmod u+x /root/wait_for_bootc_vm.sh
#
# Script that manages the ISO SSH session tab
# Waits for the domain to start and networking before attempting to SSH to guest
cat <<'EOF'> /root/wait_for_iso_vm.sh
echo "Waiting for VM 'iso-vm' to be running..."
VM_READY=false
VM_STATE=""
VM_NAME=iso-vm
while true; do
    VM_STATE=$(virsh domstate "$VM_NAME" 2>/dev/null)
    if [[ "$VM_STATE" == "running" ]]; then
        VM_READY=true
        break
    fi
    sleep 10
done
echo "Waiting for SSH to be available..."
NODE_READY=false
while true; do
    if ping -c 1 -W 1 ${VM_NAME} &>/dev/null; then
        NODE_READY=true
        break
    fi
    sleep 5
done
ssh core@${VM_NAME}
EOF

chmod u+x /root/wait_for_iso_vm.sh
