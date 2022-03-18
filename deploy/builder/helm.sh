#!/bin/bash

# Create Helm chart for clickhouse-operator 

# Paths
CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SRC_ROOT="$(realpath "${CUR_DIR}/../..")"

VERSION=$(cd "${SRC_ROOT}"; cat release)

echo "VERSION: ${VERSION}"

HELM_DIR="${SRC_ROOT}/deploy/helm"
VERSION_DIR="${HELM_DIR}/${VERSION}"
DST_DIR_CHART_CRDS="${VERSION_DIR}/crds"
DST_DIR_CHART="${VERSION_DIR}/operator"
mkdir -p ${DST_DIR_CHART_CRDS}
mkdir -p ${DST_DIR_CHART}

# Create chart structure for CRDs
TEMPLATES_DIR_CRDS="${DST_DIR_CHART_CRDS}/templates"
mkdir -p ${TEMPLATES_DIR_CRDS}

cat <<EOF > "${DST_DIR_CHART_CRDS}/Chart.yaml"
apiVersion: v2
name: clickhouse-operator-crds
description: A Helm chart for clickhouse-operator-crds
type: application
version: ${VERSION}
appVersion: ${VERSION}
EOF


# Create chart structure for Operator
TEMPLATES_DIR="${DST_DIR_CHART}/templates"
mkdir -p ${TEMPLATES_DIR}

cat <<EOF > "${DST_DIR_CHART}/Chart.yaml"
apiVersion: v2
name: clickhouse-operator
description: A Helm chart for clickhouse-operator
type: application
version: ${VERSION}
appVersion: ${VERSION}
dependencies:
- name: clickhouse-operator-crds
  version: "${VERSION}"
  repository: "file://../crds"
EOF

## values.yaml file
cat <<EOF > "${DST_DIR_CHART}/values.yaml"
# Choose between setting the username/password here or as a Secret
choUsername: ""
choPassword: ""

# Choose between setting the username/password as a Secret here or otherwise specify it above
choSecretName: "clickhouse-operator"
choSecretNamespace: "{{ .Release.Namespace }}"

# Specify Namespaces where clickhouse-operator will be monitoring for new ClickHouseInstallations
watchNamespaces: []

cho:
  registry: "docker.io"
  image: "altinity/clickhouse-operator"
  tag: ~
  pullPolicy: Always
metricsExporter:
  registry: "docker.io"
  image: "altinity/metrics-exporter"
  tag: ~
  pullPolicy: Always

securityContext: {}

# Labels that will be applied to all resources
additionalLabels: ~

deploymentAnnotations: {}
EOF

