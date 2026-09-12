OpenCodex runs under s6-overlay as the service user with state in `${HOME}/.opencodex`. Mount that directory to keep configuration, provider logins, and logs across container rebuilds.

`ocx update` works inside the container as the service user. The system `ocx` wrapper holds the supervised proxy down while the package is replaced, then s6 restarts it on the new version.

Create `/run/opencodex/paused` to hold the proxy down manually; remove it to resume.
