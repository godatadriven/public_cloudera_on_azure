#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# 
# See the License for the specific language governing permissions and
# limitations under the License.

ADMINUSER=$1
NODETYPE=$2
MYHOSTNAME=$3
DNS1IP=$4
DNS2IP=$5
DNS1NAME=$6
DNS2NAME=$7
HADOOPADMIN=$8
DOMAINNAME=$9

#talkemade: set up DNS /etc/resolv.conf

cat > /etc/dhclient-enter-hooks << EOF
#!/bin/sh
make_resolv_conf() {
echo "doing nothing to resolv.conf"
}
EOF

cat > /etc/resolv.conf << EOF
#!/bin/sh
search bigdata.intra.schiphol.nl
nameserver $DNS1IP
nameserver $DNS2IP
EOF

chmod a+x /etc/dhclient-enter-hooks

# Disable the need for a tty when running sudo and allow passwordless sudo for the admin user
sed -i '/Defaults[[:space:]]\+!*requiretty/s/^/#/' /etc/sudoers
echo "$ADMINUSER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
echo "$HADOOPADMIN ALL=(ALL) ALL" >> /etc/sudoers

# Mount and format the attached disks base on node type
if [ "$NODETYPE" == "masternode" ]
then
  bash ./prepare-masternode-disks.sh
elif [ "$NODETYPE" == "datanode" ]
then
  bash ./prepare-datanode-disks.sh
elif [ "$NODETYPE" == "gateway" ]
then
  bash ./prepare-gateway-disks.sh
else
  echo "#unknown type, default to datanode"
  bash ./prepare-datanode-disks.sh
fi

echo "Done preparing disks.  Now ls -la looks like this:"
ls -la /
# Create Impala scratch directory
numDataDirs=$(ls -la / | grep data | wc -l)
echo "numDataDirs:" $numDataDirs
let endLoopIter=(numDataDirs - 1)
for x in $(seq 0 $endLoopIter)
do 
  echo mkdir -p /data${x}/impala/scratch 
  mkdir -p /data${x}/impala/scratch
  chmod 777 /data${x}/impala/scratch
done

setenforce 0 >> /tmp/setenforce.out
getenforce > /tmp/beforeSelinux.out
sed -i 's^SELINUX=enforcing^SELINUX=disabled^g' /etc/selinux/config || true
getenforce > /tmp/afterSeLinux.out

/etc/init.d/iptables save
/etc/init.d/iptables stop
chkconfig iptables off

#remove old JDK
yum remove -y java-1.6.0-openjdk
yum remove -y java-1.7.0-openjdk 

#talkemade: disable IPv6
echo "NETWORKING_IPV6=no" >> /etc/sysconfig/network

echo "SEARCH=${DOMAINNAME}" >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo "NETWORKING_IPV6=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0

/etc/init.d/ip6tables save
/etc/init.d/ip6tables stop
chkconfig ip6tables off

# set up epel
rpm -ivh http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm

yum install -y ntp

#talkemade: configure ntp to use AD
sed -i 's/^server/#server/' /etc/ntp.conf
echo "server ${DNS1NAME} iburst" >> /etc/ntp.conf
echo "server ${DNS2NAME} iburst" >> /etc/ntp.conf

service ntpd start
service ntpd status
chkconfig ntpd on

yum install -y microsoft-hyper-v

yum install -y libselinux-python

echo never | tee -a /sys/kernel/mm/transparent_hugepage/enabled
echo "echo never | tee -a /sys/kernel/mm/transparent_hugepage/enabled" | tee -a /etc/rc.local
echo never | tee -a /sys/kernel/mm/redhat_transparent_hugepage/defrag
echo "echo never | tee -a /sys/kernel/mm/redhat_transparent_hugepage/defrag" | tee -a /etc/rc.local

echo vm.swappiness=1 | tee -a /etc/sysctl.conf
echo 1 | tee /proc/sys/vm/swappiness
ifconfig -a >> initialIfconfig.out; who -b >> initialRestart.out

echo net.ipv4.tcp_timestamps=0 >> /etc/sysctl.conf
echo net.ipv4.tcp_sack=1 >> /etc/sysctl.conf
echo net.core.netdev_max_backlog=25000 >> /etc/sysctl.conf
echo net.core.rmem_max=4194304 >> /etc/sysctl.conf
echo net.core.wmem_max=4194304 >> /etc/sysctl.conf
echo net.core.rmem_default=4194304 >> /etc/sysctl.conf
echo net.core.wmem_default=4194304 >> /etc/sysctl.conf
echo net.core.optmem_max=4194304 >> /etc/sysctl.conf
echo net.ipv4.tcp_rmem="4096 87380 4194304" >> /etc/sysctl.conf
echo net.ipv4.tcp_wmem="4096 65536 4194304" >> /etc/sysctl.conf
echo net.ipv4.tcp_low_latency=1 >> /etc/sysctl.conf
echo net.ipv4.tcp_adv_win_scale=1 >> /etc/sysctl.conf
sed -i "s/defaults        1 1/defaults,noatime        0 0/" /etc/fstab

#use the key from the key vault as the SSH authorized key
mkdir /home/$ADMINUSER/.ssh
chown $ADMINUSER /home/$ADMINUSER/.ssh
chmod 700 /home/$ADMINUSER/.ssh

# abij:  We don't use the private-key from the Vault. We will setup our own keyless login.
# ssh-keygen -y -f /var/lib/waagent/*.prv > /home/$ADMINUSER/.ssh/authorized_keys

touch /home/$ADMINUSER/.ssh/authorized_keys
chown $ADMINUSER /home/$ADMINUSER/.ssh/authorized_keys
chmod 600 /home/$ADMINUSER/.ssh/authorized_keys

# talkemade: changing hostname

# myhostname=`hostname`
# fqdnstring=`python -c "import socket; print socket.getfqdn('$myhostname')"`
sed -i "s/.*HOSTNAME.*/HOSTNAME=${MYHOSTNAME}/g" /etc/sysconfig/network
/etc/init.d/network restart

#disable password authentication in ssh
#sed -i "s/UsePAM\s*yes/UsePAM no/" /etc/ssh/sshd_config
#sed -i "s/PasswordAuthentication\s*yes/PasswordAuthentication no/" /etc/ssh/sshd_config
#/etc/init.d/sshd restart
