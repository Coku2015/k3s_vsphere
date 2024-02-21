# Automate deploy k3s with vSphere CSI enabled

This script creates a single node k3s cluster on vSphere.
The script need internet access to download the necessary tools and dependencies on the local machine.
The script will create a VM, install k3s and configure a single node cluster with vSphere CSI.
Before you run the script, you need to create a VM template and a VM Customization Specification in vCenter and set the environment variables in the script.

# Pre-requisites

1. Prepare VM template and VM customization spec in vCenter.
2. Internet connection.
3. Download and run the script

# 10 minutes, and you are ready to go with a k3s vsphere cluster.

![pFtI9PA.png](https://s11.ax1x.com/2024/02/21/pFtI9PA.png)