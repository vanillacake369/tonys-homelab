package platform

#GatewayPolicy: {
	gatewayNamespace: "gateway"
	gatewayName:      "homelab"
	routeAccessLabel: "homelab"
	...
}

#NetworkPolicyDefaults: {
	dnsNamespace: "kube-system"
	dnsApp:       "kube-dns"
	...
}
