# Changelog

Release and version history for the `ksvc` library chart is published in
[GitHub Releases](https://github.com/enchantednatures/charts/releases) and the
`<chart>-v<version>` git tags (for example `ksvc-v0.7.16`); see the repository
[release process](../../../README.md#release-process). The entries below are the
only historical notes kept in-repo: the one-off `v0.1.x → v0.2.0` breaking-change
migration.

## Migration from v0.1.x

v0.2.0 is a **breaking change**. The `knativeService:` and top-level `flagger:` /
`kafka:` keys have been replaced.

### Key changes

| v0.1.x | v0.2.0 |
|--------|--------|
| `knativeService.image.repository` | `services.<key>.image.repository` |
| `knativeService.scaling.*` | `services.<key>.scaling.*` |
| `flagger.enabled` | `services.<key>.flagger.enabled` |
| `kafka.enabled` | Remove — presence of `kafka.sources` entries enables Kafka |
| `kafka.source.topic` | `kafka.sources.<key>.topic` |
| `kafka.source.sink` (implicit) | `kafka.sources.<key>.sink` (explicit, validated) |

### Migration steps

1. Replace `knativeService:` with a named entry under `services:`:
   ```yaml
   # Before (v0.1.x)
   knativeService:
     image:
       repository: ghcr.io/org/my-app
       tag: v1.0.0

   # After (v0.2.0)
   services:
     app:
       image:
         repository: ghcr.io/org/my-app
         tag: v1.0.0
   ```

2. Move `flagger:` inside the service entry:
   ```yaml
   # Before
   flagger:
     enabled: true

   # After
   services:
     app:
       flagger:
         enabled: true
   ```

3. Convert `kafka:` to `kafka.sources:` map with explicit `sink`:
   ```yaml
   # Before
   kafka:
     enabled: true
     source:
       topic: my-events

   # After
   kafka:
     sources:
       events:
         topic: my-events
         sink: app    # must match a key in services
   ```
