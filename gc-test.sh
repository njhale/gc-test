#!/bin/bash

if [[ ${#@} < 2 ]]; then
    echo "Usage: $0 generates a number of mock extension api-services of different gvk's that are restarted periodically and kicks the kube apiserver trigger a specific GC bug"
    echo "* num_mocks: number of mock extension api-services to generate"
    echo "* mock_restart_period: restart period of mock extension api-servers"
    exit 1
fi

num_mocks=$1
mock_restart_period=$2

function cleanup_and_exit {
    read -p "press any key to clean up test resources"
    kubectl delete apiservices,crds,clusterrolebindings,clusterroles -l gcTestParticipant=true
    kubectl -n gc-test delete all -l gcTestParticipant=true
    kubectl delete ns -l gcTestParticipant=true
    kubectl -n kube-system delete roles,rolebindings -l gcTestParticipant=true
    exit $exitCode
}
trap cleanup_and_exit SIGINT SIGTERM EXIT

# Generate and apply $num_mock mock extension api-servers 
until [ $num_mocks -lt 1 ]; do
    # Generate random group name and kind
    group_name="$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-z' | head -c 8)"
    kind="$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-z' | head -c 8)"
    
    # Generate manifests and apply to cluster
    helm template gc-test-chart -f <(echo "{groupName: ${group_name},kind: ${kind},mockRestartPeriod: ${mock_restart_period}}") | kubectl apply --validate=false -f -
    let num_mocks-=1
done

echo "mock extension api-servers running"

function await_cr_creation {
    for try in {1..60} ; do
        [[ $(kubectl -n gc-test create -f long-sock.cr.yaml) == *"sock.footwear.redhat.com/long-sock created"* ]] && break
        sleep 1
    done
}

# Wait for creation of Sock CR to succeed
await_cr_creation

# Set the Sock CR OwnerReference on the ConfigMap and apply to cluster
faq -M ".metadata.ownerReferences[0].uid = \"$(kubectl -n gc-test get sock long-sock -o=jsonpath={.metadata.uid})\"" sock-map.configmap.yaml | kubectl apply -f -
read -p  "ownerreferences set. press any key to continue"

function await_kube_apiserver_ready {
    # Await kube apiserver ready
    while true; do
        [[ $(kubectl -n kube-system wait --for=condition=Ready pod/kube-apiserver-minikube --timeout=60s) == *"pod/kube-apiserver-minikube condition met"* ]] && break
        sleep 1
    done
    echo "kube apiserver restarted"
}

function restart_kube_apiserver {
    while true; do
        date
        echo "restarting kube apiserver..."
        kubectl -n kube-system exec kube-apiserver-minikube -- reboot
        await_kube_apiserver_ready

        # Wait for the kube controller manager to be ready
        kubectl -n kube-system wait --for=condition=Ready pod/kube-controller-manager-minikube --timeout=60s
        kubectl -n gc-test get configmap sock-map
        [[ $(kubectl -n gc-test get configmap sock-map) == *"Error from server (NotFound): configmaps \"sock-map\" not found"* ]] && break
        read -p "press any key to restart the kube apiserver again"
    done
}

restart_kube_apiserver

echo "configmap not found. bug reproduced!"