{{- define "ksvc.class.dragonfly" -}}
{{- $df := .Values.dragonfly -}}
{{- $dfName := include "ksvc.dragonflyName" . -}}
{{- $snap := $df.snapshot | default dict -}}
{{- $snapBucketRef := (index $snap "bucketRef") | default "" | toString -}}
{{/*
  Dragonfly S3 snapshot bucket wiring (dragonfly.snapshot.bucketRef).
  When a bucket reference is set we resolve the objectBuckets entry (bucketName
  is already defaulted by applyDefaults) and synthesize the credentials env and
  the derived --s3_endpoint/--s3_use_https args. User-provided env/args are kept
  first; synthesized entries are appended only when missing.
*/}}
{{- $dfEnv := $df.env | default (list) -}}
{{- $dfArgs := $df.args | default (list) -}}
{{- $bucketName := "" -}}
{{- if ne $snapBucketRef "" -}}
  {{- $entry := index (.Values.objectBuckets | default dict) $snapBucketRef -}}
  {{- if $entry -}}
    {{- $bucketName = (index $entry "bucketName") | default "" | toString -}}
    {{- $claimName := include "ksvc.objectBucketName" (dict "root" . "key" $snapBucketRef) -}}
    {{- $region := (index $entry "region") | default "" | toString -}}
    {{- $endpointURL := (index $entry "endpointURL") | default "" | toString -}}
    {{/* Env synthesis: append only missing names; user entries stay first. */}}
    {{- $hasAK := false -}}
    {{- $hasSK := false -}}
    {{- $hasRegion := false -}}
    {{- range $e := $dfEnv -}}
      {{- if kindIs "map" $e -}}
        {{- $n := (index $e "name") | default "" -}}
        {{- if eq $n "AWS_ACCESS_KEY_ID" -}}{{- $hasAK = true -}}{{- end -}}
        {{- if eq $n "AWS_SECRET_ACCESS_KEY" -}}{{- $hasSK = true -}}{{- end -}}
        {{- if eq $n "AWS_REGION" -}}{{- $hasRegion = true -}}{{- end -}}
      {{- end -}}
    {{- end -}}
    {{- if not $hasAK -}}
      {{- $dfEnv = append $dfEnv (dict "name" "AWS_ACCESS_KEY_ID" "valueFrom" (dict "secretKeyRef" (dict "name" $claimName "key" "AWS_ACCESS_KEY_ID"))) -}}
    {{- end -}}
    {{- if not $hasSK -}}
      {{- $dfEnv = append $dfEnv (dict "name" "AWS_SECRET_ACCESS_KEY" "valueFrom" (dict "secretKeyRef" (dict "name" $claimName "key" "AWS_SECRET_ACCESS_KEY"))) -}}
    {{- end -}}
    {{- if and (ne $region "") (not $hasRegion) -}}
      {{- $dfEnv = append $dfEnv (dict "name" "AWS_REGION" "value" $region) -}}
    {{- end -}}
    {{/* Args synthesis: derive scheme-less endpoint + use_https; append only missing flags. */}}
    {{- if ne $endpointURL "" -}}
      {{- $hasEndpoint := false -}}
      {{- $hasHTTPS := false -}}
      {{- range $a := $dfArgs -}}
        {{- $s := $a | toString -}}
        {{- if hasPrefix "--s3_endpoint" $s -}}{{- $hasEndpoint = true -}}{{- end -}}
        {{- if hasPrefix "--s3_use_https" $s -}}{{- $hasHTTPS = true -}}{{- end -}}
      {{- end -}}
      {{- $useHTTPS := "false" -}}
      {{- $hostPort := $endpointURL -}}
      {{- if hasPrefix "https://" $endpointURL -}}
        {{- $useHTTPS = "true" -}}
        {{- $hostPort = trimPrefix "https://" $endpointURL -}}
      {{- else if hasPrefix "http://" $endpointURL -}}
        {{- $hostPort = trimPrefix "http://" $endpointURL -}}
      {{- end -}}
      {{- if not $hasEndpoint -}}
        {{- $dfArgs = append $dfArgs (printf "--s3_endpoint=%s" $hostPort) -}}
      {{- end -}}
      {{- if not $hasHTTPS -}}
        {{- $dfArgs = append $dfArgs (printf "--s3_use_https=%s" $useHTTPS) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
apiVersion: dragonflydb.io/v1alpha1
kind: Dragonfly
metadata:
  name: {{ $dfName | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "cache" | quote }}
  {{- $globalAnnotations := include "ksvc.annotations" . -}}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  replicas: {{ $df.replicas }}
  {{- if $df.image }}
  image: {{ printf "%s:%s" $df.image $df.imageTag }}
  {{- end }}
  {{- if $dfArgs }}
  args:
    {{- toYaml $dfArgs | nindent 4 }}
  {{- end }}
  {{- if $dfEnv }}
  env:
    {{- toYaml $dfEnv | nindent 4 }}
  {{- end }}
  {{- if $df.resources }}
  resources:
    {{- toYaml $df.resources | nindent 4 }}
  {{- end }}
  {{- if and $df.authentication $df.authentication.passwordFromSecret $df.authentication.passwordFromSecret.name }}
  authentication:
    passwordFromSecret:
      name: {{ $df.authentication.passwordFromSecret.name | quote }}
      key: {{ $df.authentication.passwordFromSecret.key | default "password" }}
    {{- if and $df.authentication.clientCaCertSecret $df.authentication.clientCaCertSecret.name }}
    clientCaCertSecret:
      name: {{ $df.authentication.clientCaCertSecret.name | quote }}
      key: {{ $df.authentication.clientCaCertSecret.key | default "ca.crt" }}
    {{- end }}
  {{- end }}
  {{- if and $df.tls $df.tls.certManager $df.tls.certManager.enabled }}
  tlsSecretRef:
    name: {{ include "ksvc.dragonflyServerTLSSecret" . | quote }}
  {{- else if and $df.tls $df.tls.secretName }}
  tlsSecretRef:
    name: {{ $df.tls.secretName | quote }}
  {{- end }}
  {{- if and $df.snapshot $df.snapshot.enabled }}
  {{- $snapDir := (index $snap "dir") | default "" | toString }}
  {{- if and (eq $snapDir "") (ne $bucketName "") -}}
    {{- $snapDir = printf "s3://%s/" $bucketName -}}
  {{- end -}}
  {{- $snapExisting := (index $snap "existingPersistentVolumeClaimName") | default "" | toString }}
  snapshot:
    {{- if $snap.cron }}
    cron: {{ $snap.cron | quote }}
    {{- end }}
    {{- if $snap.enableOnMasterOnly }}
    enableOnMasterOnly: {{ $snap.enableOnMasterOnly }}
    {{- end }}
    {{- if ne $snapDir "" }}
    dir: {{ $snapDir | quote }}
    {{- end }}
    {{- if ne $snapExisting "" }}
    existingPersistentVolumeClaimName: {{ $snapExisting }}
    {{- end }}
    {{- if and (eq $snapDir "") (eq $snapExisting "") $snap.storage $snap.storage.size }}
    persistentVolumeClaimSpec:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: {{ $df.snapshot.storage.size }}
      {{- if $df.snapshot.storage.storageClassName }}
      storageClassName: {{ $df.snapshot.storage.storageClassName | quote }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if $df.serviceSpec }}
  serviceSpec:
    type: {{ $df.serviceSpec.type | default "ClusterIP" }}
    {{- if $df.serviceSpec.name }}
    name: {{ $df.serviceSpec.name | quote }}
    {{- end }}
    {{- if $df.serviceSpec.nodePort }}
    nodePort: {{ $df.serviceSpec.nodePort }}
    {{- end }}
    {{- if $df.serviceSpec.annotations }}
    annotations:
      {{- toYaml $df.serviceSpec.annotations | nindent 6 }}
    {{- end }}
    {{- if $df.serviceSpec.labels }}
    labels:
      {{- toYaml $df.serviceSpec.labels | nindent 6 }}
    {{- end }}
  {{- end }}
  {{- /* PDB: minAvailable and maxUnavailable are mutually exclusive and
       render-time validation rejects both being non-zero. This branch is
       defensive: maxUnavailable wins if it is ever reached with both set.
       Explicit 0 is treated as no constraint rather than a broken manifest. */ -}}
  {{- $pdbMin := int $df.pdb.minAvailable }}
  {{- $pdbMax := int $df.pdb.maxUnavailable }}
  {{- if or $pdbMin $pdbMax }}
  pdb:
    {{- if $pdbMax }}
    maxUnavailable: {{ $pdbMax }}
    {{- else }}
    minAvailable: {{ $pdbMin }}
    {{- end }}
  {{- end }}
  {{- if $df.affinity }}
  affinity:
    {{- toYaml $df.affinity | nindent 4 }}
  {{- end }}
  {{- if $df.tolerations }}
  tolerations:
    {{- toYaml $df.tolerations | nindent 4 }}
  {{- end }}
  {{- if $df.topologySpreadConstraints }}
  topologySpreadConstraints:
    {{- toYaml $df.topologySpreadConstraints | nindent 4 }}
  {{- end }}
  {{- if $df.nodeSelector }}
  nodeSelector:
    {{- toYaml $df.nodeSelector | nindent 4 }}
  {{- end }}
  {{- if $df.podSecurityContext }}
  podSecurityContext:
    {{- toYaml $df.podSecurityContext | nindent 4 }}
  {{- end }}
  {{- if $df.containerSecurityContext }}
  containerSecurityContext:
    {{- toYaml $df.containerSecurityContext | nindent 4 }}
  {{- end }}
  {{- if $df.serviceAccountName }}
  serviceAccountName: {{ $df.serviceAccountName }}
  {{- end }}
  {{- if $df.priorityClassName }}
  priorityClassName: {{ $df.priorityClassName }}
  {{- end }}
{{- end }}
