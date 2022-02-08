#!/bin/bash
#
# Copyright 2016,2020 JS Foundation and other contributors, https://js.foundation/
# Copyright 2015,2016 IBM Corp.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Node-RED Installer for DEB based systems

umask 0022
tgta12=12.22.9   # need armv6l latest from https://unofficial-builds.nodejs.org/download/release/
tgtl12=12.16.3   # need x86 latest from https://unofficial-builds.nodejs.org/download/release/
tgta14=14.18.3   # need armv6l latest from https://unofficial-builds.nodejs.org/download/release/
tgtl14=14.18.3   # need x86 latest from https://unofficial-builds.nodejs.org/download/release/
tgta16=16.13.2    # need armv6l latest from https://unofficial-builds.nodejs.org/download/release/
tgtl16=16.13.2    # need x86 latest from https://unofficial-builds.nodejs.org/download/release/

usage() {
  cat << EOL
Usage: $0 [options]

Options:
  --help            display this help and exits
  --confirm-root    install as root without asking confirmation
  --confirm-install confirm installation without asking confirmation
  --confirm-pi      confirm installation of PI specific nodes without asking confirmation
  --skip-pi         skip installing PI specific nodes without asking confirmation
  --restart         restart service if install succeeds
  --update-nodes    run npm update on existing installed nodes (within scope of package.json)
  --nodered-user    specify the user to run as, useful for installing as sudo - e.g. --nodered-user=pi
  --nodered-version if not set, the latest version is used - e.g. --nodered-version="1.3.4"
  --node12          if set, forces install of major version of nodejs 12 LTS
  --node14          if set, forces install of major version of nodejs 14 LTS
  --node16          if set, forces install of major version of nodejs 16 LTS
                    if none set, install nodejs 14 LTS if nodejs version is less than 12,
                    otherwise leave current install
EOL
}

NODE_VERSION=""
if [ $# -gt 0 ]; then
  # Parsing parameters
  while (( "$#" )); do
    case "$1" in
      --help)
        usage && exit 0
        shift
        ;;
      --confirm-root)
        CONFIRM_ROOT="y"
        shift
        ;;
      --confirm-install)
        CONFIRM_INSTALL="y"
        shift
        ;;
      --skip-pi)
        CONFIRM_PI="n"
        shift
        ;;
      --confirm-pi)
        CONFIRM_PI="y"
        shift
        ;;
      --node12)
        NODE_VERSION="12"
        shift
        ;;
      --node14)
        NODE_VERSION="14"
        shift
        ;;
      --node16)
        NODE_VERSION="16"
        shift
        ;;
      --restart)
        RESTART="y"
        shift
        ;;
      --update-nodes)
        UPDATENODES="y"
        shift
        ;;
      --nodered-version=*)
        NODERED_VERSION="${1#*=}"
        shift
        ;;
      --nodered-user=*)
        NODERED_USER="${1#*=}"
        shift
        ;;
      --) # end argument parsing
        shift
        break
        ;;
      -*|--*=) # unsupported flags
        echo "Error: Unsupported flag $1" >&2
        exit 1
        ;;
    esac
  done
fi

# helper function to test for existance of node and npm
function HAS_NODE {
    if [ -x "$(command -v node)" ]; then return 0; else return 1; fi
}
function HAS_NPM {
    if [ -x "$(command -v npm)" ]; then return 0; else return 1; fi
}

# check for apt and systemctrl (set flags for later use and log if not found)
if [ -x "$(command -v apt)" ]; then
    APTOK=true;
else
    APTOK=false
    echo "apt not found. Node/npm install will be skipped" | sudo tee -a /var/log/nodered-install.log >>/dev/null
fi
if [ -x "$(command -v systemctl)" ]; then
    SYSTEMDOK=true;
else
    SYSTEMDOK=false
    echo "systemctl not found. shortcuts/services setup will be skipped" | sudo tee -a /var/log/nodered-install.log >>/dev/null
fi

