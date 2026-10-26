OpenObserve runs under s6-overlay as the selected devcontainer user. Configuration, SQLite metadata, WAL, and data use OpenObserve's native per-user paths and are not persisted by this Feature. Add per-container bind mounts when persistence or object-storage configuration is required. When several containers share one S3 bucket, set `s3BucketPrefix` per container and keep `ZO_S3_BUCKET_PREFIX` out of the shared env file. Set `dnsName` with the Caddy Feature to expose OpenObserve through HTTPS.

## Trademarks

This feature is not affiliated with or endorsed by OpenObserve Inc.. OpenObserve and its logo are trademarks of OpenObserve Inc.. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the OpenObserve mark from [o2_logo.svg](https://github.com/openobserve/openobserve/blob/38f00688dbfd2e87b7064139f93656e057188f94/web/src/assets/images/common/o2_logo.svg) (AGPL-3.0 repository), the same mark as the openobserve.ai favicon. No trademark terms are published.
