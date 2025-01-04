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


install_build_tools() {
  sudo apt-get install coreutils dpkg fakeroot jq -y
}


install_build_tools



### VALIDATION ###

if [ -z "$1" ]; then
  die 'You must pick at least one file or directory to add to the Debian package'
fi

for file in "$@"; do
  if ! [ -e "$file" ]; then
    die "File does not exist: '$file'. Aborting"
  fi
done

no_delete_temp=1



### INITIALIZE ###

# the absolute path of this executable on the system
nexus_deb_dir="$(dirname "$(readlink_f "${BASH_SOURCE[0]}")")"
declare -r nexus_deb_dir

# the absolute path of the target project's source code on the system
source_dir="$(readlink_f "$(pwd)")"
declare -r source_dir


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

echo_logger "The package name has been set to: $package_name"

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
echo_logger "The package version has been set to: $package_version"


# Set the package description
if [ -z "$package_description" ]; then
  package_description=$(jq -r '.nexus.package_description' package.json)
  if [[ "$package_description" == 'null' ]]; then
    package_description=$(jq -r '.description' package.json)
    if [[ "$package_description" == null ]]; then
      die 'If no override is provided, your package.json must have element "nexus.package_description" or "description"'
    fi
  fi
fi
echo_logger "The package description has been set and starts with: $(echo "$package_description" | head -1 | cut -c-40)"


# Set the package maintainer
if [ -z "$package_maintainer" ]; then
  package_maintainer=$(jq -r '.nexus.package_maintainer' package.json)
  if [[ "$package_maintainer" == 'null' ]]; then
    package_maintainer=$(jq -r '.author' package.json)
  fi
fi
echo_logger "The package maintainer has been set to: $package_maintainer"

# Set the package dependencies
if [ -z "$package_dependencies" ]; then
  package_dependencies=$(jq -r '.nexus.package_dependencies' package.json)
  default_package_dependencies="sudo"
  if [[ "$package_dependencies" != 'null' ]]; then
    default_package_dependencies="${default_package_dependencies}, "
  else
    package_dependencies=""
  fi
  if [[ $no_default_package_dependencies == 1 ]]; then
    default_package_dependencies=""
  fi
  package_dependencies="${default_package_dependencies}${package_dependencies}"
fi
echo_logger "The package dependencies has been set to: $package_dependencies"

# Set the package architecture
if [ -z "$architecture" ]; then
  architecture=$(jq -r '.nexus.package_architecture' package.json)
  if [[ "$architecture" == 'null' ]]; then
    architecture="all"
  fi
fi
: ${architecture:='all'}
echo_logger "The package architecture has been set to: $architecture"

# Set executable name
if [ -z "$executable_name" ]; then
  executable_name=$(jq -r '.nexus.package_executable_name' package.json)
  if [[ "$executable_name" == 'null' ]]; then
    executable_name="$package_name"
  fi
fi
echo_logger "The executable name has been set to: $executable_name"

# Set unix user
if [ -z "$user" ]; then
  user=$(jq -r '.nexus.package_user' package.json)
  if [[ "$user" == 'null' ]]; then
    user="$package_name"
  fi
fi
echo_logger "The Unix user has been set to: $user"

if [ $(printf $user | wc -c) -gt 32 ]; then
  echo "User names must be 32 characters or less. Found: $user" >&2
  exit 1
fi

# Set unix group
if [ -z "$group" ]; then
  group=$(jq -r '.nexus.package_group' package.json)
  if [[ "$group" == 'null' ]]; then
    group="$user"
  fi
fi
echo_logger "The Unix group has been set to: $group"

if [ $(printf $group | wc -c) -gt 32 ]; then
  echo "Group names must be 32 characters or less. Found: $group" >&2
  exit 1
fi

# Set init type
if [ -z "$init" ]; then
  init=$(jq -r '.nexus.init' package.json)
  if [[ "$init" == 'null' ]]; then
    init='auto'
  fi
fi
case $init in
  auto|upstart|systemd|sysv|none)
    ;;
  *)
    die "Invalid init type: $init. Must be 'auto', 'upstart', 'systemd', 'sysv', or 'none'"
esac
echo_logger "The init type has been set to: $init"

# Set npx path
if [ -z "$npx_path" ]; then
  npx_path=$(jq -r '.nexus.npx_path' package.json)
  if [[ "$npx_path" == 'null' ]]; then
    npx_path=$(which npx)
  fi
fi

echo_logger "The npx path has been set to: $npx_path"

