# Changelog

## 1.0.0

### Features

- Installs the Grok CLI for the Dev Container user with xAI's native installer.
- Adds `grok` to the PATH. The executable and its state stay owned by the user, not root.
- The feature does not add the `agent` alias, so it does not replace another tool that provides `agent`.
- Option `version` selects the version to install.
