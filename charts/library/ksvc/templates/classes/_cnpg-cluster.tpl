{{- define "ksvc.class.cnpgCluster" -}}
{{- $pg := .Values.postgres -}}
{{- $pgName := include "ksvc.postgresName" . -}}
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: {{ $pgName | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- $globalAnnotations := include "ksvc.annotations" . -}}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  {{- /* Effective secrets = the cluster's own list then the global list; empty
         (both empty) renders nothing. */}}
  {{- with (concat (default (list) $pg.imagePullSecrets) (default (list) .Values.global.imagePullSecrets)) }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  instances: {{ $pg.instances }}
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: {{ $pg.imageCatalog.name | quote }}
    major: {{ $pg.version | int }}
  postgresql:
    parameters:
      {{- include "ksvc.utils.toStringMap" $pg.parameters | nindent 6 }}
    shared_preload_libraries:
      {{- toYaml $pg.sharedPreloadLibraries | nindent 6 }}
  resources:
    {{- toYaml $pg.resources | nindent 4 }}
  storage:
    size: {{ $pg.storage.size | quote }}
    {{- if $pg.storage.storageClassName }}
    storageClass: {{ $pg.storage.storageClassName | quote }}
    {{- end }}
  {{- if $pg.backup.enabled }}
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: {{ include "ksvc.postgresBackupStoreName" . }}
  {{- end }}
  bootstrap:
    initdb:
      postInitApplicationSQL:
        {{- toYaml $pg.postInitSQL | nindent 8 }}
  {{- if and $pg.certManager $pg.certManager.enabled }}
  certificates:
    serverTLSSecret: {{ include "ksvc.postgresServerTLSSecret" . }}
    serverCASecret: {{ include "ksvc.postgresServerCASecret" . }}
    clientCASecret: {{ include "ksvc.postgresClientCASecret" . }}
    replicationTLSSecret: {{ include "ksvc.postgresClientTLSSecret" . }}
  {{- end }}
{{- end }}
