#!/usr/bin/env bash
#
# Copyright 2017 Mycroft AI Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

# Set a default locale to handle output from commands reliably
export LANG=C.UTF-8

# exit on any error
#set -Ee
REPO_PICROFT="https://raw.githubusercontent.com/emphasize/enclosure-picroft/refactor_setup_wizard"
REPO_CORE="https://github.com/emphasize/mycroft-core"

TOP=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

if [[ ! -f "$TOP"/.dev_opts.json ]] ; then
    touch "$TOP"/.dev_opts.json
    echo '{ "firstrun": true }' > "$TOP"/.dev_opts.json
fi

function save_choices() {
    if [[ ! -f "$TOP"/.dev_opts.json ]] ; then
        touch "$TOP"/.dev_opts.json
        echo "{}" > "$TOP"/.dev_opts.json
    fi
    #no chance to bring in boolean with --arg
    #NOTE: Boolean are called without -r (whiich only outputs string)
    #eg if jq ".startup" "$TOP"/.dev_opts.json ; then
    if [ "$2" != true ] && [ "$2" != false ] ; then
        JSON=$(cat "$TOP"/.dev_opts.json | jq '.'$1' = "'$2'"')
    else
        JSON=$(cat "$TOP"/.dev_opts.json | jq '.'$1' = '$2'')
    fi
    echo "$JSON" > "$TOP"/.dev_opts.json
}

function clean_mycroft_files() {
    echo
    echo "This will completely remove any files installed by mycroft (including pairing"
    echo "information)."
    echo
    echo "Do you wish to continue? (y/n)"
    echo
    while true; do
        read -N1 -s key
        case $key in
        [Yy])
            sudo rm -rf /var/log/mycroft
            rm -f /var/tmp/mycroft_web_cache.json
            rm -rf "${TMPDIR:-/tmp}/mycroft"
            rm -rf "$HOME/.mycroft"
            sudo rm -rf "/opt/mycroft"
            exit 0
            ;;
        [Nn])
            exit 1
            ;;
        esac
    done
}

function show_help() {
    echo
    echo "Usage: dev_setup.sh [options]"
    echo "Prepare your environment for running the mycroft-core services."
    echo
    echo "Options:"
    echo
    echo "     -h, --help              Show this message"
    echo
    echo "     --clean                 Remove files and folders created by this script"
    echo
    echo "     -p arg, --python arg    Sets the python version to use"
    echo "     -mimic                  Force mimic build"
    echo "     -sm                     Skip mimic build"
    echo
    echo "     -n, --no-error          Do not exit on error (use with caution)"
    echo "     -r, --allow-root        Allow to be run as root (e.g. sudo)"
    echo
}

# Parse the command line
opt_forcemimicbuild=false
opt_allowroot=false
opt_skipmimicbuild=false
opt_inst_deps=false
opt_python=python3
param=''

for var in "$@" ; do
    # Check if parameter should be read
    if [[ $param == 'python' ]] ; then
        opt_python=$var
        param=""
        continue
    fi

    # Check for options
    if [[ $var == '-h' || $var == '--help' ]] ; then
        show_help
        exit 0
    fi

    if [[ $var == '--clean' ]] ; then
        if clean_mycroft_files; then
            exit 0
        else
            exit 1
        fi
    fi

    if [[ $var == '-r' || $var == '--allow-root' ]] ; then
        opt_allowroot=true
    fi
    if [[ $var == '-mimic' ]] ; then
        opt_forcemimicbuild=true
    fi
    if [[ $var == '-n' || $var == '--no-error' ]] ; then
        # Do NOT exit on errors
        set +Ee
    fi
    if [[ $var == '-sm' ]] ; then
        opt_skipmimicbuild=true
    fi
    if [[ $var == '-p' || $var == '--python' ]] ; then
        param='python'
    fi
done

if [[ $(id -u) -eq 0 && $opt_allowroot != true ]] ; then
    echo 'This script should not be run as root or with sudo.'
    echo 'If you really need to for this, rerun with --allow-root'
    exit 1
fi

function found_exe() {
    hash "$1" 2>/dev/null
}

if found_exe sudo ; then
    SUDO=sudo
elif [[ $opt_allowroot != true ]]; then
    echo 'This script requires the package "sudo" to install system packages. Please install it, then re-run this script.'
    exit 1