# Set install strategy
if [ -z "$install_strategy" ]; then
  install_strategy=$(jq -r '.nexus.install_strategy' package.json)
  if [[ "$install_strategy" == 'null' ]]; then
    install_strategy='auto'
  fi
fi

echo_logger "The install strategy has been set to: $install_strategy"

# Set the install directory
if [ -z "$install_dir" ]; then
  install_dir=$(jq -r '.nexus.install_dir' package.json)
  if [[ "$install_dir" == 'null' ]]; then
    install_dir='/usr/share'
  fi
fi
echo_logger "The install_dir directory was set to: $install_dir"

# Set the daemon entrypoint
if [ -z "$daemon_entrypoint" ]; then
  daemon_entrypoint=$(jq -r '.nexus.entrypoints.daemon' package.json)
  if [[ "$daemon_entrypoint" == 'null' ]] && [[ "$init" != 'none' ]]; then
    die 'Daemon entrypoint must be set in .nexus.entrypoints.daemon in package.json'
  fi
fi
echo_logger "The daemon entrypoint has been set to: $daemon_entrypoint"

# Set the CLI entrypoint
if [ -z "$cli_entrypoint" ]; then
  cli_entrypoint=$(jq -r '.nexus.entrypoints.cli' package.json)
  if [[ "$cli_entrypoint" == 'null' ]]; then
    cli_entrypoint="$daemon_entrypoint"
  fi
fi
echo_logger "The CLI entrypoint has been set to: $cli_entrypoint"

# Templates

# Set systemd unit template
if [ -z "$template_systemd" ]; then
  template_systemd=$(jq -r '.nexus.templates.systemd_service' package.json)
  if [[ "$template_systemd" == 'null' ]]; then
    template_systemd=''
  fi
fi
: ${template_systemd:="$nexus_deb_dir/templates/systemd.service"}
echo_logger "The systemd template has been set to: $template_systemd"

# Set control template
if [ -z "$template_control" ]; then
  template_control=$(jq -r '.nexus.templates.control' package.json)
  if [[ "$template_control" == 'null' ]]; then
    template_control=''
  fi
fi
: ${template_control:="$nexus_deb_dir/templates/control"}
echo_logger "The control template has been set to: $template_control"

# Set executable template
if [ -z "$template_executable" ]; then
  template_executable=$(jq -r '.nexus.templates.executable' package.json)
  if [[ "$template_executable" == 'null' ]]; then
    template_executable=''
  fi
fi
: ${template_executable:="$nexus_deb_dir/templates/executable"}
echo_logger "The executable template has been set to: $template_executable"

# Set preinst template
if [ -z "$template_preinst" ]; then
  template_preinst=$(jq -r '.nexus.templates.preinst' package.json)
  if [[ "$template_preinst" == 'null' ]]; then
    template_preinst=''
  fi
fi
: ${template_preinst:="$nexus_deb_dir/templates/preinst"}
echo_logger "The preinst template has been set to: $template_preinst"

# Set postinst template
if [ -z "$template_postinst" ]; then
  template_postinst=$(jq -r '.nexus.templates.postinst' package.json)
  if [[ "$template_postinst" == 'null' ]]; then
    template_postinst=''
  fi
fi
: ${template_postinst:="$nexus_deb_dir/templates/postinst"}
echo_logger "The postinst template has been set to: $template_postinst"

# Set postrm template
if [ -z "$template_postrm" ]; then
  template_postrm=$(jq -r '.nexus.templates.postrm' package.json)
  if [[ "$template_postrm" == 'null' ]]; then
    template_postrm=''
  fi
fi
: ${template_postrm:="$nexus_deb_dir/templates/postrm"}
echo_logger "The postrm template has been set to: $template_postrm"

# Set prerm template
if [ -z "$template_prerm" ]; then
  template_prerm=$(jq -r '.nexus.templates.prerm' package.json)
  if [[ "$template_prerm" == 'null' ]]; then
    template_prerm=''
  fi
fi
: ${template_prerm:="$nexus_deb_dir/templates/prerm"}
echo_logger "The prerm template has been set to: $template_prerm"

# Set default variables (upstart) conf template
if [ -z "$template_default_variables" ]; then
  template_default_variables=$(jq -r '.nexus.templates.default_variables' package.json)
  if [[ "$template_default_variables" == 'null' ]]; then
    template_default_variables=''
  fi
fi
: ${template_default_variables:="$nexus_deb_dir/templates/default"}
echo_logger "The default variables file template has been set to: $template_default_variables"

deb_dir="$(pwd)/debian/${package_name}_${package_version}_${architecture}"

