{{- define "ksvc.class.cnpgAlerts" -}}
{{- $pgName := include "ksvc.postgresName" . -}}
{{- $alerts := .Values.postgres.monitoring.alerts -}}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ $pgName }}-alerts
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app: {{ $pgName }}
    prometheus: kube-prometheus
spec:
  groups:
    - name: postgres.rules
      interval: 30s
      rules:
        - alert: PostgreSQLBackupFailed
          expr: |
            (
              cnpg_collector_backup_last_failed_timestamp > 0
              and
              (time() - cnpg_collector_backup_last_failed_timestamp) < 600
            )
          for: 5m
          labels:
            severity: critical
            component: postgres
          annotations:
            summary: "PostgreSQL backup failed ({{ "{{" }} $labels.cluster {{ "}}" }})"
            description: "Backup for PostgreSQL cluster {{ "{{" }} $labels.cluster {{ "}}" }} failed within the last 10 minutes."
        - alert: PostgreSQLReplicationLag
          expr: |
            cnpg_pg_replication_lag > {{ $alerts.replicationLagWarning }}
          for: 5m
          labels:
            severity: warning
            component: postgres
          annotations:
            summary: "PostgreSQL replication lag detected ({{ "{{" }} $labels.cluster {{ "}}" }})"
            description: "Replication lag is {{ "{{" }} $value {{ "}}" }}s, expected < {{ $alerts.replicationLagWarning }}s."
        - alert: PostgreSQLHighReplicationLag
          expr: |
            cnpg_pg_replication_lag > {{ $alerts.replicationLagCritical }}
          for: 2m
          labels:
            severity: critical
            component: postgres
          annotations:
            summary: "PostgreSQL high replication lag ({{ "{{" }} $labels.cluster {{ "}}" }})"
            description: "Replication lag is {{ "{{" }} $value {{ "}}" }}s. Immediate action required."
        - alert: PostgreSQLInstanceDown
          expr: |
            cnpg_collector_up == 0
          for: 1m
          labels:
            severity: critical
            component: postgres
          annotations:
            summary: "PostgreSQL instance down ({{ "{{" }} $labels.pod {{ "}}" }})"
            description: "PostgreSQL pod {{ "{{" }} $labels.pod {{ "}}" }} is not responding to metrics collection."
        - alert: PostgreSQLHighConnections
          expr: |
            cnpg_pg_stat_activity_count > {{ $alerts.highConnectionCount }}
          for: 5m
          labels:
            severity: warning
            component: postgres
          annotations:
            summary: "PostgreSQL high connection count ({{ "{{" }} $labels.pod {{ "}}" }})"
            description: "PostgreSQL has {{ "{{" }} $value {{ "}}" }} active connections, threshold is {{ $alerts.highConnectionCount }}."
{{- end }}