fi

# If tput is available and can handle multiple colors
if found_exe tput ; then
    if [[ $(tput colors) != "-1" ]]; then
        GREEN=$(tput setaf 2)
        BLUE=$(tput setaf 4)
        CYAN=$(tput setaf 6)
        YELLOW=$(tput setaf 3)
        RESET=$(tput sgr0)
        HIGHLIGHT=$YELLOW
    fi
fi

function get_YN() {
    # Loop until the user hits the Y or the N key
    echo -e -n "     Choice [${CYAN}Y${RESET}/${CYAN}N${RESET}]: "
    while true; do
        read -N1 -s key
        case $key in
        [Yy])
            return 0
            ;;
        [Nn])
            return 1
            ;;
        esac
    done
}

function os_is() {
    [[ $(grep "^ID=" /etc/os-release | awk -F'=' '/^ID/ {print $2}' | sed 's/\"//g') == $1 ]]
}

function os_is_like() {
    grep "^ID_LIKE=" /etc/os-release | awk -F'=' '/^ID_LIKE/ {print $2}' | sed 's/\"//g' | grep -q "\\b$1\\b"
}

function redhat_common_install() {
    $SUDO yum install -y cmake gcc-c++ git python3-devel ed libtool libffi-devel openssl-devel autoconf automake bison swig portaudio-devel mpg123 flac curl libicu-devel libjpeg-devel fann-devel pulseaudio pulseaudio-module-zeroconf dialog
    git clone https://github.com/libfann/fann.git
    cd fann
    git checkout b211dc3db3a6a2540a34fbe8995bf2df63fc9939
    cmake .
    $SUDO make install
    cd "$TOP"
    rm -rf fann

}

function debian_install() {
    APT_PACKAGE_LIST="git python3 python3-dev python3-setuptools libtool \
        libffi-dev libssl-dev autoconf automake bison swig libglib2.0-dev \
        portaudio19-dev mpg123 screen flac curl libicu-dev pkg-config \
        libjpeg-dev libfann-dev build-essential jq alsa-utils pulseaudio \
        pulseaudio-utils pulseaudio-module-zeroconf dialog"

    dist='debian'

    if dpkg -V libjack-jackd2-0 > /dev/null 2>&1 && [[ -z ${CI} ]] ; then
        echo
        echo "We have detected that your computer has the libjack-jackd2-0 package installed."
        echo "Mycroft requires a conflicting package, and will likely uninstall this package."
        echo "On some systems, this can cause other programs to be marked for removal."
        echo "Please review the following package changes carefully."
        echo
        read -p "     Press enter to continue"
        echo
        $SUDO apt-get install $APT_PACKAGE_LIST
    else
        $SUDO apt-get install -y $APT_PACKAGE_LIST
    fi
}

function open_suse_install() {
    $SUDO zypper install -y git python3 python3-devel libtool libffi-devel libopenssl-devel autoconf automake bison swig portaudio-devel mpg123 flac curl libicu-devel pkg-config libjpeg-devel libfann-devel python3-curses pulseaudio module-zeroconf-publish alsa-utils dialog
    $SUDO zypper install -y -t pattern devel_C_C++
    dist='open_suse'
}


function fedora_install() {
    $SUDO dnf install -y git python3 python3-devel python3-pip python3-setuptools python3-virtualenv pygobject3-devel ed libtool libffi-devel openssl-devel autoconf bison swig glib2-devel portaudio-devel mpg123 mpg123-plugins-pulseaudio alsa-utils module-zeroconf-publish asoundconf screen curl pkgconfig libicu-devel automake libjpeg-turbo-devel fann-devel gcc-c++ redhat-rpm-config jq make dialog
    dist='fedora'
}


function arch_install() {
    $SUDO pacman -Syu --needed --noconfirm wget git python python-pip python-setuptools python-virtualenv python-gobject ed libffi swig portaudio mpg123 screen flac curl icu libjpeg-turbo base-devel jq pulseaudio pulseaudio-zeroconf alsa-utils pulseaudio-alsa asoundconf dialog

    pacman -Qs '^fann$' &> /dev/null || (
        git clone  https://aur.archlinux.org/fann.git
        cd fann
        makepkg -srciA --noconfirm
        cd ..
        rm -rf fann
    )
    dist='arch'
}