finish() {
  if [ $no_delete_temp -ne 1 ]; then
    rm -rf "$deb_dir"
  fi
}

trap 'finish' EXIT

### BUILD ###

if [ -e "$deb_dir" ]; then rm -rf "$deb_dir"; fi


mkdir -p "$deb_dir/DEBIAN" \
         "$deb_dir/etc/$package_name" \
         "$deb_dir/etc/default" \
         "$deb_dir$install_dir/$package_name/app" \
         "$deb_dir$install_dir/$package_name/bin" \
         "$deb_dir/lib/systemd/system" \
         "$deb_dir/usr/bin"

escape() {
  sed -e 's/[]\/$*.^|[]/\\&/g' -e 's/&/\\&/g' <<< "$@"
}

 replace_vars() {
  : "${1:?'Template file was not defined'}"
  : "${2:?'Target file was not defined'}"
  : "${3:?'Target file permissions were not defined'}"
  declare -r file="$1"
  declare -r target_file="$2"
  declare -r permissions="$3"

  ### BEGIN TEMPLATE_VARS ###
  sed < "$file" \
    -e "s/{{ nexus_deb_package_name }}/$(escape "$package_name")/g" \
    -e "s/{{ nexus_deb_executable_name }}/$(escape "$executable_name")/g" \
    -e "s/{{ nexus_deb_package_version }}/$(escape "$package_version")/g" \
    -e "s/{{ cli_entrypoint }}/$(escape "$cli_entrypoint")/g" \
    -e "s/{{ daemon_entrypoint }}/$(escape "$daemon_entrypoint")/g" \
    -e "s/{{ nexus_deb_package_description }}/$(escape "$package_description")/g" \
    -e "s/{{ nexus_deb_package_maintainer }}/$(escape "$package_maintainer")/g" \
    -e "s/{{ nexus_deb_package_dependencies }}/$(escape "$package_dependencies")/g" \
    -e "s/{{ nexus_deb_package_architecture }}/$(escape "$architecture")/g" \
    -e "s/{{ nexus_deb_user }}/$(escape "$user")/g" \
    -e "s/{{ nexus_deb_group }}/$(escape "$group")/g" \
    -e "s/{{ nexus_deb_init }}/$(escape "$init")/g" \
    -e "s/{{ nexus_deb_no_rebuild }}/$(escape "$no_rebuild")/g" \
    -e "s/{{ nexus_deb_version }}/$(escape "$package_version")/g" \
    -e "s/{{ install_strategy }}/$(escape "$install_strategy")/g" \
    -e "s/{{ nexus_deb_install_dir }}/$(escape "$install_dir")/g" \
    -e "s/{{ npx_path }}/$(escape "$npx_path")/g" \
  > "$target_file"
  ### END TEMPLATE_VARS ###
  chmod "$permissions" "$target_file"
}

echo_logger 'Rendering templates'
replace_vars "$template_control" "$deb_dir/DEBIAN/control" '0644'
replace_vars "$template_preinst" "$deb_dir/DEBIAN/preinst" '0755'
replace_vars "$template_postinst" "$deb_dir/DEBIAN/postinst" '0755'
replace_vars "$template_postrm" "$deb_dir/DEBIAN/postrm" '0755'
replace_vars "$template_prerm" "$deb_dir/DEBIAN/prerm" '0755'
replace_vars "$template_executable" "$deb_dir$install_dir/$package_name/bin/$executable_name" '0755'
replace_vars "$template_default_variables" "$deb_dir/etc/default/$package_name" '0644'

if [ -f './.env' ]; then
  cat .env >> "$deb_dir/etc/default/$package_name"
fi

if [ "$init" == 'auto' ] || [ "$init" == 'upstart' ]; then
  replace_vars "$template_upstart" "$deb_dir/etc/init/$package_name.conf" '0644'
fi

if [ "$init" == 'auto' ] || [ "$init" == 'systemd' ]; then
  replace_vars "$template_systemd" "$deb_dir/lib/systemd/system/$package_name.service" '0644'
fi

find "$deb_dir/etc" -type f | sed "s/^$(escape "$deb_dir")//" > "$deb_dir/DEBIAN/conffiles"

echo_logger 'Templates rendered successfully'

# copy the main files
find "$@" -type d -print0 | {
  while IFS= read -r -d '' dir; do
    if ! readlink_f "$dir" | grep -Eq "^$source_dir/node_modules/.*"; then
      echo_logger "Making directory: $dir"
      mkdir -p "$deb_dir$install_dir/$package_name/app/$dir"
    fi
  done
}
find "$@" -type f -print0 | {
  while IFS= read -r -d '' file; do
    if ! readlink_f "$file" | grep -Eq "$source_dir/node_modules/.*"; then
      echo_logger "Copying: $file"
      cp -pf  "$file" "$deb_dir$install_dir/$package_name/app/$file"
    fi
  done
}