echo -ne "\033[2 q"
if [[ -e /mnt/dietpi_userdata ]]; then
    echo -ne "\n\033[1;32mDiet-Pi\033[0m detected - only going to add the  \033[0;36mnode-red-start, -stop, -log\033[0m  commands.\n"
    echo -ne "Flow files and other things worth backing up can be found in the \033[0;36m/mnt/dietpi_userdata/node-red\033[0m directory.\n\n"
    echo -ne "Use the  \033[0;36mdietpi-software\033[0m  command to un-install and re-install \033[38;5;88mNode-RED\033[0m.\n"
    echo "journalctl -f -n 25 -u node-red -o cat" > /usr/bin/node-red-log
    chmod +x /usr/bin/node-red-log
    echo "systemctl stop node-red" > /usr/bin/node-red-stop
    chmod +x /usr/bin/node-red-stop
    echo "systemctl start node-red" > /usr/bin/node-red-start
    echo "journalctl -f -n 0 -u node-red -o cat" >> /usr/bin/node-red-start
    chmod +x /usr/bin/node-red-start
else

if [ "$EUID" == "0" ]; then
# if [[ $SUDO_USER != "" ]]; then
  echo -en "\nroot user detected. Typical installs should be done as a regular user.\r\n"
  echo -en "If you are running this script using sudo, please cancel and rerun without sudo.\r\n"
  echo -en "--nodered-user can be used to specify the user otherwise installation will happen under /root.\r\n"
  echo -en "If you know what you are doing as root, please continue.\r\n\r\n"

  yn="${CONFIRM_ROOT}"
  [ ! "${yn}" ] && read -t 10 -p "Are you really sure you want to install as root ? (y/N) ? " yn
  case $yn in
    [Yy]* )
    ;;
    * )
      echo " "
      exit 1
    ;;
  esac
  id -u nobody &>/dev/null || adduser --no-create-home --shell /dev/null --disabled-password --disabled-login --gecos '' nobody &>/dev/null
fi

# setup user, home and group
if [[ "$NODERED_USER" == "" ]]; then
    NODERED_HOME=$HOME
    NODERED_USER=$USER
    NODERED_GROUP=`id -gn`
else
    NODERED_GROUP="$NODERED_USER"
    NODERED_HOME="/home/$NODERED_USER"
fi

if [[ "$(uname)" != "Darwin" ]]; then
if curl -I https://registry.npmjs.org/@node-red/util  >/dev/null 2>&1; then
echo -e '\033]2;'$NODERED_USER@`hostname`:  Node-RED update'\007'
echo " "
echo "This script checks the version of node.js installed is 12 or greater. It will try to"
echo "install node 14 if none is found. It can optionally install node 12, 14 or 16 LTS for you."
echo " "
echo "If necessary it will then remove the old core of Node-RED, before then installing the latest"
echo "version. You can also optionally specify the version required."
echo " "
echo "It also tries to run 'npm rebuild' to refresh any extra nodes you have installed"
echo "that may have a native binary component. While this normally works ok, you need"
echo "to check that it succeeds for your combination of installed nodes."
echo " "
echo "To do all this it runs commands as root - please satisfy yourself that this will"
echo "not damage your Pi, or otherwise compromise your configuration."
echo "If in doubt please backup your SD card first."
echo " "
echo "See the optional parameters by re-running this command with --help"
echo " "
if [[ -e $NODERED_HOME/.nvm ]]; then
    echo -ne '\033[1mNOTE:\033[0m We notice you are using \033[38;5;88mnvm\033[0m. Please ensure it is running the current LTS version.\n'
    echo -ne 'Using nvm is NOT RECOMMENDED. Node-RED will not run as a service under nvm.\r\n\n'
fi