function centos_install() {
    $SUDO yum install -y epel-release
    dist='centos'
    redhat_common_install
}

function redhat_install() {
    $SUDO yum install -y wget
    wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    $SUDO yum install -y epel-release-latest-7.noarch.rpm
    rm epel-release-latest-7.noarch.rpm
    dist='redhat'
    redhat_common_install
}

function gentoo_install() {
    $SUDO emerge --noreplace dev-vcs/git dev-lang/python dev-python/setuptools dev-python/pygobject dev-python/requests sys-devel/libtool virtual/libffi virtual/jpeg dev-libs/openssl sys-devel/autoconf sys-devel/bison dev-lang/swig dev-libs/glib media-libs/portaudio media-sound/alsa-utils media-sound/mpg123 media-libs/flac net-misc/curl sci-mathematics/fann sys-devel/gcc app-misc/jq media-libs/alsa-lib dev-libs/icu dev-util/dialog
    dist='gentoo'
}

function alpine_install() {
    $SUDO apk add alpine-sdk git python3 py3-pip py3-setuptools py3-virtualenv mpg123 vorbis-tools pulseaudio-utils fann-dev automake autoconf libtool pcre2-dev pulseaudio-dev pulseaudio-zeroconf alsa-lib-dev alsa-utils swig python3-dev portaudio-dev libjpeg-turbo-dev dialog
    dist='alpine'
}

function install_deps() {
    echo 'Installing packages...'
    if found_exe zypper ; then
        # OpenSUSE
        echo "$GREEN Installing packages for OpenSUSE...$RESET"
        open_suse_install
    elif found_exe yum && os_is centos ; then
        # CentOS
        echo "$GREEN Installing packages for Centos...$RESET"
        centos_install
    elif found_exe yum && os_is rhel ; then
        # Redhat Enterprise Linux
        echo "$GREEN Installing packages for Red Hat...$RESET"
        redhat_install
    elif os_is_like debian || os_is debian || os_is_like ubuntu || os_is ubuntu || os_is linuxmint; then
        # Debian / Ubuntu / Mint
        echo "$GREEN Installing packages for Debian/Ubuntu/Mint...$RESET"
        debian_install
    elif os_is_like fedora || os_is fedora; then
        # Fedora
        echo "$GREEN Installing packages for Fedora...$RESET"
        fedora_install
    elif found_exe pacman && (os_is arch || os_is_like arch); then
        # Arch Linux
        echo "$GREEN Installing packages for Arch...$RESET"
        arch_install
    elif found_exe emerge && os_is gentoo; then
        # Gentoo Linux
        echo "$GREEN Installing packages for Gentoo Linux ...$RESET"
        gentoo_install
    elif found_exe apk && os_is alpine; then
        # Alpine Linux
        echo "$GREEN Installing packages for Alpine Linux...$RESET"
        alpine_install
    else
    	echo
        echo -e "${YELLOW}Could not find package manager
${YELLOW}Make sure to manually install:$BLUE git python3 python-setuptools python-venv pygobject libtool libffi libjpg openssl autoconf bison swig glib2.0 portaudio19 mpg123 flac curl fann g++ jq\n$RESET"

        echo 'Warning: Failed to install all dependencies. Continue? y/N'
        read -n1 continue
        if [[ $continue != 'y' ]] ; then
            exit 1
        fi

    fi
}

