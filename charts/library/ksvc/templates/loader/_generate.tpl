{{/*
ksvc.loader.generate — Render all enabled resources.
Called from the consumer chart's templates/common.yaml.

Because this is a library chart, our values.yaml defaults are NOT automatically
merged. We compute the effective values (consumer values + built-in defaults)
into a local shadow context and render from that; the consumer's `.Values` is
never mutated and a second include of this template re-computes the same
result instead of re-merging the first include's output.

Include it exactly once per release.
*/}}
{{- define "ksvc.loader.generate" -}}

  {{/* ============================================================ */}}
  {{/* Compute effective values (defaults + consumer overrides)     */}}
  {{/* into a local out-dict — `.Values` is never written to.       */}}
  {{/* ============================================================ */}}
  {{- $eff := dict -}}
  {{- include "ksvc.loader.effectiveValues" (dict "root" $ "out" $eff) -}}

  {{/* Effective-values context handed to the validators and classes.
       `.Capabilities` is the same object as `$`'s, so the CRD gating is
       unchanged. */}}
  {{- $ctx := dict "Values" $eff "Chart" $.Chart "Release" $.Release "Capabilities" $.Capabilities "Files" $.Files "Template" $.Template -}}

  {{/* Run validations */}}
  {{- include "ksvc.validate" $ctx -}}

  {{/* ============================================================ */}}
  {{/* Knative Services (iterate the services map)                  */}}
  {{/* The Knative Service itself is the chart's core dependency    */}}
  {{/* (serving.knative.dev/v1) and is never capability-gated.      */}}
  {{/* ============================================================ */}}
  {{- $isFirst := true -}}
  {{- range $key, $svc := $eff.services }}
    {{- if $isFirst -}}
      {{- $isFirst = false -}}
    {{- else }}
---
    {{- end }}
  {{- include "ksvc.class.knativeService" (dict "root" $ctx "key" $key "svc" $svc) | nindent 0 }}
    {{/* Flagger Canary (per-service opt-in, CRD-gated) */}}
    {{- if and $svc.flagger $svc.flagger.enabled ($ctx.Capabilities.APIVersions.Has "flagger.app/v1beta1") }}
---
  {{- include "ksvc.class.flaggerCanary" (dict "root" $ctx "key" $key "svc" $svc) | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* Object Buckets (one ObjectBucketClaim per entry)             */}}
  {{/* ============================================================ */}}
  {{- if and $eff.objectBuckets ($ctx.Capabilities.APIVersions.Has "objectbucket.io/v1alpha1") }}
    {{- range $key, $bucket := $eff.objectBuckets }}
---
  {{- include "ksvc.class.objectBucketClaim" (dict "root" $ctx "key" $key "bucket" $bucket) | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* CloudNativePG PostgreSQL                                     */}}
  {{/* Every resource below is CRD-gated (rendered only when the    */}}
  {{/* matching API version is served) so an offline `helm          */}}
  {{/* template` / a cluster without the CRDs does not emit         */}}
  {{/* unroutable manifests.                                        */}}
  {{/* ============================================================ */}}
  {{- if and $eff.postgres $eff.postgres.enabled }}
    {{- $cnpgAPI := $ctx.Capabilities.APIVersions.Has "postgresql.cnpg.io/v1" }}
    {{- if $cnpgAPI }}
---
  {{- include "ksvc.class.cnpgCluster" $ctx | nindent 0 }}
    {{- end }}
    {{- if and $cnpgAPI $eff.postgres.pooler $eff.postgres.pooler.enabled }}
---
  {{- include "ksvc.class.cnpgPooler" $ctx | nindent 0 }}
    {{- end }}
    {{- if and $eff.postgres.networkPolicy $eff.postgres.networkPolicy.enabled }}
---
  {{- include "ksvc.class.cnpgNetworkPolicy" $ctx | nindent 0 }}
    {{- end }}
    {{- if and $eff.postgres.backup $eff.postgres.backup.enabled ($ctx.Capabilities.APIVersions.Has "barmancloud.cnpg.io/v1") }}
---
  {{- include "ksvc.class.cnpgObjectStore" $ctx | nindent 0 }}
    {{- end }}
    {{- if and $cnpgAPI $eff.postgres.backup $eff.postgres.backup.enabled }}
