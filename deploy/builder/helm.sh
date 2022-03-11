#!/bin/bash

# Create Helm chart for clickhouse-operator 

# Paths
CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SRC_ROOT="$(realpath "${CUR_DIR}/../..")"

VERSION=$(cd "${SRC_ROOT}"; cat release)

echo "VERSION: ${VERSION}"

HELM_DIR="${SRC_ROOT}/deploy/helm"
DST_DIR="${HELM_DIR}/${VERSION}"
mkdir -p ${DST_DIR}

# create chart structure
cat <<EOF > "${DST_DIR}/Chart.yaml"
apiVersion: v2
name: clickhouse-operator
description: A Helm chart for clickhouse-operator
type: application
version: ${VERSION}
appVersion: ${VERSION}
EOF

## values.yaml file
cat <<EOF > "${DST_DIR}/values.yaml"
clusterScoped: false
choUsername: "clickhouse_operator"
secrets:
  choPassword: "clickhouse_operator_password"

cho:
  registry: "docker.io"
  image: "altinity/clickhouse-operator"
  tag: ~
  pullPolicy: IfNotPresent
metricsExporter:
  registry: "docker.io"
  image: "altinity/metrics-exporter"
  tag: ~
  pullPolicy: IfNotPresent

securityContext: {}
EOF

cat <<EOF > "${DST_DIR}/templates/_helpers.yaml"
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
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
EOF


## Templates
TEMPLATES_DIR="${DST_DIR}/templates"
mkdir -p ${TEMPLATES_DIR}

## CRD's
CHI="clickhouseinstallations.clickhouse.altinity.com"
MANIFEST_PRINT_CRD="yes" \
MANIFEST_PRINT_RBAC_CLUSTERED="no" \
MANIFEST_PRINT_RBAC_NAMESPACED="no" \
MANIFEST_PRINT_DEPLOYMENT="no" \
MANIFEST_PRINT_SERVICE_METRICS="no" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.metadata.name == \"${CHI}\")" > "${TEMPLATES_DIR}/crd.${CHI}.yaml"

CHIT="clickhouseinstallationtemplates.clickhouse.altinity.com"
MANIFEST_PRINT_CRD="yes" \
MANIFEST_PRINT_RBAC_CLUSTERED="no" \
MANIFEST_PRINT_RBAC_NAMESPACED="no" \
MANIFEST_PRINT_DEPLOYMENT="no" \
MANIFEST_PRINT_SERVICE_METRICS="no" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.metadata.name == \"${CHIT}\")" > "${TEMPLATES_DIR}/crd.${CHIT}.yaml"

CHOCONF="clickhouseoperatorconfigurations.clickhouse.altinity.com"
MANIFEST_PRINT_CRD="yes" \
MANIFEST_PRINT_RBAC_CLUSTERED="no" \
MANIFEST_PRINT_RBAC_NAMESPACED="no" \
MANIFEST_PRINT_DEPLOYMENT="no" \
MANIFEST_PRINT_SERVICE_METRICS="no" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.metadata.name == \"${CHOCONF}\")" > "${TEMPLATES_DIR}/crd.${CHOCONF}.yaml"

LABELS="  labels:\n    {{- include \"clickhouse-operator.labels\" . | nindent 4 }}"

## Role
KIND="{{- if .Values.clusterScoped }}\nkind: ClusterRole\n{{- else }}\nkind: Role\n{{- end }}"
MANIFEST_PRINT_RBAC_NAMESPACED="yes" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq 'select(.kind == "Role")' | 
sed "s/^  labels:/$LABELS/g" |
sed "s/^kind: .*$/$KIND/g" |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/role.yaml"

## RoleBinding
KIND="{{- if .Values.clusterScoped }}\nkind: ClusterRoleBinding\n{{- else }}\nkind: RoleBinding\n{{- end }}"
MANIFEST_PRINT_RBAC_NAMESPACED="yes" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq 'select(.kind == "RoleBinding")' | 
sed "s/^  labels:/$LABELS/g" |
sed "s/^kind: .*$/$KIND/g" |
awk 'NR==1,/  namespace: "{{ .Release.Namespace }}"/{sub(/  namespace: "{{ .Release.Namespace }}"/, "{{- if not .Values.clusterScoped }}\n  namespace: {{ .Release.Namespace }}\n{{- end }}")} 1' |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/role_binding.yaml"

## RBAC / ServiceAccount
MANIFEST_PRINT_SERVICE_METRICS="no" \
MANIFEST_PRINT_CRD="no" \
MANIFEST_PRINT_RBAC_NAMESPACED="yes" \
MANIFEST_PRINT_DEPLOYMENT="no" \
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq 'select(.kind == "ServiceAccount")' | 
sed "s/^  labels:/$LABELS/g" |
awk 'NR==1,/  namespace: "{{ .Release.Namespace }}"/{sub(/  namespace: "{{ .Release.Namespace }}"/, "{{- if not .Values.clusterScoped }}\n  namespace: {{ .Release.Namespace }}\n{{- end }}")} 1' |
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
sed "s/^  labels:/$LABELS/g" |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/deployment.yaml"
echo "      securityContext:" >> "${TEMPLATES_DIR}/deployment.yaml"
echo "        {{- toYaml .Values.securityContext | nindent 8 }}" >> "${TEMPLATES_DIR}/deployment.yaml"

## Configmaps
OPERATOR_NAMESPACE="\"{{ .Release.Namespace }}\"" \
watchNamespaces="\"{{ .Release.Namespace | quote }}\"" \
chUsername="\"{{ .Values.choUsername }}\"" \
chPassword="\"{{ .Values.secrets.choPassword }}\"" \
password_sha256_hex="\"{{ .Values.secrets.choPassword | sha256sum }}\"" \
"${CUR_DIR}/cat-clickhouse-operator-install-yaml.sh" | yq "select(.kind == \"ConfigMap\")" | \
sed "s/^  labels:/$LABELS/g" |
sed 's/"\({{[- ].*[- ]}}\)"/\1/' | sed "s/'\({{[- ].*[- ]}}\)'/\1/" > "${TEMPLATES_DIR}/configmaps.yaml"