# Run a setup mycroft-wizard the very first time that guides the user through some decisions
#TODO ANother entry
if [[ -n $( grep '"firstrun": true' "$TOP"/.dev_opts.json ) ]] && [ -z $CI ] ; then

    clear
    echo
    echo "#########################################################################"
    echo
    echo "$CYAN                    Welcome to Mycroft!  $RESET"
    echo
    echo "#########################################################################"
    echo
    echo
    echo "Welcome to Picroft.  The following setup process is designed to make getting"
    echo "started with Mycroft quick and easy."
    echo
    echo "In a first step the system is brought up to speed and the ${CYAN}files needed to run"
    echo "Mycroft are installed$RESET."
    echo
    echo "The next step is an ${CYAN}optional setup wizard$RESET to explore preferences about"
    echo
    echo "    * ${CYAN}branch used$RESET"
    echo "    * ${CYAN}autoupdate$RESET"
    echo "    * ${CYAN}startup script$RESET"
    echo "    * ${CYAN}sound hardware$RESET"
    echo
    echo
    echo "NEXT: ${CYAN}Installing the Dependencies$RESET"
    echo
    sleep 5

    install_deps

    # Make sure that the user is present in audiospecific groups
    sudo usermod -aG `cat /etc/group | grep -e '^pulse:' -e '^audio:' -e '^pulse-access:' -e '^pulse-rt:' -e '^video:' | awk -F: '{print $1}' | tr '\n' ',' | sed 's:,$::g'` `whoami`

    #clone Repo if not present and reset TOP according to the situation
    if [[ ! -d $TOP/.git ]] ; then
        #indicating that mycroft-core has to be git cloned beforehand (which happens later)
        git clone $REPO_CORE
        cd "$TOP"/mycroft-core && mv "$TOP"/.dev_opts.json ./
        TOP=$( pwd )
        bash "$TOP"/dev_setup.sh
        exit
    fi
    clear
    #Store a fingerprint of setup
    md5sum "$TOP"/dev_setup.sh > .installed
    save_choices dir $TOP
    save_choices dist $dist
    save_choices inst_type custom
    save_choices initial_setup true
    save_choices usedbranch master
    save_choices autoupdate false
    save_choices startup false
    save_choices addpath false
    save_choices checkcode false
    save_choices restart false
    save_choices bash_patched false

    echo
    echo "  Would you like help setting up your system (Setup Wizard)?"
    echo
    echo "     ${HIGHLIGHT}Y)${RESET}es, I'd like the guided setup."
    echo "     ${HIGHLIGHT}N)${RESET}ope, just get me the basics and get out of my way!"
    echo
    sleep 1
    if get_YN ; then
        echo -e "     $HIGHLIGHT Y - Starting the Wizard $RESET"
        source "$TOP"/bin/mycroft-wizard -all

    else
        echo -e "     $HIGHLIGHT N - I will do this on my own $RESET"
        echo
        echo "Alright, have fun!"
        echo
        echo "${CYAN}NOTE: If you decide to use the wizard later, just type 'mycroft-wizard -all'"
        echo "for the whole wizard process or 'mycroft-wizard' for a table of setup choices$RESET"
        echo
        echo "You are currently running with these defaults:"
        echo
        echo "     Branch:                      ${HIGHLIGHT}$( jq -r '.usedbranch // empty' "$TOP"/.dev_opts.json )$RESET"
        echo "     Auto update:                 ${HIGHLIGHT}$( jq -r '.autoupdate // empty' "$TOP"/jq  )$RESET"
        echo "     Auto startup:                ${HIGHLIGHT}$( jq -r '.startup // empty' "$TOP"/.dev_opts.json )$RESET"
        echo "     Exectute from everywhere:    ${HIGHLIGHT}$( jq -r '.addpath // empty' "$TOP"/.dev_opts.json )$RESET"
        echo "     Auto check code (dev):       ${HIGHLIGHT}$( jq -r '.checkcode // empty' "$TOP"/.dev_opts.json )$RESET"
        echo "     Input:                       ${HIGHLIGHT}$( jq -r '.audioinput' "$TOP"/.dev_opts.json )$RESET"
        echo "     Output:                      ${HIGHLIGHT}$( jq -r '.audiooutput' "$TOP"/.dev_opts.json )$RESET"
        #Get the requirements and basic setup and leave setup
        save_choices initial_setup false
        sleep 5
    fi
fi

#Installing deps in case of dev_setup.sh version mismatch or .installed not present (eg new install)
if ! grep "$TOP"/dev_setup.sh "$TOP"/.installed 2> /dev/null | md5sum --check &> /dev/null ; then
    install_deps
fi

VIRTUALENV_ROOT=${VIRTUALENV_ROOT:-"${TOP}/.venv"}

function install_venv() {
    $opt_python -m venv "${VIRTUALENV_ROOT}/" --without-pip &> /dev/null
    # Force version of pip for reproducability, but there is nothing special
    # about this version.  Update whenever a new version is released and
    # verified functional.
    curl -s https://bootstrap.pypa.io/get-pip.py | "${VIRTUALENV_ROOT}/bin/python" - 'pip==20.0.2' &> /dev/null
    # Function status depending on if pip exists
    [[ -x ${VIRTUALENV_ROOT}/bin/pip ]]
}

