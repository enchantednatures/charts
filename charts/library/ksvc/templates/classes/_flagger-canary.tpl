{{- define "ksvc.class.flaggerCanary" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $flagger := .Values.flagger -}}
{{- $lt := $flagger.loadTest -}}
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: {{ $fullname }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
spec:
  provider: knative
  targetRef:
    apiVersion: serving.knative.dev/v1
    kind: Service
    name: {{ $fullname }}
  progressDeadlineSeconds: {{ $flagger.analysis.progressDeadlineSeconds }}
  analysis:
    interval: {{ $flagger.analysis.interval }}
    threshold: {{ $flagger.analysis.threshold }}
    maxWeight: {{ $flagger.analysis.maxWeight }}
    stepWeight: {{ $flagger.analysis.stepWeight }}
    metrics:
      - name: request-success-rate
        thresholdRange:
          min: {{ $flagger.metrics.successRateThreshold }}
        interval: {{ $flagger.analysis.interval }}
      - name: request-duration
        thresholdRange:
          max: {{ $flagger.metrics.latencyP99ThresholdMs }}
        interval: {{ $flagger.analysis.interval }}
    {{- if $lt.enabled }}
    webhooks:
      - name: smoke-test
        type: pre-rollout
        url: {{ $lt.webhookUrl }}
        timeout: 1m
        metadata:
          type: cmd
          cmd: "k6 run --out json /dev/stdin"
          {{- if $lt.script }}
          script: |
            {{- $lt.script | nindent 12 }}
          {{- else }}
          script: |
            import http from 'k6/http';
            import { check, sleep } from 'k6';

            export const options = {
              vus: 1,
              iterations: 5,
              thresholds: {
                'http_req_duration': ['p(95)<{{ $lt.p95ThresholdMs }}'],
              },
            };

            export default function () {
              const res = http.get(
                'http://{{ $fullname }}-canary.{{ .Release.Namespace }}.svc.cluster.local/health/live'
              );
              check(res, {
                'smoke: status is 200': (r) => r.status === 200,
              });
              sleep(0.5);
            }
          {{- end }}
      - name: load-test
        type: rollout
        url: {{ $lt.webhookUrl }}
        timeout: 5m
        metadata:
          {{- if $lt.script }}
          script: |
            {{- $lt.script | nindent 12 }}
          {{- else }}
          script: |
            import http from 'k6/http';
            import { check, sleep } from 'k6';
            import { Rate } from 'k6/metrics';

            const errorRate = new Rate('errors');

            export const options = {
              vus: {{ $lt.vus }},
              duration: '{{ $lt.duration }}',
              thresholds: {
                'http_req_duration': ['p(95)<{{ $lt.p95ThresholdMs }}'],
                'errors': ['rate<{{ $lt.errorRateThreshold }}'],
              },
            };

            export default function () {
              const res = http.get(
                'http://{{ $fullname }}-canary.{{ .Release.Namespace }}.svc.cluster.local/'
              );
              const ok = check(res, {
                'status is 2xx': (r) => r.status >= 200 && r.status < 300,
                'response time OK': (r) => r.timings.duration < {{ $lt.p95ThresholdMs }},
              });
              errorRate.add(!ok);
              sleep(1);
            }
          {{- end }}
    {{- end }}
{{- end }}
