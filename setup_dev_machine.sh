#!/bin/bash
#-------------------------------------------------------------------------------
# Version-dependent variables. PRs welcome :)
# https://github.com/jifalops/setup_dev_machine/pulls

# See https://developer.android.com/studio/#command-tools
ANDROID_TOOLS_URL='https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip'
# See https://flutter.dev/docs/get-started/install/chromeos#install-the-android-sdks
#ANDROID_SDKMANAGER_ARGS='' See the TODO below
ANDROID_INFO_UPDATED='2019-05-30'

# See https://github.com/nvm-sh/nvm/blob/master/README.md#install--update-script
NVM_SETUP_SCRIPT='https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.1/install.sh'
# See https://github.com/pyenv/pyenv-installer
PYENV_SETUP_SCRIPT='https://pyenv.run'

#-------------------------------------------------------------------------------

USAGE='
Usage: setup_dev_machine.sh [OPTIONS] TARGET1 [TARGET2 [...]]

OPTIONS
--code-settings-sync GIST TOKEN   VS Code SettingsSync gist and token.
-f, --force                       Install targets that are already installed.
-g, --git-config NAME EMAIL       Set the global git config name and email address.
-h, --help                        Show this help message.
-p, --path PATH                   The install path for some targets
                                  (android, flutter, anaconda, miniconda).
                                  Defaults to ~/tools/. Note for anaconda, the
                                  spyder launcher icon is created in ~/.local.
-w, --workspace DIRECTORY REMOTE  Setup a workspace folder in DIRECTORY and clone
                                  the list of repos at (REMOTE git repo)/repos.txt
                                  DIRECTORY is a name, not a path. It will be
                                  created under $HOME.

TARGETS
vscode
        Visual Studio Code editor. To include the SyncSettings extension, use
        the --code-settings-gist and --code-settings-token arguments.
flutter
        Installs Flutter from the git repo. Also installs the "android" target.
android
        Installs the Android command line tools, without Android Studio.

node
        Installs nvm and the latest version of node/npm.
pyenv
        Installs Pyenv

For information about the SettingsSync extension for VSCode, see
https://marketplace.visualstudio.com/items?itemName=Shan.code-settings-sync.
'

ALL_TARGETS=(vscode flutter android node firebase pyenv)
has_updated_sources=0

# Utility functions
command_exists() {
  $(command -v "$1" >/dev/null 2>&1) && echo 1
}
package_exists() {
  $(dpkg -l "$1" >/dev/null 2>&1) && echo 1
}
install_packages() {
  local to_install=()
  for package in "$@"; do
    [ $(package_exists "$package") ] || to_install+=("$package")
  done
  local len=${#to_install[@]}
  if [ $len -gt 0 ]; then
    if [ $has_updated_sources -eq 0 ]; then
      sudo apt update
      has_updated_sources=1
    fi
    sudo apt install ${to_install[@]}
  fi
  return $len
}
path_contains() {
  [[ $PATH == *"$1"* ]] && echo 1
}

# Parse command-line arguments
targets=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  --code-settings-sync)
    code_settings_gist="$2"
    code_settings_token="$3"
    shift # past argument
    shift # past argument
    shift # past value
    ;;
  -f | --force)
    force_install=1
    shift # past argument
    ;;
  -g | --git-config)
    git_config_name="$2"
    git_config_email="$3"
    shift # past argument
    shift # past argument
    shift # past value
    ;;
  -h | --help)
    echo "$USAGE"
    exit 0
    ;;
  -p | --path)
    install_dir="$2"
    shift # past argument
    shift # past value
    ;;
  -w | --workspace)
    workspace_dir="$2"
    workspace_repo="$3"
    shift # past argument
    shift # past argument
    shift # past value
    ;;

  *) # unknown option
    targets+=("$1") # save it in an array for later
    shift           # past argument
    ;;
  esac
done
set -- "${targets[@]}" # restore positional parameters