# Configure to use the standard commit template for
# this repo only.
git config commit.template .gitmessage

if [[ ! -f ${VIRTUALENV_ROOT}/bin/activate ]] ; then
    if ! install_venv ; then
        echo 'Failed to set up virtualenv for mycroft, exiting setup.'
        exit 1
    fi
fi

# Start the virtual environment
echo "${CYAN}Start the virtual environment ...${RESET}"
echo
cd "$TOP"
source ${VIRTUALENV_ROOT}/bin/activate

PYTHON=$(python -c "import sys;print('python{}.{}'.format(sys.version_info[0], sys.version_info[1]))")

# Add mycroft-core to the virtualenv path
# (This is equivalent to typing 'add2virtualenv $TOP', except
# you can't invoke that shell function from inside a script)
VENV_PATH_FILE="${VIRTUALENV_ROOT}/lib/$PYTHON/site-packages/_virtualenv_path_extensions.pth"
if [[ ! -f $VENV_PATH_FILE ]] ; then
    echo 'import sys; sys.__plen = len(sys.path)' > "$VENV_PATH_FILE" || return 1
    echo "import sys; new=sys.path[sys.__plen:]; del sys.path[sys.__plen:]; p=getattr(sys,'__egginsert',0); sys.path[p:p]=new; sys.__egginsert = p+len(new)" >> "$VENV_PATH_FILE" || return 1
fi

if ! grep -q "$TOP" $VENV_PATH_FILE ; then
    echo "${CYAN}Adding mycroft-core to virtualenv path ... ${RESET}"
    echo
    sed -i.tmp '1 a\
'"$TOP"'
' "$VENV_PATH_FILE"
fi

#Installing required python modules in case of requirements.txt version mismatch or .installed not present (eg new install)
if ! grep "$TOP"/requirements/requirements.txt "$TOP"/.installed 2> /dev/null | md5sum --check &> /dev/null ; then
    echo "${CYAN}installing base requirements ...${RESET}"
    echo
    if [[ ! $( pip install -r "$TOP"/requirements/requirements.txt ) ]] ; then
        echo 'Warning: Failed to install required dependencies. Continue? y/N'
        read -n1 continue
        if [[ $continue != 'y' ]] ; then
            exit 1
        fi
    fi
fi

#Installing optional python modules in case of extra-audiobackend.txt version mismatch or .installed not present (eg new install)
if ! grep "$TOP"/requirements/extra-audiobackend.txt "$TOP"/.installed 2> /dev/null | md5sum --check &> /dev/null ; then
    echo "${CYAN}installing extra audio backend requirements ...${RESET}"
    echo
    if [[ ! $( pip install -r "$TOP"/requirements/extra-audiobackend.txt ) ]] ; then
        echo 'Warning: Failed to install some optional dependencies. Continue? y/N'
        read -n1 continue
        if [[ $continue != 'y' ]] ; then
            exit 1
        fi
    fi
fi

#Installing optional python modules in case of extra-stt.txt version mismatch or .installed not present (eg new install)
if ! grep "$TOP"/requirements/extra-stt.txt "$TOP"/.installed 2> /dev/null | md5sum --check &> /dev/null ; then
    echo "${CYAN}installing extra STT requirements ...${RESET}"
    echo
    if [[ ! $( pip install -r "$TOP"/requirements/extra-stt.txt ) ]] ; then
        echo 'Warning: Failed to install some optional dependencies. Continue? y/N'
        read -n1 continue
        if [[ $continue != 'y' ]] ; then
            exit 1
        fi
    fi
fi

#Installing optional python modules in case of extra-mark1.txt version mismatch or .installed not present (eg new install)
if ! grep "$TOP"/requirements/extra-mark1.txt "$TOP"/.installed 2> /dev/null | md5sum --check &> /dev/null ; then
    echo "${CYAN}installing Mark1 requirements ...${RESET}"
    echo
    if [[ ! $( pip install -r "$TOP"/requirements/extra-mark1.txt ) ]] ; then
        echo 'Warning: Failed to install some optional dependencies. Continue? y/N'
        read -n1 continue
        if [[ $continue != 'y' ]] ; then
            exit 1
        fi
    fi
