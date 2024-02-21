#!/bin/bash
#######################  Note #######################
# This script is used to create a k3s cluster on vSphere.
# The script need internet access to download the necessary tools and dependencies on the local machine.
# The script will create a VM, install k3s and configure a single node cluster with vSphere CSI.
# Before you run the script, you need to create a VM template and a VM Customization Specification in vCenter and set the environment variables in the script.
# To create VM template in vCenter, you can do it manually or use Packer to create the VM template.
#####################################################

#######################  Environment Variables Section  ######################
###  Modify the following environment variables to match your environment  ###
MY_SSH_USER="ubuntu"
MY_VSPHERE_SERVER="172.16.0.100"
MY_VSPHERE_USERNAME="administrator@vsphere.local"
MY_VSPHERE_PASSWORD="VMware123!"
MY_DATACENTER="MyDatacenter"
MY_VM_TEMPLATE="Ubuntu20.04LTS"
MY_DATASTORE="localdatastore"
#######################  Environment Section End   ###########################
#######################  DO NOT MODIFY BELOW THIS LINE  ######################

if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script."
    exit 1
fi
contact_us="https://blog.backupnext.cloud"

HAS_GOVC="$(type "govc" &> /dev/null && echo true || echo false)"
HAS_HELM="$(type "helm" &> /dev/null && echo true || echo false)"
HAS_KUBECTL="$(type "kubectl" &> /dev/null && echo true || echo false)"
HAS_K3SUP="$(type "k3sup" &> /dev/null && echo true || echo false)"

COLOR_BLUE='\E[1;34m'
RESET_COLOR="\033[0m"

clearscreen(){
    local clear_flag=""
    clear_flag=$1
    if [[ ${clear_flag} == "clear" ]]; then
        clear
    fi
    echo ""
    echo "+----------------------------------------------------------------------+"
    echo "|              K3S with vSphere CSI automation script                  |"
    echo "+----------------------------------------------------------------------+"
    echo "|  This script is used to create a single node k3s cluster on vSphere. |"
    echo "|  The script will create a VM, install k3s and configure a single node|"
    echo "|  cluster with vSphere CSI.                                           |"
    echo "|  It's suitable for testing and learning purpose.                     |"
    echo "|  Please be noticed that the script can't be used in production.      |"
    echo "+----------------------------------------------------------------------+"
    echo "|  Intro: ${contact_us}                                |"
    echo "|  Bug Report: Lei.wei@veeam.com                                       |"
    echo "+----------------------------------------------------------------------+"
    echo ""
}

#check and install pre-requisites
check_prerequisites() {
  if [ "$HAS_GOVC" = false ]; then
    install_govc
  fi
  if [ "$HAS_HELM" = false ]; then
    install_helm
  fi
  if [ "$HAS_KUBECTL" = false ]; then
    install_kubectl
  fi
  if [ "$HAS_K3SUP" = false ]; then
    install_k3sup
  fi
}

install_govc() {
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Installing govc..."
  curl -fsSL -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | tar -C /usr/local/bin -xvzf - govc 2>&1 > /dev/null
  chmod +x /usr/local/bin/govc
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Setting govc environment variables..."
  export GOVC_URL="$MY_VSPHERE_SERVER"
  export GOVC_USERNAME="$MY_VSPHERE_USERNAME"
  export GOVC_PASSWORD="$MY_VSPHERE_PASSWORD"
  export GOVC_INSECURE=1
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - govc is installed to /usr/local/bin/govc"
}

install_helm() {
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Installing helm..."
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 2>&1 > /dev/null
  chmod 700 get_helm.sh
  ./get_helm.sh 2>&1 > /dev/null
  rm -f get_helm.sh
  #add helm repo and update
  helm repo add vsphere-cpi https://kubernetes.github.io/cloud-provider-vsphere 2>&1 > /dev/null
  helm repo update 2>&1 > /dev/null
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Helm is installed to /usr/local/bin/helm"
}

install_k3sup() {
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Installing k3sup..."
  curl -fsSL https://get.k3sup.dev | sh 2>&1 > /dev/null
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - k3sup installed to /usr/local/bin"
}

install_kubectl() {
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Installing kubectl..."
  curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" 2>&1 > /dev/null
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl 2>&1 > /dev/null
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - kubectl is installed to /usr/local/bin/kubectl"
  rm -rf kubectl
  mkdir -p /root/.kube/
}

input_settings() {
  def_vmname="k3s-cluster-$(shuf -i 1000-9999 -n 1)"
  echo "Please enter the VM name:"
  read -p "(Default VM name will be ‘k3s-cluster-<4 random number>’):" vmname
  [ -z "${vmname}" ] && vmname="${def_vmname}"

  def_ip="192.168.1.$(shuf -i 100-200 -n 1)"
  echo "Please enter the IP address for the VM:"
  read -p "(Default IP address will be ‘192.168.1.<random number>’):" ip
  [ -z "${ip}" ] && ip="${def_ip}"

  def_version="v1.28.6+k3s2"
  echo "Please enter the k3s version:"
  read -p "(Default version will be ‘v1.28.6+k3s2’):" version
  [ -z "${version}" ] && version="${def_version}"
}

# Main
clearscreen "clear"
input_settings
check_prerequisites
echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Creating VM $vmname with IP $ip..."
govc vm.clone -vm $MY_VM_TEMPLATE -c=2 -m=8192 -ds=$MY_DATASTORE -pool=Resources -on=false ${vmname} 2>&1 > /dev/null
govc vm.customize -vm ${vmname} -ip=$ip Ubuntu 2>&1 > /dev/null
govc vm.power -on ${vmname} 2>&1 > /dev/null
echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - VM $vmname is created and powered on."

