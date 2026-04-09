{{- define "ksvc.class.dragonfly" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $df := .Values.dragonfly -}}
apiVersion: dragonflydb.io/v1alpha1
kind: Dragonfly
metadata:
  name: {{ $fullname }}-dragonfly
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: cache
spec:
  replicas: {{ $df.replicas }}
  {{- if $df.image }}
  image: {{ printf "%s:%s" $df.image $df.imageTag }}
  {{- end }}
  {{- if $df.args }}
  args:
    {{- toYaml $df.args | nindent 4 }}
  {{- end }}
  {{- if $df.env }}
  env:
    {{- toYaml $df.env | nindent 4 }}
  {{- end }}
  {{- if $df.resources }}
  resources:
    {{- toYaml $df.resources | nindent 4 }}
  {{- end }}
  {{- if and $df.authentication $df.authentication.passwordFromSecret $df.authentication.passwordFromSecret.name }}
  authentication:
    passwordFromSecret:
      name: {{ $df.authentication.passwordFromSecret.name }}
      key: {{ $df.authentication.passwordFromSecret.key | default "password" }}
    {{- if and $df.authentication.clientCaCertSecret $df.authentication.clientCaCertSecret.name }}
    clientCaCertSecret:
      name: {{ $df.authentication.clientCaCertSecret.name }}
      key: {{ $df.authentication.clientCaCertSecret.key | default "ca.crt" }}
    {{- end }}
  {{- end }}
  {{- if and $df.tls $df.tls.certManager $df.tls.certManager.enabled }}
  tlsSecretRef:
    name: {{ $fullname }}-dragonfly-server-tls
  {{- else if and $df.tls $df.tls.secretName }}
  tlsSecretRef:
    name: {{ $df.tls.secretName }}
  {{- end }}
  {{- if and $df.snapshot $df.snapshot.enabled }}
  {{- $snap := $df.snapshot }}
  {{- $snapDir := (index $snap "dir") | default "" | toString }}
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
    name: {{ $df.serviceSpec.name }}
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
  {{- if $df.pdb }}
  pdb:
    {{- if $df.pdb.minAvailable }}
    minAvailable: {{ $df.pdb.minAvailable }}
    {{- end }}
    {{- if $df.pdb.maxUnavailable }}
    maxUnavailable: {{ $df.pdb.maxUnavailable }}
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
