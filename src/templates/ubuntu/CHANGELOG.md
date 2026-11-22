# Changelog

## 1.0.1

### Fixes

- Keep the image entrypoint and command active so s6 services start in the Ubuntu template.

## 1.0.0

### Features

- Creates a Dev Container from the Ubuntu base image with s6-overlay as PID 1.
- Option `imageVariant` selects `noble` (Ubuntu 24.04) or `resolute` (Ubuntu 26.04).
