## pasc
The pasc is a cross-platform command line tool that is intended to help with the development process of Free Pascal / Lazarus projects, assisting during development, testing, build and documentation.

It allows you to create projects, add tests, add automation to documentation, in addition to providing a watch command to monitor the projects folder for changes and thereby trigger the build and test report process.

An interesting feature is the ease with which a new project can be configured to work with vscode providing configuration files for build, to run tests, and even for watch project folder and to trigger build and tests.

## Install

Release binaries are published for Linux and Windows (x86_64). On other platforms, such as macOS, [build from source](#build-from-source).

### With mise (recommended)

[mise](https://mise.jdx.dev) installs pasc from the GitHub releases, and also upgrades and uninstalls it:

```sh
mise use -g github:laprado/pasc
mise upgrade github:laprado/pasc   # later, to upgrade
```

### Manual

Without a package manager, download the zip for your platform from the [latest release](https://github.com/laprado/pasc/releases/latest), check it against `pasc_checksums.txt`, and extract it to a folder in your `PATH`.

Linux:

```sh
curl -fsSLO https://github.com/laprado/pasc/releases/latest/download/pasc-linux-amd64.zip
curl -fsSLO https://github.com/laprado/pasc/releases/latest/download/pasc_checksums.txt
sha256sum -c --ignore-missing pasc_checksums.txt
unzip pasc-linux-amd64.zip -d ~/.local/bin
```

Windows (PowerShell):

```powershell
$release = "https://github.com/laprado/pasc/releases/latest/download"
Invoke-WebRequest "$release/pasc-windows-amd64.zip" -OutFile pasc-windows-amd64.zip
Invoke-WebRequest "$release/pasc_checksums.txt" -OutFile pasc_checksums.txt
$expected = (Select-String "pasc-windows-amd64.zip" pasc_checksums.txt).Line.Split(" ")[0]
if ((Get-FileHash pasc-windows-amd64.zip -Algorithm SHA256).Hash -ne $expected) { throw "checksum mismatch" }
Expand-Archive pasc-windows-amd64.zip -DestinationPath "$env:LOCALAPPDATA\Programs\pasc"
```

Then add `%LOCALAPPDATA%\Programs\pasc` to your user `PATH`. The checksums file is published for the releases after 1.2.1.

### Build from source

Requirements: [Free Pascal](https://www.freepascal.org) 3.2.2, [Lazarus](https://www.lazarus-ide.org) 4.x (for `lazbuild`), [boss](https://github.com/HashLoad/boss) 3.x and git.

```sh
git clone https://github.com/laprado/pasc.git
cd pasc
boss install
lazbuild apps/pasc/pasc.lpi --build-mode=Release
```

The executable is `apps/pasc/pasc` (`pasc.exe` on Windows). Copy it to a folder in your `PATH`.

### Upgrading from `pasc install`

Versions up to 1.2.1 installed themselves with `pasc install`, copying pasc to `~/.pasc` and changing the `PATH`. That command is deprecated: it now only shows these instructions, and how to remove an old install (the `~/.pasc` folder and its `PATH` entry).

## Documentation

Check the [**pasc docs**](https://laprado.github.io/pasc/) for a quick start and the details of available commands.

## pasc on vscode

Take a look of how pasc works in vscode integrated terminal, you can see also a list of available commands:

![pasc on vscode](./docs/generate/pasc_help_dark.jpg#gh-dark-mode-only)
![pasc on vscode](./docs/generate/pasc_help_light.jpg#gh-light-mode-only)

## License

`pasc` is free and open-source software licensed under the [MIT License](https://github.com/laprado/pasc/blob/main/LICENSE). 