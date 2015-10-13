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

# Put the command line parameters into named variables
ADMINUSER=$1

execname=$0

log() {
  echo "$(date): [${execname}] $@" 
}

#use the key from the key vault as the SSH private key

#talkemade: We are not using keyvault...

# openssl rsa -in /var/lib/waagent/*.prv -out /home/$ADMINUSER/.ssh/id_rsa
touch /home/$ADMINUSER/.ssh/id_rsa
chmod 600 /home/$ADMINUSER/.ssh/id_rsa
chown $ADMINUSER /home/$ADMINUSER/.ssh/id_rsa

file="/home/$ADMINUSER/.ssh/id_rsa"
key="/tmp/id_rsa.pem"
openssl rsa -in $file -outform PEM > $key

log "Adminuser: $ADMINUSER"
log "BEGIN: Starting detached script to finalize initialization"
sh initialize-cloudera-server.sh >/dev/null 2>&1
log "END: Detached script to finalize initialization running. PID: $!"

