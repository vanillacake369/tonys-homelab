package platform

#EnvVar: {
	name:  =~"^[A-Z_][A-Z0-9_]*$"
	value: string
}

#SecretEnvRef: {
	name:      =~"^[A-Z_][A-Z0-9_]*$"
	secret:    #DNS1123Name
	secretKey: =~"^[A-Za-z0-9._-]+$"
}

#Route: {
	enabled: bool | *false
	if enabled {
		host:       =~"^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$"
		pathPrefix: #HTTPPath
	}
	if !enabled {
		host?:       string
		pathPrefix?: #HTTPPath
	}
}

#WebService: #Metadata & {
	kind: *"WebService" | "WebService"

	image: #Image

	containerPort: int & >=1 & <=65535

	route: #Route

	health: #Health

	resources: #Resources

	env: *([]) | [...#EnvVar]
	secretEnv: *([]) | [...#SecretEnvRef]

	security: {
		runAsUser:  int & >0 | *10001
		runAsGroup: int & >0 | *10001
	}

	tmpVolume: {
		enabled:   bool | *true
		sizeLimit: string | *"64Mi"
	}
}
