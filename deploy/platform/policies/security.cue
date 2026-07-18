package platform

#MandatorySecurity: {
	automountServiceAccountToken: false
	podSecurityContext: {
		runAsNonRoot: true
		seccompProfile: type: "RuntimeDefault"
	}
	containerSecurityContext: {
		allowPrivilegeEscalation: false
		readOnlyRootFilesystem:   true
		capabilities: drop: ["ALL"]
	}
	...
}
