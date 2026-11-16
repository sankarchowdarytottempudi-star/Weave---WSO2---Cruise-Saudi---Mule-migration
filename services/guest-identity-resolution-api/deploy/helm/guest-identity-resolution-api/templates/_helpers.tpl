{{- define "gir.name" -}}guest-identity-resolution-api{{- end -}}
{{- define "gir.labels" -}}
app.kubernetes.io/name: {{ include "gir.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
integration.aroya/layer: process
{{- end -}}
{{- define "gir.selector" -}}
app.kubernetes.io/name: {{ include "gir.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "gir.podSecurity" -}}
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
fsGroup: 10001
seccompProfile: {type: RuntimeDefault}
{{- end -}}
{{- define "gir.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities: {drop: [ALL]}
{{- end -}}
{{- define "gir.dbEnv" -}}
- {name: GIR_DB_HOST, value: {{ required "database.host is required" .Values.database.host | quote }}}
- {name: GIR_DB_PORT, value: {{ .Values.database.port | quote }}}
- {name: GIR_DB_NAME, value: {{ required "database.name is required" .Values.database.name | quote }}}
- {name: GIR_DATABASE_SCHEMA, value: {{ .Values.database.schema | quote }}}
- {name: GIR_DB_SSLMODE, value: {{ .Values.database.sslmode | quote }}}
- {name: GIR_DB_SSLROOTCERT, value: /var/run/secrets/gir/db-ca/ca.crt}
{{- end -}}