fi

#Installing test python modules in case of tests.txt version mismatch or .installed not present (eg new install)
if ! grep "$TOP"/requirements/tests.txt "$TOP"/.installed 2> /dev/null | md5sum --check &> /dev/null ; then
    echo "${CYAN}installing test requirements ...${RESET}"
    echo
    if [[ ! $(pip install -r "$TOP"/requirements/tests.txt ) ]] ; then
        echo "Warning: Test requirements failed to install. Note: normal operation should still work fine..."
    fi
fi

#in case of skipping mycroft-wizard prime conf
if [ ! -f /etc/mycroft/mycroft.conf ]; then
    sudo mkdir -p /etc/mycroft/
    cd /etc/mycroft
    sudo wget -N $REPO_PICROFT/etc/mycroft/mycroft.conf &> /dev/null
    JSON=$(cat /etc/mycroft/mycroft.conf | jq 'del(.ipc_path)')
    echo "$JSON" | sudo tee /etc/mycroft/mycroft.conf &> /dev/null
fi

if [[ ! -d /opt/mycroft/skills ]] ; then
    echo "#########################################################################"
    echo "    ${CYAN} Skills${RESET}"
    echo "#########################################################################"
    echo "The ${CYAN}standard location${RESET} for Mycroft skills is under ${CYAN}/opt/mycroft/skills.${RESET}"
    echo "This script will create that folder for you.  This requires sudo"
    echo "permission and might ask you for a password..."
    echo
    setup_user=$USER
    setup_group=$(id -gn $USER)
    $SUDO mkdir -p /opt/mycroft/skills
    $SUDO chown -R ${setup_user}:${setup_group} /opt/mycroft
    echo 'Created!'
    echo
    sleep 2
fi

# Create a link to the 'skills' folder.
if [[ ! -d skills ]] ; then
    ln -s /opt/mycroft/skills skills
    echo "For convenience, ${CYAN}a soft link has been created called 'skills' which leads"
    echo "to /opt/mycroft/skills.${RESET}"
    echo
    sleep 2
fi

# create and set permissions for logging
if [[ ! -w /var/log/mycroft/ ]] ; then
    # Creating and setting permissions
    echo 'Creating /var/log/mycroft/ directory'
    if [[ ! -d /var/log/mycroft/ ]] ; then
        $SUDO mkdir /var/log/mycroft/
    fi
    $SUDO chmod 777 /var/log/mycroft/
fi

# Install pep8 pre-commit hook
HOOK_FILE="$TOP/.git/hooks/pre-commit"
if $( jq .checkcode $TOP/.dev_opts.json) || grep -q 'MYCROFT DEV SETUP' $HOOK_FILE; then
    if [[ ! -f $HOOK_FILE ]] || grep -q 'MYCROFT DEV SETUP' $HOOK_FILE; then
        echo "#########################################################################"
        echo "     ${CYAN}PEP8 Check (dev)${RESET}"
        echo "#########################################################################"
        echo "Installing ${CYAN}PEP8 check as precommit-hook${RESET}"
        echo
        echo "#! $(which python)" > $HOOK_FILE
        echo '# MYCROFT DEV SETUP' >> $HOOK_FILE
        cat ./scripts/pre-commit >> $HOOK_FILE
        chmod +x $HOOK_FILE
    fi
fi

SYSMEM=$(free | awk '/^Mem:/ { print $2 }')
MAXCORES=$(($SYSMEM / 2202010))
MINCORES=1
CORES=$(nproc)

# ensure MAXCORES is > 0
if [[ $MAXCORES -lt 1 ]] ; then
    MAXCORES=${MINCORES}
fi

# Be positive!
if ! [[ $CORES =~ ^[0-9]+$ ]] ; then
    CORES=$MINCORES
elif [[ $MAXCORES -lt $CORES ]] ; then
    CORES=$MAXCORES
fi

#build and install pocketsphinx
#build and install mimic

if [[ $opt_skipmimicbuild == true ]] ; then
    save_choices mimic_built false
fi
if [[ $opt_forcemimicbuild == true ]] ; then
    save_choices mimic_built true
fi

