{{- define "ksvc.class.kyvernoScaling" -}}
{{- $apiVersion := .Values.kyverno.scaling.apiVersion -}}
{{- $actions := .Values.kyverno.scaling.validationActions -}}
apiVersion: {{ $apiVersion }}
kind: NamespacedValidatingPolicy
metadata:
  name: {{ .Release.Name }}-scaling-knative
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: admission-policy
spec:
  failurePolicy: Fail
  validationActions:
    {{- toYaml $actions | nindent 4 }}
  matchConstraints:
    resourceRules:
      - apiGroups: ["serving.knative.dev"]
        apiVersions: ["v1"]
        resources: ["services"]
        operations: ["CREATE", "UPDATE"]
  variables:
    - name: minScale
      expression: >-
        has(object.spec.template.metadata.annotations) && 'autoscaling.knative.dev/min-scale' in object.spec.template.metadata.annotations ? object.spec.template.metadata.annotations['autoscaling.knative.dev/min-scale'] : ''
    - name: maxScale
      expression: >-
        has(object.spec.template.metadata.annotations) && 'autoscaling.knative.dev/max-scale' in object.spec.template.metadata.annotations ? object.spec.template.metadata.annotations['autoscaling.knative.dev/max-scale'] : ''
    - name: target
      expression: >-
        has(object.spec.template.metadata.annotations) && 'autoscaling.knative.dev/target' in object.spec.template.metadata.annotations ? object.spec.template.metadata.annotations['autoscaling.knative.dev/target'] : ''
  validations:
    - expression: >-
        (variables.minScale == '' || variables.maxScale == '') ? true : (variables.minScale.matches('^[0-9]+$') && variables.maxScale.matches('^[0-9]+$') && int(variables.minScale) <= int(variables.maxScale))
      message: "Knative Service autoscaling min-scale/max-scale annotations must be integers, and min-scale must be <= max-scale when both are set."
    - expression: >-
        variables.minScale == '' || (variables.minScale.matches('^[0-9]+$') && int(variables.minScale) >= 0)
      message: "Knative Service autoscaling min-scale annotation must be an integer >= 0."
    - expression: >-
        variables.maxScale == '' || (variables.maxScale.matches('^[0-9]+$') && int(variables.maxScale) >= 1)
      message: "Knative Service autoscaling max-scale annotation must be an integer >= 1."
    - expression: >-
        variables.target == '' || (variables.target.matches('^[0-9]+$') && int(variables.target) >= 1)
      message: "Knative Service autoscaling target annotation must be an integer >= 1."
    - expression: >-
        !has(object.spec.template.spec) || !has(object.spec.template.spec.containerConcurrency) || object.spec.template.spec.containerConcurrency >= 0
      message: "Knative Service containerConcurrency must be >= 0."
    - expression: >-
        !has(object.spec.template.spec) || !has(object.spec.template.spec.timeoutSeconds) || object.spec.template.spec.timeoutSeconds >= 1
      message: "Knative Service timeoutSeconds must be >= 1."
---
apiVersion: {{ $apiVersion }}
kind: NamespacedValidatingPolicy
metadata:
  name: {{ .Release.Name }}-scaling-cnpg
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: admission-policy
spec:
  failurePolicy: Fail
  validationActions:
    {{- toYaml $actions | nindent 4 }}
  matchConstraints:
    resourceRules:
      - apiGroups: ["postgresql.cnpg.io"]
        apiVersions: ["v1"]
        resources: ["clusters"]
        operations: ["CREATE", "UPDATE"]
  validations:
    - expression: >-
        !has(object.spec.instances) || (object.spec.instances >= 1 && object.spec.instances <= 16)
      message: "CNPG Cluster spec.instances must be between 1 and 16."
---
apiVersion: {{ $apiVersion }}
kind: NamespacedValidatingPolicy
metadata:
  name: {{ .Release.Name }}-scaling-dragonfly
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: admission-policy
spec:
  failurePolicy: Fail
  validationActions:
    {{- toYaml $actions | nindent 4 }}
  matchConstraints:
    resourceRules:
      - apiGroups: ["dragonflydb.io"]
        apiVersions: ["v1alpha1"]
        resources: ["dragonflies"]
        operations: ["CREATE", "UPDATE"]
  validations:
    - expression: >-
        !has(object.spec.replicas) || (object.spec.replicas >= 1 && object.spec.replicas <= 16)
      message: "Dragonfly spec.replicas must be between 1 and 16."
    - expression: >-
        !has(object.spec.pdb) || !has(object.spec.pdb.minAvailable) || (object.spec.pdb.minAvailable >= 0 && object.spec.pdb.minAvailable <= (has(object.spec.replicas) ? object.spec.replicas : 1))
      message: "Dragonfly PDB minAvailable must be >= 0 and <= spec.replicas."
    - expression: >-
        !has(object.spec.pdb) || !has(object.spec.pdb.maxUnavailable) || object.spec.pdb.maxUnavailable >= 0
      message: "Dragonfly PDB maxUnavailable must be >= 0."
{{- end }}
