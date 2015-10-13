#!/usr/bin/env bash

execname=$0

log() {
  echo "$(date): [${execname}] $@" >> /tmp/initialize-cloudera-server.log
}

log "Set cloudera-manager.repo to CM v5"
yum clean all >> /tmp/initialize-cloudera-server.log
rpm --import http://archive.cloudera.com/cdh5/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera >> /tmp/initialize-cloudera-server.log
wget http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/cloudera-manager.repo -O /etc/yum.repos.d/cloudera-manager.repo >> /tmp/initialize-cloudera-server.log
# this often fails so adding retry logic
n=0
until [ $n -ge 5 ]
do
    yum install -y oracle-j2sdk* cloudera-manager-daemons cloudera-manager-server >> /tmp/initialize-cloudera-server.log 2>> /tmp/initialize-cloudera-server.err && break
    n=$[$n+1]
    sleep 15s
done
if [ $n -ge 5 ]; then log "scp error $remote, exiting..." & exit 1; fi

#######################################################################################################################
log "installing external DB"
sudo yum install postgresql-server -y
bash install-postgresql.sh >> /tmp/initialize-cloudera-server.log 2>> /tmp/initialize-cloudera-server.err
#restart to make sure all configuration take effects
sudo service postgresql restart

log "finished installing external DB"
#######################################################################################################################

log "start cloudera-scm-server services"
service cloudera-scm-server start >> /tmp/initialize-cloudera-server.log

while ! (exec 6<>/dev/tcp/$(hostname)/7180) ; do log 'Waiting for cloudera-scm-server to start...'; sleep 15; done
log "END: master node deployments"

# trap file to indicate done
log "creating file to indicate finished"
touch /tmp/readyFile