cat <<EOF > "${DST_DIR_CHART}/templates/_helpers.yaml"
{{- define "clickhouse-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "clickhouse-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clickhouse-operator.labels" -}}
helm.sh/chart: {{ include "clickhouse-operator.chart" . }}
{{ include "clickhouse-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.additionalLabels }}
{{ toYaml .Values.additionalLabels }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Clickhouse-operator secret generation
*/}}
{{- define "clickhouse-operator.secret" -}}
{{- \$secret := lookup "v1" "Secret" .Release.Namespace "clickhouse-operator" -}}
{{- if \$secret -}}
clickhouse-operator: {{ index \$secret.data "clickhouse-operator" }}
{{- else -}}
clickhouse-operator: {{ randAlphaNum 16 | b64enc }}
{{- end -}}
{{- end -}}
EOF


## Templates
## CRD's
CHI="clickhouseinstallations.clickhouse.altinity.com"
MANIFEST_PRINT_CRD="yes" \
MANIFEST_PRINT_RBAC_CLUSTERED="no" \
MANIFEST_PRINT_RBAC_NAMESPACED="no" \
MANIFEST_PRINT_DEPLOYMENT="no" \
MANIFEST_PRINT_SERVICE_METRICS="no" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.metadata.name == \"${CHI}\")" > "${TEMPLATES_DIR_CRDS}/crd.${CHI}.yaml"

CHIT="clickhouseinstallationtemplates.clickhouse.altinity.com"
MANIFEST_PRINT_CRD="yes" \
MANIFEST_PRINT_RBAC_CLUSTERED="no" \
MANIFEST_PRINT_RBAC_NAMESPACED="no" \
MANIFEST_PRINT_DEPLOYMENT="no" \
MANIFEST_PRINT_SERVICE_METRICS="no" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.metadata.name == \"${CHIT}\")" > "${TEMPLATES_DIR_CRDS}/crd.${CHIT}.yaml"

CHOCONF="clickhouseoperatorconfigurations.clickhouse.altinity.com"
MANIFEST_PRINT_CRD="yes" \
MANIFEST_PRINT_RBAC_CLUSTERED="no" \
MANIFEST_PRINT_RBAC_NAMESPACED="no" \
MANIFEST_PRINT_DEPLOYMENT="no" \
MANIFEST_PRINT_SERVICE_METRICS="no" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.metadata.name == \"${CHOCONF}\")" > "${TEMPLATES_DIR_CRDS}/crd.${CHOCONF}.yaml"

LABELS="  labels:\n    {{- include \"clickhouse-operator.labels\" . | nindent 4 }}"

## ClusterRole
MANIFEST_PRINT_RBAC_NAMESPACED="yes" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq 'select(.kind == "Role")' | 
sed "s/^  labels:/$LABELS/g" |
sed "s/^kind: Role$/kind: ClusterRole/g" |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/role.yaml"

## RoleBinding
## cho's namespace
MANIFEST_PRINT_RBAC_NAMESPACED="yes" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq 'select(.kind == "RoleBinding") | .roleRef.kind = "ClusterRole"' | 
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/role_binding.yaml"

## per namespace
MANIFEST_PRINT_RBAC_NAMESPACED="yes" \
OPERATOR_NAMESPACE="\"{{ $.Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq 'select(.kind == "RoleBinding") | .metadata.namespace = "{{ $ns }}" | .roleRef.kind = "ClusterRole"' | 
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > tmp
cat <<EOF > "${TEMPLATES_DIR}/role_binding_watched_ns.yaml"
{{- \$i := len .Values.watchNamespaces }}
{{- range \$_, \$ns := .Values.watchNamespaces }}
`cat tmp`
{{ ne (\$i = sub \$i 1) 0 | ternary "---" "" }}
{{- end }}
EOF
rm tmp

## RBAC / ServiceAccount
MANIFEST_PRINT_SERVICE_METRICS="no" \
MANIFEST_PRINT_CRD="no" \
MANIFEST_PRINT_RBAC_NAMESPACED="yes" \
MANIFEST_PRINT_DEPLOYMENT="no" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq 'select(.kind == "ServiceAccount")' | 
sed "s/^  labels:/$LABELS/g" |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/service_account.yaml"

## Service
MANIFEST_PRINT_SERVICE_METRICS="yes" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.kind == \"Service\")" |
sed "s/^  labels:/$LABELS/g" |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/service.yaml"

## Deployment
MANIFEST_PRINT_DEPLOYMENT="yes" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.kind == \"Deployment\")" | \
yq '.spec.template.spec.containers[0].image |= "{{ .Values.cho.registry }}/{{ .Values.cho.image }}:{{ .Values.cho.tag | default .Chart.AppVersion }}"' | \
yq '.spec.template.spec.containers[0].imagePullPolicy |= "{{ .Values.cho.pullPolicy }}"' | \
yq '.spec.template.spec.containers[1].image |= "{{ .Values.metricsExporter.registry }}/{{ .Values.metricsExporter.image }}:{{ .Values.metricsExporter.tag | default .Chart.AppVersion }}"' | \
yq '.spec.template.spec.containers[1].imagePullPolicy |= "{{ .Values.metricsExporter.pullPolicy }}"' | \
sed 's/^metadata:/metadata:\n  {{- with .Values.deploymentAnnotations }}\n  annotations:\n    {{- toYaml . | nindent 4 }}\n  {{- end }}/g' |
sed "s/^  labels:/$LABELS/g" |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/deployment.yaml"
echo "      securityContext:" >> "${TEMPLATES_DIR}/deployment.yaml"
echo "        {{- toYaml .Values.securityContext | nindent 8 }}" >> "${TEMPLATES_DIR}/deployment.yaml"

## Configmaps
#watchNamespaces="{{ toJson .Values.watchNamespaces }}" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
chUsername="{{ .Values.choUsername | quote }}" \
chPassword="{{ .Values.choPassword | quote }}" \
password_sha256_hex="{{ .Values.choPassword | sha256sum }}" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.kind == \"ConfigMap\")" | \
sed "s/^  labels:/$LABELS/g" |
sed "s/^      namespaces: \[\]/      namespaces: {{ toJson .Values.watchNamespaces }}/g" | 
sed "s/^          namespace: \"\"$/          namespace: {{ if .Values.choSecretName -}} {{ tpl .Values.choSecretNamespace . | quote }} {{- else -}} \"\" {{- end }}/g" |
sed "s/^          name: \"\"$/          name: {{ .Values.choSecretName | quote }}/g" |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/configmaps.yaml"

## Secret for cho password
cat <<EOF > "${TEMPLATES_DIR}/secret_cho.yaml"
{{- if .Values.choSecretName }}
apiVersion: v1
kind: Secret
metadata:
  name: clickhouse-operator
  namespace: {{ .Release.Namespace }}
type: Opaque
data:
{{- include "clickhouse-operator.secret" . | nindent 2 -}}
{{- end }}
EOF


## package the chart
helm dependency update ${DST_DIR_CHART} > /dev/null
helm package --destination ../helm ${DST_DIR_CHART}


