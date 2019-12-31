#!/bin/bash -e
# Creates some instances for networking-sfc demo/development:
# a web server, another instance to use as client
# three "service VMs" with two interface that will just route the packets to/from each interface

. $(dirname "${BASH_SOURCE}")/custom.sh
. $(dirname "${BASH_SOURCE}")/tools.sh

# Disable port security (else packets would be rejected when exiting the service VMs)
openstack network set --disable-port-security "${PRIV_NETWORK}"

# Create network ports for all VMs
openstack port create --network "${PRIV_NETWORK}" --fixed-ip ip-address=192.168.0.10 source_vm_port
openstack port create --network "${PRIV_NETWORK}" --fixed-ip ip-address=192.168.0.11 p1in
openstack port create --network "${PRIV_NETWORK}" --fixed-ip ip-address=192.168.0.12 p1out
openstack port create --network "${PRIV_NETWORK}" --fixed-ip ip-address=192.168.0.21 p2in
openstack port create --network "${PRIV_NETWORK}" --fixed-ip ip-address=192.168.0.22 p2out
openstack port create --network "${PRIV_NETWORK}" --fixed-ip ip-address=192.168.0.31 p3in
openstack port create --network "${PRIV_NETWORK}" --fixed-ip ip-address=192.168.0.32 p3out
openstack port create --network "${PRIV_NETWORK}" --fixed-ip ip-address=192.168.0.40 dest_vm_port

# SFC VMs
openstack server create --image "${IMAGE}" --flavor "${FLAVOR}" \
    --nic port-id="$(openstack port show -f value -c id p1in)" \
    --nic port-id="$(openstack port show -f value -c id p1out)" \
    --key-name "${SSH_KEYNAME}" vm1
openstack server create --image "${IMAGE}" --flavor "${FLAVOR}" \
    --nic port-id="$(openstack port show -f value -c id p2in)" \
    --nic port-id="$(openstack port show -f value -c id p2out)" \
    --key-name "${SSH_KEYNAME}" vm2
openstack server create --image "${IMAGE}" --flavor "${FLAVOR}" \
    --nic port-id="$(openstack port show -f value -c id p3in)" \
    --nic port-id="$(openstack port show -f value -c id p3out)" \
    --key-name "${SSH_KEYNAME}" vm3

# Demo VMs
openstack server create --image "${IMAGE}" --flavor "${FLAVOR}" \
    --nic port-id="$(openstack port show -f value -c id source_vm_port)" \
    --key-name "${SSH_KEYNAME}" source_vm
openstack server create --image "${IMAGE}" --flavor "${FLAVOR}" \
    --nic port-id="$(openstack port show -f value -c id dest_vm_port)" \
    --key-name "${SSH_KEYNAME}" dest_vm

# Floating IPs
SOURCE_FLOATING=$(openstack floating ip create "${PUB_NETWORK}" -f value -c floating_ip_address)
openstack server add floating ip source_vm ${SOURCE_FLOATING}
DEST_FLOATING=$(openstack floating ip create "${PUB_NETWORK}" -f value -c floating_ip_address)
openstack server add floating ip dest_vm ${DEST_FLOATING}
for i in 1 2 3; do
    floating_ip=$(openstack floating ip create "${PUB_NETWORK}" -f value -c floating_ip_address)
    declare VM${i}_FLOATING=${floating_ip}
    openstack server add floating ip vm${i} ${floating_ip}
done

# HTTP Flow classifier (catch the web traffic from source_vm to dest_vm)
SOURCE_IP=$(openstack port show source_vm_port -f value -c fixed_ips | grep "ip_address='[0-9]*\." | cut -d"'" -f2)
DEST_IP=$(openstack port show dest_vm_port -f value -c fixed_ips | grep "ip_address='[0-9]*\." | cut -d"'" -f2)
openstack sfc flow classifier create \
    --ethertype IPv4 \
    --source-ip-prefix ${SOURCE_IP}/32 \
    --destination-ip-prefix ${DEST_IP}/32 \
    --protocol tcp \
    --destination-port 80:80 \
    --logical-source-port source_vm_port \
    FC_tcp

# Get easy access to the VMs (single node)
route_to_subnetpool

# Create the port pairs for all 3 VMs
openstack sfc port pair create --ingress=p1in --egress=p1out PP1
openstack sfc port pair create --ingress=p2in --egress=p2out PP2
openstack sfc port pair create --ingress=p3in --egress=p3out PP3

# And the port pair group
openstack sfc port pair group create --port-pair PP1 --port-pair PP2 --port-pair PP3 PG1

# The complete chain
openstack sfc port chain create --port-pair-group PG1 --flow-classifier FC_tcp PC1
