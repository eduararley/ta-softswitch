#!/bin/bash

#This script finishes the deployment from softswitch VM

# Install required packagesS
yum -y update
yum -y install\
  centos-release-scl\
  epel-release\
  https://files.freeswitch.org/repo/yum/centos-release/freeswitch-release-repo-0-1.noarch.rpm
yum -y install\
  freeswitch-application-curl\
  freeswitch-application-db\
  freeswitch-application-expr\
  freeswitch-application-hash\
  freeswitch-application-memcache\
  freeswitch-application-voicemail\
  freeswitch-event-format-cdr\
  freeswitch-event-json-cdr\
  freeswitch-format-local-stream\
  freeswitch-lua\
  freeswitch-sounds-en-us-callie-8000\
  freeswitch-sounds-music-8000\
  freeswitch-xml-curl\
  mysql-connector-odbc\
  nginx\
  rh-php72-php-fpm\
  rh-php72-php-gd\
  rh-php72-php-mbstring\
  rh-php72-php-mysqlnd

# Get passwords from Azure Key Vault
azUrl="https://management.azure.com"
azKey=$(curl "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${azUrl}/" -H Metadata:true |\
  python -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
azSub=$(curl "${azUrl}/subscriptions?api-version=2016-09-01" -H "Authorization: Bearer ${azKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")
azRg=$(curl "${azUrl}${azSub}/resourceGroups?api-version=2016-09-01" -H "Authorization: Bearer ${azKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")
azDb=$(curl "${azUrl}${azRg}/providers/Microsoft.DBforMariaDB/servers?api-version=2018-06-01" -H "Authorization: Bearer ${azKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")
azDbUrl=$(curl "${azUrl}${azDb}?api-version=2018-06-01" -H "Authorization: Bearer ${azKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['properties']['fullyQualifiedDomainName'])")
azDbUser=$(curl "${azUrl}${azDb}?api-version=2018-06-01" -H "Authorization: Bearer ${azKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['properties']['administratorLogin'])")
azVaultUri=$(curl "${azUrl}${azRg}/providers/Microsoft.KeyVault/vaults/ta-swKeyVault?api-version=2018-02-14" -H "Authorization: Bearer ${azKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['properties']['vaultUri'])")

azVaultUrl="https://vault.azure.net"
azVaultKey=$(curl "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${azVaultUrl}" -H Metadata:true |\
  python -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
azDeplPwdVer=$(curl "${azVaultUri}secrets/tasoftsw/versions?maxresults=1&api-version=7.0" -H "Authorization: Bearer ${azVaultKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")
azDeplPwd=$(curl "${azDeplPwdVer}?api-version=7.0" -H "Authorization: Bearer ${azVaultKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['value'])")

azWebFtp=$(curl "${azUrl}${azRg}/providers/Microsoft.Web/sites/ta-swWebApp/config/publishingcredentials/list?api-version=2016-08-01" -H "Authorization: Bearer ${azKey}" |\
  python -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")

# Deploy ODBC
cat > /etc/odbc.ini << EOF
[freeswitch]
DRIVER    = MySQL
SERVER    = ${azDbUrl}
DATABASE  = mysql
USER      = ${azDbUser}@${azDbUrl}
PASSWORD  = ${azDeplPwd}
EOF

curl -Lo /usr/local/src/ASTPP.tar.gz https://github.com/iNextrix/ASTPP/archive/v4.0.1.tar.gz
tar -C /usr/local/src -xf /usr/local/src/ASTPP.tar.gz
mv /usr/local/src/ASTPP-4.0.1 /usr/local/src/ASTPP
rm -f /usr/local/src/ASTPP.tar.gz

setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=permissive/g" /etc/selinux/config

touch /var/log/nginx/{astpp_access,astpp_error,fs_access,fs_error}_log