yn="${CONFIRM_INSTALL}"
[ ! "${yn}" ] && read -p "Are you really sure you want to do this ? [y/N] ? " yn
case $yn in
    [Yy]* )
        echo ""
        EXTRANODES=""
        EXTRAW="update"

        response="${CONFIRM_PI}"
        [ ! "${response}" ] && read -r -t 15 -p "Would you like to install the Pi-specific nodes ? [y/N] ? " response
        if [[ "$response" =~ ^([yY])+$ ]]; then
            EXTRANODES="node-red-node-pi-gpio@latest node-red-node-random@latest node-red-node-ping@latest node-red-contrib-play-audio@latest node-red-node-smooth@latest node-red-node-serialport@latest"
            EXTRAW="install"
        fi

        # this script assumes that $HOME is the folder of the user that runs node-red
        # that $NODERED_USER is the user name and the group name to use when running is the
        # primary group of that user
        # if this is not correct then edit the lines below
        MYOS=$(cat /etc/os-release | grep "^ID=" | cut -d = -f 2 | tr -d '"')
        GLOBAL="true"
        TICK='\033[1;32m\u2714\033[0m'
        CROSS='\033[1;31m\u2718\033[0m'
        cd "$NODERED_HOME" || exit 1
        clear
        echo -e "\nRunning Node-RED $EXTRAW for user $NODERED_USER at $NODERED_HOME on $MYOS\n"

        nv=0
        nv2=""
        nrv=`echo $NODERED_VERSION | cut -d "." -f1`

        if [[ "$APTOK" == "false" ]]; then
            if HAS_NODE && HAS_NPM; then
                : # node and npm is installed, we can continue :)
            else
                if HAS_NODE; then :; else echo -en "\b$CROSS   MISSING: nodejs\r\n"; fi
                if HAS_NPM; then :; else echo -en "\b$CROSS   MISSING: npm\r\n"; fi
                echo -en "\b$CROSS   MISSING: apt"
                echo -e "\r\n\r\nThis script uses apt to install nodejs and npm.\n"
                echo -e "You can install nodejs and npm manually then run the script again to continue.\r\n\r\n"
                exit 2
            fi
        fi

        if [[ "$APTOK" == "true" ]]; then
            ndeb=$(apt-cache policy nodejs | grep Installed | awk '{print $2}')
        fi
        if HAS_NODE; then
            nv=`node -v | cut -d "." -f1 | cut -d "v" -f2`
            nvs=`node -v | cut -d "." -f2`
            nv2=`node -v`
            # nv2=`apt list nodejs 2>/dev/null | grep dfsg | cut -d ' ' -f 2 | cut -d '-' -f 1`
            echo "Already have nodejs $nv2" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        fi
        # ensure ~/.config dir is owned by the user
        sudo chown -Rf $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.config/

        echo "OLD nodejs "$nv" :" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        echo "NEW nodejs "$NODE_VERSION" :" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        # If older than version of 12.17 then force it to update to support es modules
        if [[ "$nv" -eq 12 && "$nvs" -lt 17 ]]; then
            nv=0
            NODE_VERSION="12"
        fi

        if [[ "$nv" -lt 12 && "$nv" -ne 0  && "$nrv" != 1 ]]; then
            if [[ "$NODE_VERSION" == "" ]]; then
                echo "Nodejs $nv too old and new version not specified - exiting" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                echo "Node-RED v2.x no longer supports Nodejs $nv "
                # echo "  Node-RED v2 no longer supports Nodejs $nv.  Please update."
                # echo "  "
                # echo "  You can use the old v1 branch by specifying --nodered-version=1.*"
                echo "  "
                echo "  You can force an install of node 12, 14 or 16 by using the --node12, --node14 or --node16 parameter."
                echo "  However doing so may break some nodes that may need re-installing manually."
                echo "  Generally it is recommended to update all nodes to their latest versions before upgrading."
                echo "  "
                echo "  If you wish to stay on nodejs $nv you can update to the latest Node-RED 1.x version by adding"
                echo '  --nodered-version="1.3.7" to that install command. If in doubt this is the safer option.'
                if [[ "$npv" != "" ]]; then
                    echo "Checking for outdated nodes in $PWD"
                    npm --silent outdated
                    echo "  "
                fi
                echo "  Please backup your installation and flows before upgrading."
                echo "  "
                if ! sudo grep -q BCM2 /proc/cpuinfo; then
                    echo "  Note: not all embedded hardware can be updated via this method - please check before proceeding."
                    echo "  "
                fi
                echo "  Exiting now."
                exit 2
            fi
            echo "Installing nodejs "$NODE_VERSION" over "$nv" ." | sudo tee -a /var/log/nodered-install.log >>/dev/null
        fi

        time1=$(date)
        echo "" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        echo "***************************************" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        echo "" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        echo "Started : "$time1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
        echo "Running for user $NODERED_USER at $NODERED_HOME" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        echo -ne '\r\nThis can take 20-30 minutes on the slower Pi versions - please wait.\r\n\n'
        echo -ne '  Stop Node-RED                       \r\n'
        echo -ne '  Remove old version of Node-RED      \r\n'
        echo -ne '  Remove old version of Node.js       \r\n'
        echo -ne '  Install Node.js                     \r\n'
        echo -ne '  Clean npm cache                     \r\n'
        echo -ne '  Install Node-RED core               \r\n'
        echo -ne '  Move global nodes to local          \r\n'
        echo -ne '  Npm rebuild existing nodes          \r\n'
        echo -ne '  Install extra Pi nodes              \r\n'
        echo -ne '  Add shortcut commands               \r\n'
        echo -ne '  Update systemd script               \r\n'
        echo -ne '                                      \r\n'
        echo -ne '\r\nAny errors will be logged to   /var/log/nodered-install.log\r\n'
        echo -ne '\033[14A'

        # stop any running node-red service
        if sudo service nodered stop 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null ; then CHAR=$TICK; else CHAR=$CROSS; fi
        echo -ne "  Stop Node-RED                       $CHAR\r\n"

        # save any global nodes
        GLOBALNODES=$(find /usr/local/lib/node_modules/node-red-* -maxdepth 0 -type d -printf '%f\n' 2>/dev/null)
        GLOBALNODES="$GLOBALNODES $(find /usr/lib/node_modules/node-red-* -maxdepth 0 -type d -printf '%f\n' 2>/dev/null)"
        echo "Found global nodes: $GLOBALNODES :" | sudo tee -a /var/log/nodered-install.log >>/dev/null

        # remove any old node-red installs or files
        if [[ "$APTOK" == "true" ]]; then
            sudo apt remove -y nodered 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
        fi
        # sudo apt remove -y node-red-update 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
        sudo rm -rf /usr/local/lib/node_modules/node-red* /usr/local/lib/node_modules/npm /usr/local/bin/node-red* /usr/local/bin/node /usr/local/bin/npm 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
        sudo rm -rf /usr/lib/node_modules/node-red* /usr/bin/node-red* 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
        echo -ne '  Remove old version of Node-RED      \033[1;32m\u2714\033[0m\r\n'

        if [[ "$APTOK" == "false" ]]; then
            echo -ne "  Node option not possible            :   Skipped - apt not found\n"
            echo -ne "  Leave existing Node.js              :"
        elif [[ "$NODE_VERSION" == "" && "$nv" -ne 0 ]]; then
            CHAR="-"
            echo -ne "  Node option not specified           :   --node12, --node14, or --node16\n"
            echo -ne "  Leave existing Node.js              :"
        else
            if [[ "$NODE_VERSION" == "12" ]]; then
                tgtl=$tgtl12
                tgta=$tgta12
            elif [[ "$NODE_VERSION" == "16" ]]; then
                tgtl=$tgtl16
                tgta=$tgta16
            else
                tgtl=$tgtl14
                tgta=$tgta14
                NODE_VERSION="14"
            fi
            # maybe remove Node.js - or upgrade if nodesource.list exists
            if [[ "$(uname -m)" =~ "i686" ]]; then
                echo "Using i686" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                curl -sSL -o /tmp/node.tgz https://unofficial-builds.nodejs.org/download/release/v$tgtl/node-v$tgtl-linux-x86.tar.gz 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                # unpack it into the correct places
                hd=$(head -c 9 /tmp/node.tgz)
                if [ "$hd" == "<!DOCTYPE" ]; then
                    CHAR="$CROSS File $f not downloaded";
                else
                    if sudo tar -zxof /tmp/node.tgz --strip-components=1 -C /usr 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                fi
                rm /tmp/node.tgz 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Install Node.js for i686            $CHAR"
            elif uname -m | grep -q armv6l ; then
                sudo apt remove -y nodejs nodejs-legacy npm 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo rm -rf /etc/apt/sources.d/nodesource.list /usr/lib/node_modules/npm*
                echo -ne "  Remove old version of Node.js       $TICK   $nv2\r\n"
                echo -ne "  Install Node.js for Armv6           \r"
                # f=$(curl -sL https://nodejs.org/download/release/latest-dubnium/ | grep "armv6l.tar.gz" | cut -d '"' -f 2)
                # curl -sL -o node.tgz https://nodejs.org/download/release/latest-dubnium/$f 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                curl -sSL -o /tmp/node.tgz https://unofficial-builds.nodejs.org/download/release/v$tgta/node-v$tgta-linux-armv6l.tar.gz 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                # unpack it into the correct places
                hd=$(head -c 9 /tmp/node.tgz)
                if [ "$hd" == "<!DOCTYPE" ]; then
                    CHAR="$CROSS File $f not downloaded";
                else
                    mkdir -p /tmp/nodejs
                    # if [[ -e /usr/bin/node ]]; then
                    #     if [[ -O "/usr/bin/" ]]; then
                    #         echo "Fixup v6 /usr owner" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                    #         sudo chown -f root:root /usr/bin /usr/bin/node /usr/bin/npx /usr/bin/npm /usr/lib /usr/include
                    #         sudo chown -fR root:root /usr/lib/node_modules /usr/include/node /usr/share
                    #     else
                    #         echo "v6 /usr owner OK" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                    #     fi
                    # fi
                    sudo tar -zxof /tmp/node.tgz --strip-components=1 -C /tmp/nodejs
                    sudo chown -R root:root /tmp/nodejs 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                    if sudo cp -PR /tmp/nodejs/* /usr 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                    sudo rm -rf /tmp/nodejs 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                fi
                # remove the tgz file to save space
                rm /tmp/node.tgz 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Install Node.js for Armv6           $CHAR"
            elif [[ -e $NODERED_HOME/.nvm ]]; then
                echo -ne '  Using NVM to manage Node.js         +   please run   \033[0;36mnvm use lts\033[0m   before running Node-RED\r\n'
                echo -ne '  NOTE: Using nvm is NOT RECOMMENDED.     Node-RED will not run as a service under nvm.\r\n'
                export NVM_DIR=$NODERED_HOME/.nvm
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
                echo "Using NVM !!! $(nvm current)" 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                nvm install $NODE_VERSION --no-progress --latest-npm >/dev/null 2>&1
                nvm use $NODE_VERSION >/dev/null 2>&1
                nvm alias default $NODE_VERSION >/dev/null 2>&1
                echo "Now using --- $(nvm current)" 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                GLOBAL="false"
                ln -f -s $NODERED_HOME/.nvm/versions/node/$(nvm current)/lib/node_modules/node-red/red.js  $NODERED_HOME/node-red
                echo -ne "  Update Node.js $NODE_VERSION                   $CHAR"
            elif [[ $(which n) ]]; then
                echo "Using n" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Using N to manage Node.js           +\r\n"
                if sudo n $NODE_VERSION 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                echo -ne "  Update Node.js $NODE_VERSION                   $CHAR"
            else
                echo "Installing nodejs $NODE_VERSION" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                # clean out old nodejs stuff
                npv=$(npm -v 2>/dev/null | head -n 1 | cut -d "." -f1)
                sudo apt remove -y nodejs nodejs-legacy npm 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo dpkg -r nodejs 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo dpkg -r node 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo rm -rf /opt/nodejs 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo rm -rf /usr/local/lib/nodejs* 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo rm -f /usr/local/bin/node* 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo rm -rf /usr/local/bin/npm* /usr/local/bin/npx* /usr/lib/node_modules/npm* 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                if [ "$npv" = "1" ]; then
                    sudo rm -rf /usr/local/lib/node_modules/node-red* /usr/lib/node_modules/node-red* 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                fi
                sudo apt -y autoremove 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Remove old version of Node.js       \033[1;32m\u2714\033[0m   $nv2\r\n"
                echo "Grab the LTS bundle" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Install Node.js $NODE_VERSION LTS              \r"
                # use the official script to install for other debian platforms
                sudo apt install -y curl 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                curl -sSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash - 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                if sudo apt install -y nodejs 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                echo -ne "  Install Node.js $NODE_VERSION LTS              $CHAR"
            fi
        fi

        NUPG=$CHAR
        hash -r
        rc=""
        if nov=$(node -v 2>/dev/null); then :; else rc="ERR"; fi
        if npv=$(npm -v 2>/dev/null); then :; else rc="ERR"; fi
        if [[ "$npv" == "" ]]; then npv="missing"; fi
        if [[ "$nov" == "" ]]; then nov="missing"; fi

        echo -ne "\nVersions: node:$nov npm:$npv\n" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        if [[ "$rc" == "" ]]; then
            echo -ne "   $nov   Npm $npv\r\n"
        else
            echo -ne "\b$CROSS   Bad install:  Node.js $nov  Npm $npv - Exit\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n"
            exit 2
        fi
        if [ "$EUID" == "0" ]; then npm config set unsafe-perm true &>/dev/null; fi

        # clean up the npm cache and node-gyp
        if [[ "$NUPG" == "$TICK" ]]; then
            if [[ "$GLOBAL" == "true" ]]; then
                sudo npm cache clean --force 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
            else
                npm cache clean --force 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
            fi
            if sudo rm -rf "$NODERED_HOME/.node-gyp" "$NODERED_HOME/.npm" /root/.node-gyp /root/.npm; then CHAR=$TICK; else CHAR=$CROSS; fi
        fi
        echo -ne "  Clean npm cache                     $CHAR\r\n"

        # and install Node-RED
        echo "Now install Node-RED $NODERED_VERSION" | sudo tee -a /var/log/nodered-install.log >>/dev/null

        NODERED_VERSION_SELECTION=""
        if [ -z ${NODERED_VERSION} ]; then
            NODERED_VERSION_SELECTION="latest"
        else
            NODERED_VERSION_SELECTION=${NODERED_VERSION}
        fi

        if [[ "$GLOBAL" == "true" ]]; then
            sudo npm i -g --unsafe-perm --no-progress --no-update-notifier --no-audit --no-fund node-red@"$NODERED_VERSION_SELECTION" 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; nri=${PIPESTATUS[0]}
            if [[ $nri -eq 0 ]]; then CHAR=$TICK; else CHAR=$CROSS; fi
        else
            npm i -g --unsafe-perm --no-progress --no-update-notifier --no-audit --no-fund node-red@"$NODERED_VERSION_SELECTION" 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; nri=${PIPESTATUS[0]}
            if [[ $nri -eq 0 ]]; then CHAR=$TICK; else CHAR=$CROSS; fi
        fi
        nrv=$(npm --no-progress --no-update-notifier --no-audit --no-fund -g ls node-red | grep node-red | cut -d '@' -f 2 | sudo tee -a /var/log/nodered-install.log) >>/dev/null 2>&1
        echo -ne "  Install Node-RED core               $CHAR   $nrv\r\n"

        # install any nodes, that were installed globally, as local instead
        echo "Now create basic package.json for the user and move any global nodes" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        mkdir -p "$NODERED_HOME/.node-red/node_modules"
        sudo chown -Rf $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.node-red/ 2>&1 >>/dev/null
        pushd "$NODERED_HOME/.node-red" 2>&1 >>/dev/null
            npm config set update-notifier false 2>&1 >>/dev/null
            if [ ! -f "package.json" ]; then
                echo '{' > package.json
                echo '  "name": "node-red-project",' >> package.json
                echo '  "description": "initially created for you by Node-RED '$nrv'",' >> package.json
                echo '  "version": "0.0.1",' >> package.json
                echo '  "private": true,' >> package.json
                echo '  "dependencies": {' >> package.json
                echo '  }' >> package.json
                echo '}' >> package.json
            fi
            CHAR="-"
            if [[ $GLOBALNODES != " " ]]; then
                if npm i --unsafe-perm --save --no-progress --no-update-notifier --no-audit --no-fund $GLOBALNODES 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
            fi
            echo -ne "  Move global nodes to local          $CHAR\r\n"

            # try to rebuild any already installed nodes
            CHAR="-"
            if [[ "$NUPG" == "$TICK" ]]; then
                echo -ne "Running npm rebuild\r\n" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                if npm rebuild --no-progress --no-update-notifier --no-fund 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                echo -ne "  Npm rebuild existing nodes          $CHAR\r"
            else
                echo -ne "  Leave existing nodes                -\r"
            fi
            if [[ "$UPDATENODES" == "y" ]]; then
                echo -ne "Running npm update\r\n" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Npm update existing nodes           "
                if npm update --no-progress --no-update-notifier --no-fund 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                echo -ne "$CHAR\r"
            fi
            echo -ne "\n"

            CHAR="-"
            if [[ ! -z $EXTRANODES ]]; then
                echo "Installing extra nodes: $EXTRANODES :" | sudo tee -a /var/log/nodered-install.log >>/dev/null
                if npm i --unsafe-perm --save --no-progress --no-update-notifier --no-audit --no-fund $EXTRANODES 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
            fi
            echo -ne "  Install extra Pi nodes              $CHAR\r\n"

        popd 2>&1 >>/dev/null
        if [ -d "$NODERED_HOME/.npm" ]; then
            sudo chown -Rf $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.npm 2>&1 >>/dev/null
        fi

        if [[ "$SYSTEMDOK" == "true" ]]; then
            # add the shortcut and start/stop/log scripts to the menu
            echo "Now add the shortcut and start/stop/log scripts to the menu" | sudo tee -a /var/log/nodered-install.log >>/dev/null
            sudo mkdir -p /usr/bin
            if curl -f https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-icon.svg >/dev/null 2>&1; then
                sudo curl -sL -o /usr/share/icons/hicolor/scalable/apps/node-red-icon.svg https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-icon.svg 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo curl -sL -o /usr/share/applications/Node-RED.desktop https://raw.githubusercontent.com/node-red/linux-installers/master/resources/Node-RED.desktop 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo curl -sL -o /usr/bin/node-red-start https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-start 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo curl -sL -o /usr/bin/node-red-stop https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-stop 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo curl -sL -o /usr/bin/node-red-restart https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-restart 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo curl -sL -o /usr/bin/node-red-reload https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-reload 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo curl -sL -o /usr/bin/node-red-log https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-log 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo curl -sL -o /etc/logrotate.d/nodered https://raw.githubusercontent.com/node-red/linux-installers/master/resources/nodered.rotate 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                sudo chmod +x /usr/bin/node-red-start
                sudo chmod +x /usr/bin/node-red-stop
                sudo chmod +x /usr/bin/node-red-restart
                sudo chmod +x /usr/bin/node-red-reload
                sudo chmod +x /usr/bin/node-red-log
                echo -ne "  Add shortcut commands               $TICK\r\n"
            else
                echo -ne "  Add shortcut commands               $CROSS\r\n"
            fi

            # add systemd script and configure it for $NODERED_USER
            echo "Now add systemd script and configure it for $NODERED_USER:$NODERED_GROUP @ $NODERED_HOME" | sudo tee -a /var/log/nodered-install.log >>/dev/null

            # check if systemd script already exists
            SYSTEMDFILE="/lib/systemd/system/nodered.service"

            if sudo curl -sL -o ${SYSTEMDFILE}.temp https://raw.githubusercontent.com/node-red/linux-installers/master/resources/nodered.service 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
            # set the memory, User Group and WorkingDirectory in nodered.service
            if [ $(cat /proc/meminfo | grep MemTotal | cut -d ":" -f 2 | cut -d "k" -f 1 | xargs) -lt 894000 ]; then mem="256"; else mem="512"; fi
            if [ $(cat /proc/meminfo | grep MemTotal | cut -d ":" -f 2 | cut -d "k" -f 1 | xargs) -gt 1894000 ]; then mem="1024"; fi
            if [ $(cat /proc/meminfo | grep MemTotal | cut -d ":" -f 2 | cut -d "k" -f 1 | xargs) -gt 3894000 ]; then mem="2048"; fi
            # if [ $(cat /proc/meminfo | grep MemTotal | cut -d ":" -f 2 | cut -d "k" -f 1 | xargs) -gt 7894000 ]; then mem="4096"; fi
            sudo sed -i 's#=512#='$mem'#;' ${SYSTEMDFILE}.temp
            sudo sed -i 's#^User=pi#User='$NODERED_USER'#;s#^Group=pi#Group='$NODERED_GROUP'#;s#^WorkingDirectory=/home/pi#WorkingDirectory='$NODERED_HOME'#;s#^EnvironmentFile=-/home/pi#EnvironmentFile=-'$NODERED_HOME'#;' ${SYSTEMDFILE}.temp

            if test -f "$SYSTEMDFILE"; then
                # there's already a systemd script
                EXISTING_FILE=$(md5sum $SYSTEMDFILE | awk '$1 "${SYSTEMDFILE}" {print $1}');
                TEMP_FILE=$(md5sum ${SYSTEMDFILE}.temp | awk '$1 "${SYSTEMDFILE}.temp" {print $1}');

                if [[ $EXISTING_FILE == $TEMP_FILE ]];
                then
                    : # silent procedure
                else
                    echo "Customized systemd script found @ $SYSTEMDFILE. To prevent loss of modifications, we'll not recreate the systemd script." | sudo tee -a /var/log/nodered-install.log >>/dev/null
                    echo "If you want the installer to recreate the systemd script, please delete or rename the current script & re-run the installer." | sudo tee -a /var/log/nodered-install.log >>/dev/null
                    CHAR="-   Skipped - existing script is customized."
                fi
                sudo rm ${SYSTEMDFILE}.temp
            else
                sudo mv ${SYSTEMDFILE}.temp $SYSTEMDFILE
            fi

            sudo systemctl daemon-reload 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
            echo -ne "  Update systemd script               $CHAR\r\n"
        else
            echo -ne "  Add shortcut commands               :   Skipped - systemd not found\r\n"
            echo -ne "  Update systemd script               :   Skipped - systemd not found\r\n"
        fi
        sudo ln -s $(which python3) /usr/bin/python 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null

        # remove unneeded large sentiment library to save space and load time
        sudo rm -f /usr/lib/node_modules/node-red/node_modules/multilang-sentiment/build/output/build-all.json 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
        # on LXDE add launcher to top bar, refresh desktop menu
        file=/home/$NODERED_USER/.config/lxpanel/LXDE-pi/panels/panel
        if [ -e $file ]; then
            if ! grep -q "Node-RED" $file; then
                mat="lxterminal.desktop"
                ins="lxterminal.desktop\n    }\n    Button {\n      id=Node-RED.desktop"
                sudo sed -i "s|$mat|$ins|" $file 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                if xhost >& /dev/null ; then
                    export DISPLAY=:0 && lxpanelctl restart 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
                fi
            fi
        fi

        # on Pi, add launcher to top bar, add cpu temp example, make sure ping works
        echo "Now add launcher to top bar, add cpu temp example, make sure ping works" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        if sudo grep -q BCM2 /proc/cpuinfo; then
            sudo setcap cap_net_raw+eip $(eval readlink -f `which node`) 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
            sudo setcap cap_net_raw=ep /bin/ping 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
            sudo adduser $NODERED_USER gpio 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
            sudo apt install -y python3-rpi.gpio 2>&1 | sudo tee -a /var/log/nodered-install.log >>/dev/null
        fi

        echo -ne "\r\n\r\n\r\n"
        echo -ne "All done.\r\n"
        if [[ "$RESTART" == "y" ]]; then
            echo -ne "\033[1mRestarting \033[38;5;88mNode-RED\033[0m service\r\n"
            sudo systemctl restart nodered
            echo -ne "\033[1mRestarted  \033[38;5;88mNode-RED\033[0m\r\n"
        else
            if [[ "$GLOBAL" == "true" ]] ; then
                if [[ "$SYSTEMDOK" == "true" ]]; then
                    echo -ne "You can now start Node-RED with the command  \033[0;36mnode-red-start\033[0m\r\n"
                    echo -ne "  or using the icon under   Menu / Programming / Node-RED\r\n"
                else
                    echo -ne "You can now start Node-RED with the command  \033[0;36mnode-red\033[0m\r\n"
                fi
            else
                echo -ne "You can now start Node-RED with the command  \033[0;36m./node-red\033[0m\r\n"
            fi
        fi
        echo -ne "Then point your browser to \033[0;36mlocalhost:1880\033[0m or \033[0;36mhttp://{your_pi_ip-address}:1880\033[0m\r\n"
        echo -ne "\r\n"
        if free -h -t >/dev/null 2>&1; then
            echo "Memory  : $(free -h -t | grep Total | awk '{print $2}' | cut -d i -f 1)" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        else
            echo "Mem     : $(free -m | grep Mem | awk '{print $2}' | cut -d i -f 1)Mb" | sudo tee -a /var/log/nodered-install.log >>/dev/null
            echo "Swap    : $(free -m | grep Swap | awk '{print $2}' | cut -d i -f 1)Mb" | sudo tee -a /var/log/nodered-install.log >>/dev/null
        fi
        echo "Started :  $time1 " | sudo tee -a /var/log/nodered-install.log
        echo "Finished:  $(date)" | sudo tee -a /var/log/nodered-install.log

        file=/home/$NODERED_USER/.node-red/settings.js
        if [ ! -f $file ]; then
            echo " "
            echo -e "You may want to run   \033[0;36mnode-red admin init\033[0m"
            echo "to configure your initial options and settings."
            echo " "
        elif ! diff -q /usr/lib/node_modules/node-red/settings.js $file &>/dev/null 2>&1 ; then
            echo " "
            echo "Your settings.js file is different from the latest defaults."
            echo "You may wish to run"
            echo "   diff -y --suppress-common-lines /usr/lib/node_modules/node-red/settings.js $file"
            echo "to compare them."
            echo " "
        fi
    ;;
    * )
        echo " "
        exit 1
    ;;
esac
else
echo " "
echo "Sorry - cannot connect to internet - not going to touch anything."
echo "https://www.npmjs.com/package/node-red   is not reachable."
echo "Please ensure you have a working internet connection."
echo "Return code from curl is "$?
echo " "
exit 1
fi
else
echo " "
echo "Sorry - I'm not supposed to be run on a Mac."
echo "Please see the documentation at http://nodered.org/docs/getting-started/upgrading."
echo " "
exit 1
fi
fi
