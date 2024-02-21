# Enable the below api's
```bash
google_compute_network
google_compute_subnetwork
google_compute_firewall
google_compute_route
```

# Assign these roles for the service account so that packer can create a compute instance for ami buils
```bash
compute.instanceAdmin.v1
iam.serviceAccountUser
iap.tunnelResourceAccessor
```