---
  {{- include "ksvc.class.cnpgScheduledBackup" $ctx | nindent 0 }}
    {{- end }}
    {{- if and $eff.postgres.monitoring $eff.postgres.monitoring.enabled ($ctx.Capabilities.APIVersions.Has "monitoring.coreos.com/v1") }}
---
  {{- include "ksvc.class.cnpgPodMonitor" $ctx | nindent 0 }}
---
  {{- include "ksvc.class.cnpgAlerts" $ctx | nindent 0 }}
    {{- end }}
    {{- if and $eff.postgres.certManager $eff.postgres.certManager.enabled ($ctx.Capabilities.APIVersions.Has "cert-manager.io/v1") }}
---
  {{- include "ksvc.class.certManagerPostgres" $ctx | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* Kafka Event Sources (iterate the kafka.sources map)          */}}
  {{/* The KafkaSource is CRD-gated; the DLQ service is a plain     */}}
  {{/* Knative Service and always renders when enabled.            */}}
  {{/* ============================================================ */}}
  {{- if and $eff.kafka $eff.kafka.sources }}
    {{- range $key, $source := $eff.kafka.sources }}
      {{- if $ctx.Capabilities.APIVersions.Has "sources.knative.dev/v1" }}
---
  {{- include "ksvc.class.kafkaSource" (dict "root" $ctx "key" $key "source" $source) | nindent 0 }}
      {{- end }}
      {{- if and $source.dlq $source.dlq.enabled }}
---
  {{- include "ksvc.class.kafkaDlq" (dict "root" $ctx "key" $key "source" $source) | nindent 0 }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* DragonflyDB Cache Cluster                                   */}}
  {{/* ============================================================ */}}
  {{- if and $eff.dragonfly $eff.dragonfly.enabled }}
    {{- if $ctx.Capabilities.APIVersions.Has "dragonflydb.io/v1alpha1" }}
---
  {{- include "ksvc.class.dragonfly" $ctx | nindent 0 }}
    {{- end }}
    {{- if and $eff.dragonfly.networkPolicy $eff.dragonfly.networkPolicy.enabled }}
---
  {{- include "ksvc.class.dragonflyNetworkPolicy" $ctx | nindent 0 }}
    {{- end }}
    {{- if and $eff.dragonfly.tls $eff.dragonfly.tls.certManager $eff.dragonfly.tls.certManager.enabled ($ctx.Capabilities.APIVersions.Has "cert-manager.io/v1") }}
---
  {{- include "ksvc.class.certManagerDragonfly" $ctx | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* Kyverno Admission Policies (opt-in)                         */}}
  {{/* Gated on the CONFIGURED kyverno.scaling.apiVersion, so the  */}}
  {{/* policies render on both Kyverno >= 1.16 (v1beta1) and       */}}
  {{/* >= 1.17 (v1) clusters and never emit an unserved apiVersion.*/}}
  {{/* ============================================================ */}}
  {{- if and $eff.kyverno $eff.kyverno.enabled $eff.kyverno.scaling $eff.kyverno.scaling.enabled }}
    {{- if $ctx.Capabilities.APIVersions.Has $eff.kyverno.scaling.apiVersion }}
---
{{- include "ksvc.class.kyvernoScaling" $ctx | nindent 0 }}
    {{- end }}
{{- end }}

{{- end }}

