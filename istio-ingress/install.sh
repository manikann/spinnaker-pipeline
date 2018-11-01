#!/usr/bin/env bash

set -xeuo pipefail

#helm tiller run helm delete istio-ingress --purge || true
#kubectl delete --ignore-not-found=true -f ./istio-1.0.3/install/kubernetes/helm/istio/templates/crds.yaml
#kubectl delete --ignore-not-found=true namespace istio-system 
#watch kubectl get namespace

kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole=cluster-admin \
  --user=$(gcloud config get-value core/account) \
  --dry-run -o yaml | kubectl apply -f -

helm tiller run helm upgrade istio-ingress  \
              istio \
              --values istio/values-istio-gateways.yaml \
              --set global.crds=true \
              --set security.enabled=true \
              --set pilot.enabled=true \
              --set gateways.custom-gateway.cpu.targetAverageUtilization=80 \
              --set gateways.custom-gateway.externalTrafficPolicy=Local \
              --set gateways.istio-ingressgateway.enabled=false \
              --set gateways.istio-egressgateway.enabled=false \
              --namespace istio-system \
              --install \
              --force

DNS=spinnaker.nataram4.com
SECRET=istio-customgateway-certs

kubectl create -n istio-system secret tls $SECRET \
        --key ${DNS}/3_application/private/${DNS}.key.pem \
        --cert ${DNS}/3_application/certs/${DNS}.cert.pem \
        --dry-run -o  yaml | kubectl apply -f -

kubectl -n spinnaker apply -f ingress.yaml

kubectl -n istio-system delete pods --all
