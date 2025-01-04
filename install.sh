#!/bin/bash
set -eo pipefail

OS=$(uname)

die() {
  echo 'ERROR:' "$@" >&2
  exit 1
}

# OSX can't do `readlink -f`
declare -i has_readlink
if readlink -f "$0" &> /dev/null; then
  has_readlink=1
else
  has_readlink=0
fi
declare -r has_readlink

readlink_f() {
  : "${1:?'Target file not specified.'}"
  declare src="$1"

  if [ "$has_readlink" -eq 1 ]; then
    readlink -f "$src"
  else
    declare dir=
    while [ -h "$src" ]; do
      dir="$(cd -P "$( dirname "$src")" && pwd)"
      src="$(readlink "$src")"
      [[ $src != /* ]] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")"
    echo "$(pwd)/$(basename "$src")"
  fi
}

echo_logger() {
  echo 'Nexus Builder:' "$@"
}



# Set the package name
if [ -z "$package_name" ]; then
  package_name=$(jq -r '.nexus.package_name' package.json)
  if [[ "$package_name" == 'null' ]]; then
    package_name=$(jq -r '.name' package.json)
    if [ "$package_name" == 'null' ]; then
      die 'If no override is provided, your package.json must have element "nexus.package_name" or "name"'
    fi
  fi
fi

# Set the package version
if [ -z "$package_version" ]; then
  package_version=$(jq -r '.nexus.version' package.json)
  if [[ "$package_version" == 'null' ]]; then
    package_version=$(jq -r '.version' package.json)
    if [ "$package_version" == 'null' ]; then
      die 'If no override is provided, your package.json must have element "nexus.package_version" "version"'
    fi
  fi
fi

# Set the package architecture
if [ -z "$architecture" ]; then
  architecture=$(jq -r '.nexus.package_architecture' package.json)
  if [[ "$architecture" == 'null' ]]; then
    architecture="all"
  fi
fi
: ${architecture:='all'}
echo_logger "The package architecture has been set to: $architecture"


# Clean previous install
if dpkg -l | grep -q "^ii  $package_name "; then
    echo_logger "Removing existing package $package_name"
    sudo apt-get purge -y "$package_name"
else
    echo_logger "Package $package_name is not installed"
fi


# the absolute path of the target project's source code on the system
source_dir="$(readlink_f "$(pwd)")"
declare -r source_dir

if [ ! -d "$source_dir/debian" ]; then
  die "Missing debian directory "$source_dir/debian". You must build the package before install"
fi

deb_file="$(pwd)/debian/${package_name}_${package_version}_${architecture}.deb"

echo "Installing $deb_file"

sudo apt install "$deb_file"