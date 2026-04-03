{{- define "olympic-tracker-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "olympic-tracker-chart.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "olympic-tracker-chart.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "olympic-tracker-chart.labels" -}}
app.kubernetes.io/name: {{ include "olympic-tracker-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "olympic-tracker-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "olympic-tracker-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
