#!/bin/bash
#
# This script finishes the deployment from softswitch VM
#
# Usage:
# bash deploy.sh prefix site
#
# Parameters:
#
# prefix: Two-letter prefix used during deployment (deployment 'deployPrefix' param)
# site:   Name of deployed site (deployment 'siteName' param)

prefix=$1
site=$2

deployRepo=https://github.com/eduararley/ta-softswitch.git
deployDir=/dev/shm/deploy

function pkg_install() {
  #
  # Install required packages
  #
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
    git\
    mysql-connector-odbc\
    nginx\
    patch\
    rh-php72-php-fpm\
    rh-php72-php-gd\
    rh-php72-php-mbstring\
    rh-php72-php-mysqlnd
}

function azure_getparams() {
  #
  # Initialize Azure keys
  #
  # Params:
  # $1: Prefix
  # $2: Site
  #
  local azUrl="https://management.azure.com"
  local azVaultUrl="https://vault.azure.net"

  local azKey=$(curl "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${azUrl}/" -H Metadata:true |\
    python -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
  local azSub=$(curl "${azUrl}/subscriptions?api-version=2016-09-01" -H "Authorization: Bearer ${azKey}" |\
    python -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")
  local azWrg=${azSub}/resourceGroups/${1}Workers
  local azDb=$(curl "${azUrl}${azWrg}/providers/Microsoft.DBforMariaDB/servers?api-version=2018-06-01" -H "Authorization: Bearer ${azKey}" |\
    python -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")
  local azVaultUri=$(curl "${azUrl}${azWrg}/providers/Microsoft.KeyVault/vaults/ta-swKeyVault?api-version=2018-02-14" -H "Authorization: Bearer ${azKey}" |\
    python -c "import sys,json; print(json.load(sys.stdin)['properties']['vaultUri'])")
  local azVaultKey=$(curl "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${azVaultUrl}" -H Metadata:true |\
    python -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
  local azDeplPwdVer=$(curl "${azVaultUri}secrets/${2}-admin/versions?maxresults=1&api-version=7.0" -H "Authorization: Bearer ${azVaultKey}" |\
    python -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")

  azGit=$(curl "${azUrl}${azWrg}/providers/Microsoft.Web/sites/ta-softsw-web/config/publishingcredentials/list?api-version=2016-08-01" -d "" -H "Authorization: Bearer ${azKey}" |\
    python -c "import sys,json; print(json.load(sys.stdin)['properties']['scmUri'])")/${2}-web.git
  azDbUrl=$(curl "${azUrl}${azDb}?api-version=2018-06-01" -H "Authorization: Bearer ${azKey}" |\
    python -c "import sys,json; print(json.load(sys.stdin)['properties']['fullyQualifiedDomainName'])")
  azDbUser=$(curl "${azUrl}${azDb}?api-version=2018-06-01" -H "Authorization: Bearer ${azKey}" |\
    python -c "import sys,json; print(json.load(sys.stdin)['properties']['administratorLogin'])")
  azDeplPwd=$(curl "${azDeplPwdVer}?api-version=7.0" -H "Authorization: Bearer ${azVaultKey}" |\
    python -c "import sys,json; print(json.load(sys.stdin)['value'])")
}

function odbc_config() {
  # Deploy ODBC
  cat > /etc/odbc.ini << EOF
[freeswitch]
DRIVER    = MySQL
SERVER    = ${azDbUrl}
DATABASE  = astpp
USER      = ${azDbUser}@${azDbUrl}
PASSWORD  = ${azDeplPwd}
EOF
}

function git_clone() {
  local current_dir=$(pwd)
  rm -rf ${deployDir}
  mkdir -p ${deployDir}
  cd ${deployDir}
  git clone --recursive ${deployRepo}
  cp -r ta-softswitch/ASTPP/web_interface/astpp web
  cd ${current_dir}
}

function git_patch() {
  local current_dir=$(pwd)
  cd ${deployDir}
  command cp ta-softswitch/config/BaltimoreCyberTrustRoot.crt.pem web
  patch < ta-softswitch/config/mysqli_driver.php.patch
  sed -i\
    "s/\$astpp_config \['dbhost'\]/\"${azDbUrl}\"/g"\
    web/application/config/database.php
  sed -i\
    "s/\$astpp_config \['dbuser'\]/\"${azDbUser}@${azDbUrl}\"/g"\
    web/application/config/database.php
  sed -i\
    "s/\$astpp_config \['dbpass'\]/\"${azDeplPwd}\"/g"\
    web/application/config/database.php
  sed -i\
    "s/\$astpp_config \['dbname'\]/\"astpp\"/g"\
    web/application/config/database.php
  cd ${current_dir}
}

function git_publish() {
  local current_dir=$(pwd)
  cd /dev/shm/web
  git init
  git config user.name autodeploy
  git config user.email autodeploy@${HOSTNAME}
  git remote add origin ${azGit}
  git add .
  git commit -m "Deploy"
  git push origin master
  cd ${current_dir}
}

function db_prepare() {
  yum -y install rh-mariadb103-mariadb
  local current_dir=$(pwd)
  command cp /dev/shm/ta-softswitch/ASTPP/database/astpp-4.0.sql /dev/shm/tmp
  command cp /dev/shm/ta-softswitch/ASTPP/database/astpp-4.0.1.sql /dev/shm/tmp
  sed -i 's/DEFINER=`root`@`localhost` //g' /dev/shm/astpp-4.0.sql
  sed -i 's/DEFINER=`root`@`localhost` //g' /dev/shm/astpp-4.0.1.sql
  sed -i 's/COLLATE=utf8mb4_0900_ai_ci/COLLATE=utf8mb4_general_ci/g' /dev/shm/astpp-4.0.sql
  sed -i 's/COLLATE=utf8mb4_0900_ai_ci/COLLATE=utf8mb4_general_ci/g' /dev/shm/astpp-4.0.1.sql
  /opt/rh/rh-mariadb103/root/usr/bin/mysql\
    -h ${azDbUrl} -u "${azDbUser}@${azDbUrl}" -p${azDeplPwd} --ssl\
    -e "DROP SCHEMA astpp; CREATE SCHEMA astpp;"
  /opt/rh/rh-mariadb103/root/usr/bin/mysql\
    -h ${azDbUrl} -u "${azDbUser}@${azDbUrl}" -p${azDeplPwd} astpp --ssl\
    < /dev/shm/astpp-4.0.sql
  /opt/rh/rh-mariadb103/root/usr/bin/mysql\
    -h ${azDbUrl} -u "${azDbUser}@${azDbUrl}" -p${azDeplPwd} astpp --ssl\
    < /dev/shm/astpp-4.0.1.sql
  cd ${current_dir}
  yum -y erase rh-mariadb103-*
}

curl -Lo /usr/local/src/ASTPP.tar.gz https://github.com/iNextrix/ASTPP/archive/v4.0.1.tar.gz
tar -C /usr/local/src -xf /usr/local/src/ASTPP.tar.gz
mv /usr/local/src/ASTPP-4.0.1 /usr/local/src/ASTPP
rm -f /usr/local/src/ASTPP.tar.gz

setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=permissive/g" /etc/selinux/config

touch /var/log/nginx/{astpp_access,astpp_error,fs_access,fs_error}_log