#  Pull down mimic source?  Most will be happy with just the package
# Check whether to build mimic (it takes a really long time!)
if [[ $(jq -r .mimic_built "$TOP"/.dev_opts.json) == null ]] ; then
    sleep 0.5
    echo
    echo "Mycroft uses its Mimic technology to speak to you.  Mimic can run both"
    echo "locally and from a server.  The local Mimic is more robotic, but always"
    echo "available regardless of network connectivity.  It will act as a fallback"
    echo "if unable to contact the Mimic server."
    echo
    echo "However, building the local Mimic is time consuming -- it can take hours"
    echo "on slower machines.  This can be skipped, but Mycroft will be unable to"
    echo "talk if you lose network connectivity.  Would you like to build Mimic"
    echo "locally?"
    echo
    if get_YN ; then
        echo -e "     $HIGHLIGHT Y - Mimic will be built $RESET"
        echo
        save_choices mimic_built true
    else
        echo -e "     $HIGHLIGHT N - skip Mimic build $RESET"
        echo
        save_choices mimic_built false
    fi
fi

cd "$TOP"

if $( jq .mimic_built "$TOP"/.dev_opts.json ) ; then
    # first, look for a build of mimic in the folder
    has_mimic=''
    if [[ -f ${TOP}/mimic/bin/mimic ]] ; then
        has_mimic=$(${TOP}/mimic/bin/mimic -lv | grep Voice) || true
    fi

    # in not, check the system path
    if [[ -z $has_mimic ]] ; then
        if [[ -x $(command -v mimic) ]] ; then
            has_mimic=$(mimic -lv | grep Voice) || true
        fi
    fi

    #+ force overwrite
    if [[ -z $has_mimic ]] || [[ $opt_forcemimicbuild == true ]]; then
        echo "#########################################################################"
        echo "     ${CYAN}Mimic Build Process${RESET}"
        echo "#########################################################################"
        echo
        echo "Building with $CORES cores."
        echo
        echo "${HIGHLIGHT}WARNING: The following can take a long time (approx. 15 Minutes on a Pi4) to run$RESET!"
        echo
        "${TOP}/scripts/install-mimic.sh" " $CORES"
        #Adding the custom path to mycroft.conf
        JSON=$( cat /etc/mycroft/mycroft.conf | jq '.tts.mimic = { "path": "'"$TOP"'/mimic/bin/mimic"}' )
        echo "$JSON" | sudo tee /etc/mycroft/mycroft.conf
    fi
else
    if $( jq .initial_setup "$TOP"/.dev_opts.json ) ; then
        #preparing conf with mimic2 (since the default conf points to mimic regardless this steps)
        JSON=$( cat /etc/mycroft/mycroft.conf | jq '.tts += { "module": "mimic2" }' )
        echo "$JSON" | sudo tee /etc/mycroft/mycroft.conf &> /dev/null
        echo "${HIGHLIGHT}You can force a Mimic build afterwards with calling './dev_setup.sh -mimic'$RESET"
        echo 'Skipping mimic build.'
    fi
fi

# set permissions for common scripts
chmod +x "$TOP"/start-mycroft.sh
chmod +x "$TOP"/stop-mycroft.sh
chmod +x "$TOP"/bin/mycroft-cli-client
chmod +x "$TOP"/bin/mycroft-help
chmod +x "$TOP"/bin/mycroft-mic-test
chmod +x "$TOP"/bin/mycroft-msk
chmod +x "$TOP"/bin/mycroft-msm
chmod +x "$TOP"/bin/mycroft-pip
chmod +x "$TOP"/bin/mycroft-say-to
chmod +x "$TOP"/bin/mycroft-skill-testrunner
chmod +x "$TOP"/bin/mycroft-speak

#Store a fingerprint of setup
md5sum "$TOP"/requirements/requirements.txt "$TOP"/requirements/extra-audiobackend.txt "$TOP"/requirements/extra-stt.txt "$TOP"/requirements/extra-mark1.txt "$TOP"/requirements/tests.txt "$TOP"/dev_setup.sh > .installed

#switch back to bin/mycroft-wizard if this is a firstrun
if $( jq .initial_setup "$TOP"/.dev_opts.json ) ; then
    source "$TOP"/bin/mycroft-wizard -all
    #save_choices restart false
fi
save_choices firstrun false
save_choices initial_setup false
