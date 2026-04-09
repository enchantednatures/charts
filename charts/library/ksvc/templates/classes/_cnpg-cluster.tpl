{{- define "ksvc.class.cnpgCluster" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $pg := .Values.postgres -}}
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: {{ $fullname }}-postgres
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: database
spec:
  instances: {{ $pg.instances }}
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    major: {{ $pg.version | int }}
  postgresql:
    parameters:
      {{- toYaml $pg.parameters | nindent 6 }}
    shared_preload_libraries:
      {{- toYaml $pg.sharedPreloadLibraries | nindent 6 }}
  resources:
    {{- toYaml $pg.resources | nindent 4 }}
  storage:
    size: {{ $pg.storage.size | quote }}
    storageClassName: {{ $pg.storage.storageClassName | quote }}
  {{- if $pg.backup.enabled }}
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: {{ $fullname }}-postgres-backup-store
  {{- end }}
  bootstrap:
    initdb:
      postInitApplicationSQL:
        {{- toYaml $pg.postInitSQL | nindent 8 }}
  {{- if and $pg.certManager $pg.certManager.enabled }}
  certificates:
    serverTLSSecret: {{ $fullname }}-postgres-server-tls
    serverCASecret: {{ $fullname }}-postgres-server-tls
    clientCASecret: {{ $fullname }}-postgres-client-tls
    replicationTLSSecret: {{ $fullname }}-postgres-client-tls
  {{- end }}
  monitoring:
    enabled: {{ $pg.monitoring.enabled }}
    podMonitorEnabled: {{ $pg.monitoring.enabled }}
{{- end }}
