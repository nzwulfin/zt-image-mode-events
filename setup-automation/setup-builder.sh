#!/bin/bash
set -x

# Set up the infrastructure environemnt
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
BOOTC_RHEL_VER=10.1
podman pull registry.redhat.io/rhel10/rhel-bootc:$BOOTC_RHEL_VER registry.redhat.io/rhel10/bootc-image-builder:$BOOTC_RHEL_VER

# Remove pull credentials
# rm ~/.config/containers/auth.json

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

# set up http based auth for registry
mkdir .auth
podman run --rm --entrypoint htpasswd quay.io/hummingbird/httpd:2 -Bbn core redhat > .auth/htpasswd
podman rmi quay.io/hummingbird/httpd:2

# run a local registry with authenication and the provided certs
podman run --privileged -d \
  --name registry \
  -p 443:5000 \
  -v `pwd`/.auth:/auth:Z  \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
  -v /etc/letsencrypt/live/registry-"${GUID}"."${DOMAIN}"/fullchain.pem:/certs/fullchain.pem \
  -v /etc/letsencrypt/live/registry-"${GUID}"."${DOMAIN}"/privkey.pem:/certs/privkey.pem \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/fullchain.pem \
  -e REGISTRY_HTTP_TLS_KEY=/certs/privkey.pem \
  quay.io/mmicene/registry:2

# Add name based resolution for internal IPs
echo "10.0.2.2 builder.${GUID}.${DOMAIN}" >> /etc/hosts
echo "10.0.2.2 registry-${GUID}.${DOMAIN}" >> /etc/hosts
cp /etc/hosts ~/etc/hosts

# Script that manages the VM SSH session tab
# Waits for the domain to start and networking before attempting to SSH to guest
cat <<'EOF'> /root/.wait_for_bootc_vm.sh
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

chmod u+x /root/.wait_for_bootc_vm.sh
#
# Script that manages the ISO SSH session tab
# Waits for the domain to start and networking before attempting to SSH to guest
cat <<'EOF'> /root/.wait_for_iso_vm.sh
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

chmod u+x /root/.wait_for_iso_vm.sh

# Clone the git repo for the application to deploy
git clone --single-branch --branch bootc https://github.com/rhel-labs/python-hostinfo.git /root/bootc-version

# Clone the samples directory and move it to the working home directory
git clone --single-branch --branch ${GIT_BRANCH} --no-checkout --depth=1 --filter=tree:0 ${GIT_REPO} /tmp/lab
git -C /tmp/lab sparse-checkout set --no-cone /samples
git -C /tmp/lab checkout
if [ -d /tmp/lab/samples ]; then 
    cp -r /tmp/lab/samples /root/samples
    mv /tmp/lab/samples samples
fi
rm -rf /tmp/lab

