# Records docs/user/assets/base-image.gif, the base image media on wyrd.foo.
# Run from the repository root: vhs docs/media/base-image.tape
# Needs Docker and the published image ghcr.io/wyrd-company/devcontainers/base:noble.

Output docs/user/assets/base-image.gif

Require docker

Set Shell bash
Set FontSize 16
Set Width 1200
Set Height 640
Set Padding 24
Set TypingSpeed 40ms
Set Theme "Catppuccin Mocha"

Hide
Type "docker run -d --rm --name base-image-demo ghcr.io/wyrd-company/devcontainers/base:noble >/dev/null && sleep 2" Enter
Sleep 4s
Type "docker exec -it -u vscode -e PS1='vscode@base:~$ ' -w /home/vscode base-image-demo bash --norc" Enter
Sleep 2s
Type "clear" Enter
Sleep 500ms
Show

Type "# s6-overlay runs as PID 1" Enter
Sleep 300ms
Type "ps -o pid,comm -p 1" Enter
Sleep 2s

Type "# vscode may install packages with sudo" Enter
Sleep 300ms
Type "sudo apt-get update -qq && sudo apt-get install -y -qq --no-install-recommends jq >/dev/null" Enter
Wait@90s /~\$$/
Type "jq --version" Enter
Sleep 2s

Type "# and control s6 services" Enter
Sleep 300ms
Type "sudo /command/s6-rc -a list" Enter
Sleep 2s

Type "# every other sudo command is denied" Enter
Sleep 300ms
Type "sudo -n id" Enter
Sleep 3s

Hide
Type "exit" Enter
Sleep 1s
Type "docker stop base-image-demo >/dev/null" Enter
Sleep 3s
