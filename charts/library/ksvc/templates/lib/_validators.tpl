{{/*
Validate required values at template render time.
Call this from the loader to catch misconfigurations early.
*/}}
{{- define "ksvc.validate" -}}
  {{/* services map must exist and have at least one entry */}}
  {{- if not .Values.services -}}
    {{- fail "services is required and must contain at least one service entry" -}}
  {{- end -}}
  {{- if not (kindIs "map" .Values.services) -}}
    {{- fail "services must be a map (e.g. services: { api: { ... } })" -}}
  {{- end -}}
  {{- if eq (len .Values.services) 0 -}}
    {{- fail "services must contain at least one service entry" -}}
  {{- end -}}

  {{/* global name overrides become part of resource names, so they must be
       valid DNS-1123 labels (<= 63 chars, lowercase alphanumerics and dashes) */}}
  {{- if .Values.global.nameOverride -}}
    {{- include "ksvc.validate.dns1123Label" (dict "value" .Values.global.nameOverride "path" "global.nameOverride") -}}
  {{- end -}}
  {{- if .Values.global.fullnameOverride -}}
    {{- include "ksvc.validate.dns1123Label" (dict "value" .Values.global.fullnameOverride "path" "global.fullnameOverride") -}}
  {{- end -}}

  {{/* each service must have image.repository */}}
  {{- range $key, $svc := .Values.services -}}
    {{/* map keys and nameOverride become name suffixes: validate them first */}}
    {{- include "ksvc.validate.dns1123Label" (dict "value" $key "path" (printf "services.%s" $key)) -}}
    {{- if $svc.nameOverride -}}
      {{- include "ksvc.validate.dns1123Label" (dict "value" $svc.nameOverride "path" (printf "services.%s.nameOverride" $key)) -}}
    {{- end -}}
    {{- if not $svc.image -}}
      {{- fail (printf "services.%s.image is required" $key) -}}
    {{- end -}}
    {{- if not $svc.image.repository -}}
      {{- fail (printf "services.%s.image.repository is required" $key) -}}
    {{- end -}}
    {{/* an image reference must resolve to an explicit tag or an immutable digest */}}
    {{- if and (not $svc.image.tag) (not $svc.image.digest) -}}
      {{- fail (printf "services.%s.image.tag is required (or set services.%s.image.digest)" $key $key) -}}
    {{- end -}}
    {{/* scaling must be a map; a nil/non-map cannot render and must fail cleanly */}}
    {{- if not (kindIs "map" $svc.scaling) -}}
      {{- fail (printf "services.%s.scaling must be a map (got %v)" $key $svc.scaling) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.minScale "path" (printf "services.%s.scaling.minScale" $key)) -}}
    {{- $minScale := int $svc.scaling.minScale -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.maxScale "path" (printf "services.%s.scaling.maxScale" $key)) -}}
    {{- $maxScale := int $svc.scaling.maxScale -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.target "path" (printf "services.%s.scaling.target" $key)) -}}
    {{- $target := int $svc.scaling.target -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.containerConcurrency "path" (printf "services.%s.scaling.containerConcurrency" $key)) -}}
    {{- $containerConcurrency := int $svc.scaling.containerConcurrency -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.timeoutSeconds "path" (printf "services.%s.scaling.timeoutSeconds" $key)) -}}
    {{- $timeoutSeconds := int $svc.scaling.timeoutSeconds -}}
    {{- if lt $minScale 0 -}}
      {{- fail (printf "services.%s.scaling.minScale must be >= 0 (got %d)" $key $minScale) -}}
    {{- end -}}
    {{- if lt $maxScale 1 -}}
      {{- fail (printf "services.%s.scaling.maxScale must be >= 1 (got %d)" $key $maxScale) -}}
    {{- end -}}
    {{- if gt $minScale $maxScale -}}
      {{- fail (printf "services.%s.scaling: minScale (%d) must be <= maxScale (%d)" $key $minScale $maxScale) -}}
    {{- end -}}
    {{- if lt $target 1 -}}
      {{- fail (printf "services.%s.scaling.target must be >= 1 (got %d)" $key $target) -}}
    {{- end -}}
    {{- if lt $containerConcurrency 0 -}}
      {{- fail (printf "services.%s.scaling.containerConcurrency must be >= 0 (got %d)" $key $containerConcurrency) -}}
    {{- end -}}
    {{- if lt $timeoutSeconds 1 -}}
      {{- fail (printf "services.%s.scaling.timeoutSeconds must be >= 1 (got %d)" $key $timeoutSeconds) -}}
    {{- end -}}
  {{- end -}}

  {{/* objectBuckets entry validation (runs after applyDefaults).
       Per-entry check order is fixed (storageClassName, key, bucketName) so the
       failure message is deterministic. */}}
  {{- if .Values.objectBuckets -}}
    {{- range $key, $bucket := .Values.objectBuckets -}}
      {{- if not $bucket.storageClassName -}}
        {{- fail (printf "objectBuckets.%s.storageClassName is required and must name an existing bucket StorageClass" $key) -}}
      {{- end -}}
      {{- if or (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $key)) (gt (len $key) 53) -}}
        {{- fail (printf "objectBuckets.%s must be a DNS-1123 label" $key) -}}
      {{- end -}}
      {{- if not (regexMatch "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$" $bucket.bucketName) -}}
        {{- fail (printf "objectBuckets.%s.bucketName must be a valid S3 bucket name (3-63 chars, lowercase letters, digits, dots, hyphens)" $key) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* postgres backup validation */}}
  {{- if and .Values.postgres.enabled .Values.postgres.backup.enabled (not .Values.postgres.backup.objectStore.destinationPath) -}}
    {{- fail "postgres.backup.objectStore.destinationPath is required when postgres backup is enabled" -}}
  {{- end -}}
  {{- if and .Values.postgres.enabled .Values.postgres.backup.enabled (not .Values.postgres.backup.objectStore.endpointURL) -}}
    {{- fail "postgres.backup.objectStore.endpointURL is required when postgres backup is enabled" -}}
  {{- end -}}
  {{/* postgres backup bucketRef validation (defensive read: the key may not exist yet if todo 5 has not landed) */}}
  {{- $pgBucketRef := .Values.postgres.backup.objectStore.bucketRef | default "" -}}
  {{- if $pgBucketRef -}}
    {{- if and .Values.postgres.backup.enabled (not (hasKey .Values.objectBuckets $pgBucketRef)) -}}
      {{- fail (printf "postgres.backup.objectStore.bucketRef references '%s' which does not exist in objectBuckets" $pgBucketRef) -}}
    {{- end -}}
    {{- if not .Values.postgres.backup.enabled -}}
      {{- fail "postgres.backup.objectStore.bucketRef is set but postgres.backup.enabled is false" -}}
    {{- end -}}
  {{- end -}}

  {{/* postgres instance count validation */}}
  {{- if .Values.postgres.enabled -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" .Values.postgres.instances "path" "postgres.instances") -}}
    {{- $pgInstances := int .Values.postgres.instances -}}
    {{- if or (lt $pgInstances 1) (gt $pgInstances 16) -}}
      {{- fail (printf "postgres.instances must be >= 1 and <= 16 (got %d)" $pgInstances) -}}
    {{- end -}}
    {{- if .Values.postgres.pooler.enabled -}}
      {{- include "ksvc.validate.requireInteger" (dict "value" .Values.postgres.pooler.instances "path" "postgres.pooler.instances") -}}
      {{- $poolerInstances := int .Values.postgres.pooler.instances -}}
      {{- if lt $poolerInstances 1 -}}
        {{- fail (printf "postgres.pooler.instances must be >= 1 (got %d)" $poolerInstances) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* kafka source sink validation: each source's sink must reference a valid services key */}}
  {{- if and .Values.kafka .Values.kafka.sources -}}
    {{- range $key, $source := .Values.kafka.sources -}}
      {{/* source keys become part of KafkaSource/DLQ/consumer-group names */}}
      {{- include "ksvc.validate.dns1123Label" (dict "value" $key "path" (printf "kafka.sources.%s" $key)) -}}
      {{- if not $source.sink -}}
        {{- fail (printf "kafka.sources.%s.sink is required and must reference a key in the services map" $key) -}}
      {{- end -}}
      {{- if not (hasKey $.Values.services $source.sink) -}}
        {{- fail (printf "kafka.sources.%s.sink references '%s' which does not exist in the services map" $key $source.sink) -}}
      {{- end -}}
      {{/* DLQ scaling validation (only when the DLQ is enabled) */}}
      {{- if and $source.dlq $source.dlq.enabled -}}
        {{- if not (kindIs "map" $source.dlq.scaling) -}}
          {{- fail (printf "kafka.sources.%s.dlq.scaling must be a map (got %v)" $key $source.dlq.scaling) -}}
        {{- end -}}
        {{- include "ksvc.validate.requireInteger" (dict "value" $source.dlq.scaling.minScale "path" (printf "kafka.sources.%s.dlq.scaling.minScale" $key)) -}}
        {{- $dlqMinScale := int $source.dlq.scaling.minScale -}}
        {{- include "ksvc.validate.requireInteger" (dict "value" $source.dlq.scaling.maxScale "path" (printf "kafka.sources.%s.dlq.scaling.maxScale" $key)) -}}
        {{- $dlqMaxScale := int $source.dlq.scaling.maxScale -}}
        {{- if lt $dlqMinScale 0 -}}
          {{- fail (printf "kafka.sources.%s.dlq.scaling.minScale must be >= 0 (got %d)" $key $dlqMinScale) -}}
        {{- end -}}
        {{- if lt $dlqMaxScale 1 -}}
          {{- fail (printf "kafka.sources.%s.dlq.scaling.maxScale must be >= 1 (got %d)" $key $dlqMaxScale) -}}
        {{- end -}}
        {{- if gt $dlqMinScale $dlqMaxScale -}}
          {{- fail (printf "kafka.sources.%s.dlq.scaling: minScale (%d) must be <= maxScale (%d)" $key $dlqMinScale $dlqMaxScale) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* cert-manager issuer validation: an enabled certManager block must resolve to a non-empty issuer name (locally or via global.certManager.issuerRef.name) */}}
  {{- $globalIssuerName := "" }}
  {{- if and .Values.global .Values.global.certManager -}}
    {{- $globalIssuerName = .Values.global.certManager.issuerRef.name | default "" -}}
  {{- end -}}
  {{- if and .Values.postgres.enabled .Values.postgres.certManager .Values.postgres.certManager.enabled -}}
    {{- $issuerName := .Values.postgres.certManager.issuerRef.name | default $globalIssuerName | toString | trim -}}
    {{- if not $issuerName -}}
      {{- fail "postgres.certManager: issuerRef.name must be set (locally or via global.certManager.issuerRef.name) when certManager is enabled — an empty issuerRef produces an invalid Certificate" -}}
    {{- end -}}
  {{- end -}}
  {{- if and .Values.dragonfly.enabled .Values.dragonfly.tls .Values.dragonfly.tls.certManager .Values.dragonfly.tls.certManager.enabled -}}
    {{- $issuerName := .Values.dragonfly.tls.certManager.issuerRef.name | default $globalIssuerName | toString | trim -}}
    {{- if not $issuerName -}}
      {{- fail "dragonfly.tls.certManager: issuerRef.name must be set (locally or via global.certManager.issuerRef.name) when certManager is enabled — an empty issuerRef produces an invalid Certificate" -}}
    {{- end -}}
  {{- end -}}

  {{/* dragonfly replica and PDB validation */}}
  {{- if .Values.dragonfly.enabled -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" .Values.dragonfly.replicas "path" "dragonfly.replicas") -}}
    {{- $dfReplicas := int .Values.dragonfly.replicas -}}
    {{- if or (lt $dfReplicas 1) (gt $dfReplicas 16) -}}
      {{- fail (printf "dragonfly.replicas must be >= 1 and <= 16 (got %d)" $dfReplicas) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" .Values.dragonfly.pdb.minAvailable "path" "dragonfly.pdb.minAvailable") -}}
    {{- $dfPdbMinAvailable := int .Values.dragonfly.pdb.minAvailable -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" .Values.dragonfly.pdb.maxUnavailable "path" "dragonfly.pdb.maxUnavailable") -}}
    {{- $dfPdbMaxUnavailable := int .Values.dragonfly.pdb.maxUnavailable -}}
    {{- if and (ne $dfPdbMinAvailable 0) (ne $dfPdbMaxUnavailable 0) -}}
      {{- fail "dragonfly.pdb: minAvailable and maxUnavailable are mutually exclusive — set one of them to 0" -}}
    {{- end -}}
    {{- if and (ne $dfPdbMinAvailable 0) (gt $dfPdbMinAvailable $dfReplicas) -}}
      {{- fail (printf "dragonfly.pdb.minAvailable (%d) must be <= dragonfly.replicas (%d)" $dfPdbMinAvailable $dfReplicas) -}}
    {{- end -}}
  {{- end -}}

  {{/* dragonfly snapshot dir is mutually exclusive with an existing PVC: `dir`
       renders an S3 backup path while existingPersistentVolumeClaimName renders
       a claim reference — setting both produces an ambiguous/broken spec. */}}
  {{- if and .Values.dragonfly.enabled .Values.dragonfly.snapshot.enabled -}}
    {{- $dfSnapDir := .Values.dragonfly.snapshot.dir | default "" | toString -}}
    {{- $dfSnapPVC := .Values.dragonfly.snapshot.existingPersistentVolumeClaimName | default "" | toString -}}
    {{- if and $dfSnapDir $dfSnapPVC -}}
      {{- fail "dragonfly.snapshot: dir and existingPersistentVolumeClaimName are mutually exclusive" -}}
    {{- end -}}
  {{- end -}}

  {{/* dragonfly snapshot bucketRef validation (defensive read) */}}
  {{- $dfBucketRef := .Values.dragonfly.snapshot.bucketRef | default "" -}}
  {{- if $dfBucketRef -}}
    {{- if or (not .Values.dragonfly.enabled) (not .Values.dragonfly.snapshot.enabled) -}}
      {{- fail "dragonfly.snapshot.bucketRef requires dragonfly.enabled and dragonfly.snapshot.enabled" -}}
    {{- end -}}
    {{- if not (hasKey .Values.objectBuckets $dfBucketRef) -}}
      {{- fail (printf "dragonfly.snapshot.bucketRef references '%s' which does not exist in objectBuckets" $dfBucketRef) -}}
    {{- end -}}
    {{- if .Values.dragonfly.snapshot.existingPersistentVolumeClaimName -}}
      {{- fail "dragonfly.snapshot: bucketRef and existingPersistentVolumeClaimName are mutually exclusive" -}}
    {{- end -}}
    {{- if not (index .Values.objectBuckets $dfBucketRef).endpointURL -}}
      {{- fail "dragonfly.snapshot.bucketRef requires an endpointURL on the referenced bucket" -}}
    {{- end -}}
  {{- end -}}
{{- end }}

{{/*
ksvc.validate.dns1123Label — Reject values that must be usable as a Kubernetes
resource name component (a DNS-1123 label: <= 63 chars, lowercase
alphanumerics and dashes, starting and ending with an alphanumeric). Used for
consumer-supplied name fragments — `global.nameOverride`,
`global.fullnameOverride`, the `services` map keys, each
`services.<key>.nameOverride`, and the `kafka.sources` map keys — which are
concatenated into rendered resource names. Without this check an uppercase or
dotted override silently produces an invalid resource name.
*/}}
{{- define "ksvc.validate.dns1123Label" -}}
{{- $v := .value | toString -}}
{{- if or (gt (len $v) 63) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $v)) -}}
{{- fail (printf "%s must be a DNS-1123 label (<= 63 chars, lowercase alphanumerics and dashes)" .path) -}}
{{- end -}}
{{- end }}

{{/*
ksvc.validate.requireInteger — Reject non-integer numeric values before they are
truncated by `int` (which would turn 1.5 into 1 and let invalid values through).
Accepts integer kinds and whole floats (e.g. 10.0); rejects fractional floats,
non-numeric strings, and non-numeric kinds. Negative integers are allowed here so
that the existing range checks (>= 0 / >= 1) keep producing their original messages.
*/}}
{{- define "ksvc.validate.requireInteger" -}}
{{- $v := .value -}}
{{- if kindIs "string" $v -}}
  {{- if not (regexMatch "^-?[0-9]+$" $v) -}}
    {{- fail (printf "%s must be an integer (got %s)" .path $v) -}}
  {{- end -}}
{{- else if kindIs "float64" $v -}}
  {{- if ne $v (floor $v) -}}
    {{- fail (printf "%s must be an integer (got %v)" .path $v) -}}
  {{- end -}}
{{- else if or (kindIs "bool" $v) (kindIs "slice" $v) (kindIs "map" $v) (kindIs "invalid" $v) -}}
  {{- fail (printf "%s must be an integer (got %v)" .path $v) -}}
{{- end -}}
{{- end }}