{{/*
ksvc.loader.effectiveValues — Compute the effective values: the built-in
defaults (templates/loader/_defaults.tpl) deep-merged with the consumer's
values, consumer values taking precedence. The result is written into the
caller-supplied out-dict (`.out`); the caller's `.Values` is never modified,
so including `ksvc.loader.generate` twice cannot re-merge previously merged
values and never leaks defaults into the consumer's values.

This replaces the previous `ksvc.loader.applyDefaults`, which wrote the merged
result back into the global `.Values` via `set`.
*/}}
{{- define "ksvc.loader.effectiveValues" -}}
{{- $root := .root -}}
{{- $out := .out -}}
{{- $defaults := dict -}}
{{- include "ksvc.loader.defaults" (dict "out" $defaults) -}}

  {{/* --- service defaults (applied to each entry in the services map) --- */}}
  {{- $svcDefaults := $defaults.svc -}}
  {{- $flaggerDefaults := $defaults.flagger -}}
  {{/* Deep-copy the consumer-side maps so nothing computed here can alias
       (and therefore mutate) the consumer's raw `.Values`. */}}
  {{- $services := deepCopy ($root.Values.services | default dict) -}}
  {{- range $key, $svc := $services }}
    {{/* Explicit prometheus.io/port annotations always win; when they are not
         set, the scrape port must follow services.<key>.port instead of the
         historical hard-coded 8080. Capture the raw annotations before the
         merge so "consumer set it" can be told apart from "we defaulted it". */}}
    {{- $rawPodAnnotations := $svc.podAnnotations | default dict -}}
    {{- $rawAnnotations := $svc.annotations | default dict -}}
    {{- $merged := mustMergeOverwrite (deepCopy $svcDefaults) $svc -}}
    {{/* Merge flagger defaults into the service's flagger config */}}
    {{- $svcFlagger := $merged.flagger | default dict -}}
    {{- $_ := set $merged "flagger" (mustMergeOverwrite (deepCopy $flaggerDefaults) $svcFlagger) -}}
    {{- $mergedPodAnnotations := $merged.podAnnotations | default dict -}}
    {{- $mergedAnnotations := $merged.annotations | default dict -}}
    {{- if and (not (hasKey $rawPodAnnotations "prometheus.io/port")) (eq (toString (index $mergedPodAnnotations "prometheus.io/scrape")) "true") -}}
      {{- $_ := set $mergedPodAnnotations "prometheus.io/port" (toString $merged.port) -}}
    {{- end -}}
    {{- if and (not (hasKey $rawAnnotations "prometheus.io/port")) (eq (toString (index $mergedAnnotations "prometheus.io/scrape")) "true") -}}
      {{- $_ := set $mergedAnnotations "prometheus.io/port" (toString $merged.port) -}}
    {{- end -}}
    {{- $_ := set $services $key $merged -}}
  {{- end }}
  {{- $_ := set $out "services" $services -}}

  {{/* --- kafka source defaults (applied to each entry in kafka.sources map) --- */}}
  {{- $kafkaSourceDefaults := $defaults.kafkaSource -}}
  {{- $kafka := deepCopy ($root.Values.kafka | default dict) -}}
  {{- if or (not (hasKey $kafka "sources")) (not $kafka.sources) -}}
    {{- $_ := set $kafka "sources" dict -}}
  {{- end -}}
  {{- range $key, $source := $kafka.sources }}
    {{- $merged := mustMergeOverwrite (deepCopy $kafkaSourceDefaults) $source -}}
    {{- $_ := set $kafka.sources $key $merged -}}
  {{- end }}
  {{- $_ := set $out "kafka" $kafka -}}

  {{/* --- object bucket defaults (applied to each entry in the objectBuckets map) --- */}}
  {{- $bucketDefaults := $defaults.bucket -}}
  {{- $buckets := deepCopy ($root.Values.objectBuckets | default dict) -}}
  {{- range $key, $bucket := $buckets }}
    {{- $merged := mustMergeOverwrite (deepCopy $bucketDefaults) $bucket -}}
    {{- $_ := set $merged "bucketName" (default (include "ksvc.objectBucketName" (dict "root" $root "key" $key)) $merged.bucketName) -}}
    {{- $_ := set $buckets $key $merged -}}
  {{- end }}
  {{- $_ := set $out "objectBuckets" $buckets -}}

  {{/* --- postgres defaults --- */}}
  {{/* Capture RAW consumer objectStore values before the merge so bucketRef
       derivation can tell "consumer set it" apart from "we defaulted it".
       NOTE: sprig `dig` type-asserts its dict to map[string]interface{} and
       rejects chartutil.Values, so walk the nested maps explicitly instead. */}}
  {{- $pgRaw := $root.Values.postgres | default dict -}}
  {{- $pgBackupRaw := $pgRaw.backup | default dict -}}
  {{- $pgStoreRaw := $pgBackupRaw.objectStore | default dict -}}
  {{- $pgCredsRaw := $pgStoreRaw.s3Credentials | default dict -}}
  {{- $rawPgBucketRef := $pgStoreRaw.bucketRef | default "" -}}
  {{- $rawPgDestPath := $pgStoreRaw.destinationPath | default "" -}}
  {{- $rawPgEndpoint := $pgStoreRaw.endpointURL | default "" -}}
  {{- $rawPgCredSecret := $pgCredsRaw.secretName | default "" -}}
  {{- $rawPgCredAccess := $pgCredsRaw.accessKeyIdKey | default "" -}}
  {{- $rawPgCredSecretKey := $pgCredsRaw.secretAccessKeyKey | default "" -}}
  {{- $pgCredsProvided := or $rawPgCredSecret $rawPgCredAccess $rawPgCredSecretKey -}}
  {{/* An explicitly empty securityContext ({} or null) opts out of the
       hardened pooler default; must be detected on the RAW values because the
       merge below cannot unset fields. */}}
  {{- $pgPoolerSCExplicitEmpty := false -}}
  {{- $pgPoolerRaw := $pgRaw.pooler | default dict -}}
  {{- if hasKey $pgPoolerRaw "securityContext" -}}
    {{- $pgPoolerSCExplicitEmpty = eq (len ($pgPoolerRaw.securityContext | default dict)) 0 -}}
  {{- end -}}
  {{- $pgDefaults := $defaults.postgres -}}
  {{- $pg := deepCopy $pgRaw -}}
  {{- $_ := set $out "postgres" (mustMergeOverwrite (deepCopy $pgDefaults) $pg) -}}
  {{- if $pgPoolerSCExplicitEmpty -}}
    {{- $_ := set $out.postgres.pooler "securityContext" (dict) -}}
  {{- end -}}

  {{/* --- postgres bucketRef wiring (objectBuckets entries are defaulted above) --- */}}
  {{- if and $rawPgBucketRef (hasKey ($out.objectBuckets | default dict) $rawPgBucketRef) -}}
    {{- $entry := index $out.objectBuckets $rawPgBucketRef -}}
    {{- $claimName := include "ksvc.objectBucketName" (dict "root" $root "key" $rawPgBucketRef) -}}
    {{- $store := $out.postgres.backup.objectStore -}}
    {{- if not $rawPgDestPath -}}
      {{- $_ := set $store "destinationPath" (printf "s3://%s/" $entry.bucketName) -}}
    {{- end -}}
    {{- if not $rawPgEndpoint -}}
      {{- $_ := set $store "endpointURL" $entry.endpointURL -}}
    {{- end -}}
    {{- if not $pgCredsProvided -}}
      {{- $_ := set $store.s3Credentials "secretName" $claimName -}}
      {{- $_ := set $store.s3Credentials "accessKeyIdKey" "AWS_ACCESS_KEY_ID" -}}
      {{- $_ := set $store.s3Credentials "secretAccessKeyKey" "AWS_SECRET_ACCESS_KEY" -}}
    {{- end -}}
  {{- end -}}

  {{/* --- dragonfly defaults --- */}}
  {{/* Explicitly-empty security contexts ({} or null) opt out of the hardened
       defaults; detected on the RAW values before the merge, which cannot
       unset fields. */}}
  {{- $dfRaw := $root.Values.dragonfly | default dict -}}
  {{- $dfPodSCExplicitEmpty := false -}}
  {{- if hasKey $dfRaw "podSecurityContext" -}}
    {{- $dfPodSCExplicitEmpty = eq (len ($dfRaw.podSecurityContext | default dict)) 0 -}}
  {{- end -}}
  {{- $dfCtrSCExplicitEmpty := false -}}
  {{- if hasKey $dfRaw "containerSecurityContext" -}}
    {{- $dfCtrSCExplicitEmpty = eq (len ($dfRaw.containerSecurityContext | default dict)) 0 -}}
  {{- end -}}
  {{- $dfDefaults := $defaults.dragonfly -}}
  {{- $df := deepCopy $dfRaw -}}
  {{- $_ := set $out "dragonfly" (mustMergeOverwrite (deepCopy $dfDefaults) $df) -}}
  {{- if $dfPodSCExplicitEmpty -}}
    {{- $_ := set $out.dragonfly "podSecurityContext" (dict) -}}
  {{- end -}}
  {{- if $dfCtrSCExplicitEmpty -}}
    {{- $_ := set $out.dragonfly "containerSecurityContext" (dict) -}}
  {{- end -}}

  {{/* --- kyverno defaults --- */}}
  {{- $kyvernoDefaults := $defaults.kyverno -}}
  {{- $kyverno := deepCopy ($root.Values.kyverno | default dict) -}}
  {{- $_ := set $out "kyverno" (mustMergeOverwrite (deepCopy $kyvernoDefaults) $kyverno) -}}

  {{/* --- global defaults --- */}}
  {{- $globalDefaults := $defaults.global -}}
  {{- $global := deepCopy ($root.Values.global | default dict) -}}
  {{- $_ := set $out "global" (mustMergeOverwrite (deepCopy $globalDefaults) $global) -}}

{{- end }}
