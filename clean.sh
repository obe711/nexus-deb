#!/bin/bash
set -eo pipefail


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

echo "removing package $package_name"

sudo apt-get purge "$package_name"