copy_node_modules() {
  if [ -d "$source_dir/node_modules" ]; then
    echo_logger 'Copying dir: node_modules'
    cp -rfL "$source_dir/node_modules/" "$deb_dir$install_dir/$package_name/app/"
  fi
}


if [[ "$install_strategy" == 'auto' ]]; then
  if [ -d "$source_dir/node_modules" ]; then
    if hash npm 2> /dev/null; then
      mkdir -p "$deb_dir$install_dir/$package_name/app/node_modules"

     
      for dir in $(npm ls --parseable --omit=dev | sed -e "s/$(escape "$source_dir")//g" | grep -Ev '^$' | sed -e 's:^/node_modules/::g' | cut -d / -f 1 | sort -u); do
        echo_logger "Copying dependency: $dir"
        cp -rf "$source_dir/node_modules/$dir" "$deb_dir$install_dir/$package_name/app/node_modules/"
      done

      if [ -f "$source_dir/node_modules/.bin" ]; then
        cp -rfL "$source_dir/node_modules/.bin/" "$deb_dir$install_dir/$package_name/app/node_modules/.bin/"
       
        for e in $(find "$deb_dir$install_dir/$package_name/app/node_modules/.bin/"); do
          stat "$(readlink_f "$e")" || rm -rf "$e"
        done
      fi
    else
      copy_node_modules
    fi
  fi
fi

if [[ "$install_strategy" == 'copy' ]]; then
  copy_node_modules
fi

if ! [ -f "$deb_dir$install_dir/$package_name/app/package.json" ]; then
  echo_logger "Including 'package.json' in the Debian package."
  cp -pf './package.json' "$deb_dir$install_dir/$package_name/app/"
fi

if [ -f './yarn.lock' ] && ! [ -f "$deb_dir$install_dir/$package_name/app/yarn.lock" ]; then
  echo_logger "Including 'yarn.lock' in the Debian package."
  cp -pf './yarn.lock' "$deb_dir$install_dir/$package_name/app/"
fi

if [ -f './npm-shrinkwrap.json' ] && ! [ -f "$deb_dir$install_dir/$package_name/app/npm-shrinkwrap.json" ]; then
  echo_logger "Including 'npm-shrinkwrap.json' in the Debian package."
  cp -pf './npm-shrinkwrap.json' "$deb_dir$install_dir/$package_name/app/"
fi

# Calculate md5sums
echo_logger 'Calculating md5 sums'
# Debian/Ubuntu
if hash md5sum 2>/dev/null; then
  find "$deb_dir" -path "$deb_dir/DEBIAN" -prune -o -type f -print0 | xargs -0 md5sum >> "$deb_dir/DEBIAN/md5sums"
# OSX
elif hash md5 2>/dev/null; then
  find "$deb_dir" -path "$deb_dir/DEBIAN" -prune -o -type f -print0 | {
    while IFS= read -r -d '' file; do
      echo "$(md5 -q "$file") $file" >> "$deb_dir/DEBIAN/md5sums"
    done
  }
# OSX with `brew install gmd5sum`
elif hash gmd5sum 2>/dev/null; then
  find "$deb_dir" -path "$deb_dir/DEBIAN" -prune -o -type f -print0 | xargs -0 gmd5sum >> "$deb_dir/DEBIAN/md5sums"

else
  log_warn 'Unable to find suitable md5 sum program. No md5sums calculated.'
fi

# strip the build dirname from the Debian package
# and then strip the leading slash again
if [ "$OS" == "Linux" ]; then
    sed -i "s/$(escape "$deb_dir")//" "$deb_dir/DEBIAN/md5sums"
    sed -i s:/:: "$deb_dir/DEBIAN/md5sums"
else
    sed -i '' "s/$(escape "$deb_dir")//" "$deb_dir/DEBIAN/md5sums"
    sed -i '' s:/:: "$deb_dir/DEBIAN/md5sums"
fi

echo_logger 'Building Debian package'
if [[ -z "$output_deb_name" ]]; then
  fakeroot dpkg-deb --build "$deb_dir" > '/dev/null'
else
  fakeroot dpkg-deb --build "$deb_dir" "$output_deb_name" > '/dev/null'
fi
echo_logger 'Debian package built.'
exit 0