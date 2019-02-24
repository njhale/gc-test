# Kube Garbage Collection Issue Reproduction

The `gc-test.sh` script and accompanying `gc-helm-chart` are an attempt to build a means to reproduces a suspected kubernetes garbage collection issue.

## Issue

Resources with an `OwnerReference` pointing to a `CustomResource` are sometimes garbage collected when their parent still exists.

## Observed When

The issue seems to occur when the kube apiserver or kube controller-manager pods are restarted (multiple times?) on a cluster with both CRDs defined and multiple extension api-servers.

## Thoughts on Root Cause

From inspecting the kubernetes 1.12 garbage collection logic, it looks like the issue could occur if the kube apiserver returns 404 when requesting a CR during an issue with discovery.

## Test Requirements

* `kubectl`
* `minikube` running at kubernetes version 1.12
* `faq`: https://github.com/jzelinskie/faq

## Test Design

The `gc-test.sh` test script executes the following steps:
1. Generate the `gc-test` namespace
2. Generate the given number of [mock extension apiservers](https://github.com/operator-framework/mock-extension-apiserver) which serve discovery for randomly generated kinds and are configured to fail at a given period (pods and services in the `gc-test` namespace) - this is meant to cause discovery issues 
3. Create the `Sock` CRD and respective `lock-sock` CR in the `gc-test` namespace
4. Create the `sock-map` `ConfigMap` in the `gc-test` namespace with an `OwnerReference` that points to the `long-sock` CR
6. Wait for keyboard input
7. `exec` a reboot command to the only container in the `kube-apiserver-minikube` pod
8. Wait for the `kube-apiserver-minikube` pod to have status condition `Ready`
9. Wait for the `kube-controller-manager-minikube` pod to have status condition `Ready`
10. Check if the `sock-map` `ConfigMap` still exists - if so, exit (issue has been reproduced)
11. Wait for keyboard input
12. goto step 7

> Note: The `gc-test.sh` script __must__ run against `minikube`

## Results

The `gc-test.sh` script has __not been able to reproduce the issue on minikube__.