while true; do
  output=$(govc vm.info ${vmname})
  if echo "$output" | grep -q "IP address:.*${ip}"; then
    echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - IP address found: $ip"
    # waiting SSH available
    while ! ssh "$MY_SSH_USER"@"$ip" true; do
      echo "SSH connection not available, waiting..."
      sleep 10
    done
    break
  else
    echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Waiting for IP address to appear..."
    sleep 60
  fi
done

echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Installing k3s on ${vmname}..."
k3sup install --ip ${ip} --user ${MY_SSH_USER} \
    --no-extras --k3s-extra-args '--disable-cloud-controller --disable-network-policy --disable=local-storage' \
    --k3s-version ${version} \
    --local-path /root/.kube/config-${vmname} \
    --context ${vmname} 2>&1 > /dev/null

export KUBECONFIG=/root/.kube/config-${vmname}
while true
do
  kubectl wait --for=condition=ready --timeout=3000s -n kube-system pod --all > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - k3s is installed and ready on ${vmname}"
    break
  else
    echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Waiting for k3s to be ready..."
    sleep 10
  fi
done

echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Configuring k3s vsphere csi on ${vmname}..."
ssh "$MY_SSH_USER"@"$ip" "printf \"        '--kubelet-arg=cloud-provider=external' \\\\n\" | sudo tee -a /root/k3s.service > /dev/null"
ssh "$MY_SSH_USER"@"$ip" "printf \"        '--kubelet-arg=provider-id=vsphere://\\\$master_node_id' \\\\n\" | sudo tee -a /root/k3s.service > /dev/null"
ssh "$MY_SSH_USER"@"$ip" 'sudo systemctl daemon-reload && sudo service k3s restart'

# check if node is ready, if not, wait for 10 seconds
while [ -z "$(kubectl get no | grep Ready)" ]; do
  echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Waiting for k3s to be ready..."
  sleep 10
done
nodeid=$(kubectl get no | grep Ready | awk '{print $1}')
kubectl taint nodes $nodeid node-role.kubernetes.io/control-plane=:NoSchedule 2>&1 > /dev/null

helm install vsphere-cpi vsphere-cpi/vsphere-cpi --namespace kube-system \
	--set config.enabled=true \
	--set config.vcenter=$MY_VSPHERE_SERVER \
	--set config.username=$MY_VSPHERE_USERNAME \
	--set config.password=$MY_VSPHERE_PASSWORD \
	--set config.datacenter=$MY_DATACENTER  2>&1 > /dev/null

echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Waiting for vsphere-cpi to be ready..."
while true
do
  kubectl wait --for=condition=ready --timeout=3000s -n kube-system pod --all > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - vsphere-cpi is installed and ready on ${vmname}"
    break
  else
    echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Waiting for vsphere-cpi to be ready..."
    sleep 10
  fi
done
kubectl create namespace vmware-system-csi 2>&1 > /dev/null
cat <<EOF > csi-vsphere.conf
[Global]

[VirtualCenter "$MY_VSPHERE_SERVER"]
insecure-flag = "true"
user = "$MY_VSPHERE_USERNAME"
password = "$MY_VSPHERE_PASSWORD"
port = "443"
datacenters = "$MY_DATACENTER"
EOF

kubectl create secret generic vsphere-config-secret --from-file=csi-vsphere.conf --namespace=vmware-system-csi 2>&1 > /dev/null
#download the yaml file and modify the replica to 1
curl -fsSLO https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.0.0/manifests/vanilla/vsphere-csi-driver.yaml
csi_file="vsphere-csi-driver.yaml"
sed -i 's/replicas: 3/replicas: 1/g' $csi_file
sed -i 's/^.*node-role\.kubernetes\.io\/control-plane:.*$/        node-role.kubernetes.io\/control-plane: "true"/' $csi_file

kubectl apply -f $csi_file -n vmware-system-csi 2>&1 > /dev/null
echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Waiting CSI services are up running"
while true
do
  kubectl wait --for=condition=ready --timeout=3000s -n vmware-system-csi pod --all > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - vSphere CSI is installed and ready on ${vmname}"
    break
  else
    echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Waiting for vSphere CSI to be ready..."
    sleep 10
  fi
done
kubectl taint nodes $nodeid node-role.kubernetes.io/control-plane=:NoSchedule- 2>&1 > /dev/null

MY_DATASTORE_URL=$(govc datastore.info localnvme | grep 'URL:' | awk '{print $2}')
cat <<EOF > storageclass.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: $MY_DATASTORE
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.vmware.com
parameters:
  datastoreurl: $MY_DATASTORE_URL
EOF
kubectl apply -f storageclass.yaml 2>&1 > /dev/null
echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - Storage class $MY_DATASTORE is created."
# clean up
rm -rf csi-vsphere.conf
rm -rf storageclass.yaml
rm -rf $csi_file

echo -e "${COLOR_BLUE}[ $(date +"%Y-%m-%d %H:%M:%S") ]${RESET_COLOR} - All done!"
echo "=============================================================="
echo "You can now access the k3s cluster with the following command:"
echo "export KUBECONFIG=/root/.kube/config-${vmname}"
echo "kubectl config use-context ${vmname}"
echo "kubectl get no"
echo "kubectl get po -A"
echo "=============================================================="
