# Go (go)

Installs Go and common Go utilities without replacing an existing container init system.

## Example Usage

```json
"features": {
    "ghcr.io/wyrd-company/devcontainers/go:1": {}
}
```

## Options

| Options Id          | Description                             | Type   | Default Value |
| ------------------- | --------------------------------------- | ------ | ------------- |
| version             | Select or enter a Go version to install | string | latest        |
| golangciLintVersion | Version of golangci-lint to install     | string | latest        |

## Customizations

### VS Code Extensions

- `golang.Go`

## OS Support

This Feature should work on recent versions of Debian/Ubuntu, RedHat Enterprise Linux, Fedora, Alma, and RockyLinux distributions with the apt, yum, dnf, or microdnf package manager installed.

`bash` is required to execute the `install.sh` script.

## Trademarks

This feature is not affiliated with or endorsed by Google LLC. Go and its logo are trademarks of Google LLC. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

The Go gopher was designed by Renee French and is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Logo: the Go gopher from [favicon-gopher.svg](https://github.com/golang/website/blob/52d470bcf26e41fd5a38199c5463268fb61b67ae/_content/images/favicon-gopher.svg).