# Validate arg count
if [ $# -lt 1 ] && [ -z "$workspace_dir" ]; then
  echo "$USAGE"
  exit 1
fi

# Validate VSCode SettingsSync settings
if [ -n "$code_settings_gist" ]; then
  if [ ${#code_settings_gist} -ne 32 ] || [ ${#code_settings_token} -ne 40 ]; then
    echo "Invalid gist or token. Their lengths are 32 and 40 characters, respectively."
    exit 1
  fi
fi

# Validate install_dir
if [ -n "$install_dir" ]; then
  if [ ! -d "$install_dir"]; then
    echo "$install_dir is not a directory."
    exit 1
  fi
else
  install_dir="$HOME/tools"
  if [ ! -d "$install_dir" ]; then
    mkdir "$install_dir" || exit 1
  fi
fi
cd "$install_dir" || exit 1

# Validate targets list
declare -A has_target
for target in "${targets[@]}"; do
  valid=0
  for t in "${ALL_TARGETS[@]}"; do
    if [ "$target" == "$t" ]; then
      valid=1
      has_target[$t]=1
      break
    fi
  done
  if [ $valid -eq 0 ]; then
    echo "Invalid target $target"
    exit 1
  fi
done

# Validate git config
if [ -n "$git_config_name" ]; then
  if [[ "$git_config_email" != *"@"* ]]; then
    echo Invalid git config email "$git_config_email"
    exit 1
  fi
fi

# Source .profile to pick up any recent changes
if [ -f "$HOME/.profile" ]; then
  source "$HOME/.profile"
elif [ -f "$HOME/.bashrc" ]; then
  source "$HOME/.bashrc"
fi

# Ensure targets are not already installed unless --force was supplied.
# Doing this first lets the script fail immediately if there is a problem.
declare -A installed
installed[vscode]=$(command_exists code)
installed[flutter]=$(command_exists flutter)
installed[android]=$(command_exists sdkmanager)
installed[pyenv]=$(command_exists pyenv)
installed[node]=$(command_exists node)
if [ ! $force_install ]; then
  for target in "${targets[@]}"; do
    if [ ${installed[$target]} ]; then
      echo "Target '$target' is already installed. Use --force to override."
      exit 1
    fi
  done
fi

# Exit if the flutter repo dir exists and is not empty.
if [ ${has_target[flutter]} ] && [ -d "$install_dir/flutter" ] && [ "$(ls -A $install_dir/flutter)" ]; then
  echo "$install_dir/flutter already exists and is not empty."
  exit 1
fi

#
# Fatal errors are accounted for, on to the installers.
#
path_changes=""
start_time="$(date -u +%s)"

# Flutter
if [ ${has_target[flutter]} ]; then
  echo
  echo "==========================================================="
  echo "Setting up Flutter from GitHub (master)"
  echo "See https://flutter.dev/docs/development/tools/sdk/releases"
  echo "==========================================================="
  echo
  git clone -b master https://github.com/flutter/flutter.git "$install_dir/flutter"
  "$install_dir/flutter/bin/flutter" --version

  install_packages lib32stdc++6 clang
  [ $(command_exists make) ] || sudo apt install make

  if [ ! $(path_contains "$install_dir/flutter/bin") ]; then
    export PATH="$PATH:$install_dir/flutter/bin:$install_dir/flutter/bin/cache/dart-sdk/bin:$HOME/.pub-cache/bin"
    path_changes+="$install_dir/flutter/bin:$install_dir/flutter/bin/cache/dart-sdk/bin:$HOME/.pub-cache/bin"
  fi
fi

# Android SDK and tools
if [ ${has_target[flutter]} ] || [ ${has_target[android]} ]; then
  echo
  echo "======================================================="
  echo "Setting up the Android SDK (without Android Studio)"
  echo "See https://developer.android.com/studio/#command-tools"
  echo "======================================================="
  echo
  install_packages default-jre default-jdk wget unzip

  if [ -z "$ANDROID_HOME" ]; then
    export ANDROID_HOME="$install_dir/android"
    echo "export ANDROID_HOME=\"$ANDROID_HOME\"" >>"$HOME/.profile"
  fi

  mkdir "$ANDROID_HOME" >/dev/null 2>&1
  cd "$ANDROID_HOME"

  if [ ! ${installed[android]} ] || [ $force_install ]; then
    wget "$ANDROID_TOOLS_URL"
    unzip -q sdk-tools-linux*.zip*
    rm sdk-tools-linux*.zip*
  fi

  if [ ! $(path_contains "$ANDROID_HOME/tools") ]; then
    export PATH="$PATH:$ANDROID_HOME/tools/bin:$ANDROID_HOME/tools"
    path_changes+=':$ANDROID_HOME/tools/bin:$ANDROID_HOME/tools'
  fi

  # Squelches a repeated warning
  mkdir "$HOME/.android" >/dev/null 2>&1
  touch "$HOME/.android/repositories.cfg"

  yes | sdkmanager --licenses
  # TODO pass this as a version-dependent variable.
  sdkmanager "build-tools;28.0.3" "emulator" "tools" "platform-tools" "platforms;android-28" "extras;google;google_play_services" "extras;google;webdriver" "system-images;android-28;google_apis_playstore;x86_64"

  if [ ! $(path_contains "$ANDROID_HOME/platform-tools") ]; then
    export PATH="$PATH:$ANDROID_HOME/platform-tools"
    path_changes+=':$ANDROID_HOME/platform-tools'
  fi

  # reset pwd
  cd "$install_dir"
fi

# Node and npm (via nvm)
if [ ${has_target[node]} ]; then
  echo
  echo "======================================================="
  echo "Installing Node and npm via Node Version Manager (nvm)"
  echo "See https://github.com/nvm-sh/nvm/blob/master/README.md"
  echo "======================================================="
  echo
  curl -o- "$NVM_SETUP_SCRIPT" | bash

  nvm install node
fi

# Firebase tools
if [ ${has_target[firebase]} ]; then
  echo
  echo "======================================================="
  echo "Installing Firebase tools"
  echo "See https://github.com/nvm-sh/nvm/blob/master/README.md"
  echo "======================================================="
  echo

  npm install -g firebase-tools
fi

# Pyenv
if [ ${has_target[pyenv]} ]; then
  install_packages sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
    xz-utils tk-dev libffi-dev liblzma-dev python-openssl

    curl $PYENV_SETUP_SCRIPT  | bash
fi

# ChromeOS specific
if [ -d /mnt/chromeos ] && [ ! -e "$HOME/Downloads" ]; then
  ln -s /mnt/chromeos/MyFiles/Downloads/ "$HOME/Downloads"
fi

# Extras
[ $(command_exists la) ] || echo 'alias la="ls -a"' >>"$HOME/.profile"
[ $(command_exists ll) ] || echo 'alias ll="ls -la"' >>"$HOME/.profile"
# install_packages software-properties-common
[ -d "$HOME/bin" ] || mkdir "$HOME/bin"

# Finishing up

if [ -n $path_changes ]; then
  echo "export PATH=\"$path_changes:\$PATH\"" >>"$HOME/.profile"
fi

#
# Workspace setup
#
if [ -n "$workspace_dir" ]; then
  curl "https://raw.githubusercontent.com/jifalops/setup_dev_machine/master/workspace_repos.sh" -o "$HOME/bin/workspace_repos.sh"
  chmod +x "$HOME/bin/workspace_repos.sh"
  cd "$HOME/$workspace_dir"
  "$HOME/bin/workspace_repos.sh" init "$workspace_repo"
  "$HOME/bin/workspace_repos.sh" clone
  # Reset pwd
  cd "$install_dir"
fi

# Git config
if [ -n "$git_config_name" ]; then
  git config --global user.name "$git_config_name"
  git config --global user.email "$git_config_email"
fi

# VS Code with settings-sync
if [ ${has_target[vscode]} ]; then
  echo
  echo "======================================================="
  echo "Installing VS Code by adding it to the apt sources list"
  echo "See https://code.visualstudio.com/docs/setup/linux"
  echo "======================================================="
  echo

  sudo apt update
  install_packages software-properties-common apt-transport-https curl
  curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
  sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main"


  curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >microsoft.gpg
  sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
  sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'

  sudo apt update
  install_packages code # or code-insiders

  # Extensions
  if [ ${has_target[flutter]} ] || [ ${installed[flutter]} ]; then
    code --install-extension dart-code.flutter --force
  fi
  if [ ${has_target[python]} ] || [ ${installed[python]} ]; then
    code --install-extension ms-python.python --force
  fi
  code --install-extension shan.code-settings-sync --force

  if [ -n "$code_settings_gist" ]; then
    install_packages jq
    settings_file="$HOME/.config/Code/User/settings.json"
    sync_file="$HOME/.config/Code/User/syncLocalSettings.json"
    default_sync_settings="{ \"sync.gist\": \"$code_settings_gist\", \"sync.autoDownload\": true, \"sync.autoUpload\": true, \"sync.quietSync\": true }"
    if [ -e "$settings_file" ]; then
      echo 'Applying current settings on top of default sync settings.'
      echo "$default_sync_settings $(cat ${settings_file})" | jq -s add >"$settings_file"
    else
      echo "$default_sync_settings" >"$settings_file"
    fi
    if [ -e "$sync_file" ]; then
      tmp=$(mktemp)
      jq ".token = \"$code_settings_token\"" "$sync_file" >"$tmp" && mv "$tmp" "$sync_file"
    else
      echo "{ \"token\": \"$code_settings_token\" }" >"$sync_file"
    fi
    code
  fi
fi

if [ ${has_target[flutter]} ]; then
  "$install_dir/flutter/bin/flutter" doctor
fi

exec $SHELL
end_time="$(date -u +%s)"
elapsed="$(($end_time - $start_time))"
echo
echo "Setup complete in $elapsed seconds."
echo "Restart your terminal session or source ~/.profile to incorporate changes."
