#!/bin/bash
echo -e "This script does a quick and dirty install of the puppet8 agent on ubuntu 22.04 systems for the lab.\nIt has a hard-coded IP address for the hostvm.\nIt requests a certificate from the puppet master."

echo "Adding puppet server to /etc/hosts file if necessary"
grep -q ' puppet$' /etc/hosts || sudo sed -i -e '$a172.16.1.1 puppet' /etc/hosts

echo "Setting up for puppet8 and installing agent on $(hostname)"
wget -q https://apt.puppet.com/puppet8-release-jammy.deb
sudo dpkg -i puppet8-release-jammy.deb
sudo apt-get -qq update

echo "Restarting snapd.seeded.service can take a long time, do not interrupt it - installing puppet agent"
NEEDRESTART_MODE=a sudo apt-get -y install puppet-agent >/dev/null

echo "Setting up PATH to include puppet tools in ~/.bashrc"
echo 'PATH=$PATH:/opt/puppetlabs/bin' >> ~/.bashrc

cat <<'EOF'
Requesting a certificate from puppet master.

On the puppet master, run:

  sudo /opt/puppetlabs/bin/puppetserver ca sign --all

to complete the request.
EOF

/opt/puppetlabs/bin/puppet ssl bootstrap &
