
# Image URL to use all building/pushing image targets
IMG_MANAGER ?= kubespheredev/porter:v0.1
IMG_AGENT ?= kubespheredev/porter-agent:v0.1
NAMESPACE ?= porter-system

CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: manager

# Run tests
test: fmt vet
	go test -v  ./api/... ./controllers/... ./pkg/...  -coverprofile cover.out

# Build manager binary
manager: fmt vet
	go build -o bin/manager github.com/kubesphere/porter/cmd/manager

# Install CRDs into a cluster
install: manifests
	kubectl apply -f config/crd/bases

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	kubectl apply -f config/crd/bases
	kustomize build config/default | kubectl apply -f -

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./api/...

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./api/..." paths="./controllers/..." output:crd:artifacts:config=config/crd/bases
# Run go fmt against code
fmt:
	go fmt ./pkg/... ./cmd/... ./test/...  ./api/... ./controllers/...

# Run go vet against code
vet:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go vet ./pkg/... ./cmd/... ./test/... ./controllers/...


controller-gen:
ifeq (, $(shell which controller-gen))
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.0
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

debug: vet
	./hack/debug_in_cluster.sh
debug-out-of-cluster: vet
	./hack/manager/debug_out_cluster.sh

debug-log:
	kubectl logs -f -n porter-system controller-manager-0 -c manager

clean-up:
	./hack/cleanup.sh

release:
	./hack/deploy.sh ${IMG_MANAGER} manager
	./hack/deploy.sh ${IMG_AGENT} agent
	sed -i '' -e  's/namespace: .*/namespace: '"${NAMESPACE}"'/' ./config/default/kustomization.yaml
	kustomize build config/default -o deploy/porter.yaml
	@echo "Done, the yaml is in deploy folder named 'porter.yaml'"

release-with-private-registry: test
	./hack/deploy.sh ${IMG_MANAGER} manager --private
	./hack/deploy.sh ${IMG_AGENT} agent --private
	sed -i '' -e  's/namespace: .*/namespace: '"${NAMESPACE}"'/' ./config/default/kustomization.yaml
	@echo "Building yamls"
	kustomize build config/overlays/private_registry -o deploy/porter.yaml
	@echo "Done, the yaml is in deploy folder named 'porter.yaml'"

install-travis:
	chmod +x ./hack/*.sh
	./hack/install_tools.sh

e2e-test: vet
	./hack/e2e.sh
e2e-nobuild:
	./hack/e2e.sh --skip-build

docker-ut:
	docker run --rm -v "${PWD}":/usr/src/github.com/kubesphere/porter -w /usr/src/github.com/kubesphere/porter golang:1.11-alpine  go test -v ./pkg/nettool/