# nexus-deb

Node JS Debian packager


## Usage

- Clone into project directory of node repo
```
git submodule add git@github.com:obe711/nexus-deb.git
```

- Add `nexus` property to `package.json`
```json
...
  "scripts": {
    "start": "cross-env NODE_ENV=development node --watch src/index.js"
  },
  "nexus": {
    "package_name": "your-new-package",
    "install_strategy": "auto",
    "package_description": "Description of your new package",
    "package_maintainer": "Obediah Klopfenstein <obe711@gmail.com>",
    "package_dependencies": "git",
    "package_architecture": "amd64",
    "package_executable_name": "your-executable",
    "package_user": "a-user",
    "package_group": "a-user-group",
    "init": "systemd",
    "entrypoints": {
      "daemon": "bin/your-bin.js --daemon"
    }
  },
```

- Run packager - arguments are files and/or directories to include in package
```
./nexus-deb/nexus-deb.sh src/ bin/ README.md .env
```

- Install package
```
sudo apt install ./debian/your_new_package_1.0.0_amd64.deb
```

- Remove package
```
sudo apt remove your_new_package
```
