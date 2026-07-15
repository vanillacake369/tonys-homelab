package platform

#HTTPPath: =~"^/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*$"

#Health: {
	readinessPath: #HTTPPath
	livenessPath:  #HTTPPath
	startup: {
		enabled:          bool | *true
		periodSeconds:    int & >=1 | *5
		timeoutSeconds:   int & >=1 | *3
		failureThreshold: int & >=1 | *18
	}
	readiness: {
		periodSeconds:    int & >=1 | *10
		timeoutSeconds:   int & >=1 | *3
		failureThreshold: int & >=1 | *3
	}
	liveness: {
		periodSeconds:    int & >=1 | *30
		timeoutSeconds:   int & >=1 | *3
		failureThreshold: int & >=1 | *3
	}
}
