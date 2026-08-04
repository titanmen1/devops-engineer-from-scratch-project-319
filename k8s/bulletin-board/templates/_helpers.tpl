{{/*
Имя релиза используется в именах ресурсов, чтобы в одном кластере уживались
несколько окружений одного чарта.
*/}}
{{- define "bulletin-board.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "bulletin-board.labels" -}}
app: {{ include "bulletin-board.name" . }}
app.kubernetes.io/name: bulletin-board
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "bulletin-board.selectorLabels" -}}
app: {{ include "bulletin-board.name" . }}
{{- end -}}
