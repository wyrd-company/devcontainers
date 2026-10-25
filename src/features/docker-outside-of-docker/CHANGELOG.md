# Changelog

## 1.0.0

### Features

- Uses the Docker socket of the host. An s6-overlay service runs the socket proxy when one is needed.
- Based on the Microsoft Docker-outside-of-Docker feature. This feature uses s6-overlay supervision instead of an entrypoint hook, so an image with s6-overlay as PID 1 works.
- Installs the Docker CE CLI by default. Option `moby` selects Microsoft-packaged Moby. The install fails if the Moby packages are not available.
