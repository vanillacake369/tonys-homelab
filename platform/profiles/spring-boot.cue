package platform

#SpringBoot: {
	component: *"api" | string
	env: [...#EnvVar]
	env: [{
		name:  "JAVA_OPTS"
		value: "-XX:MaxRAMPercentage=75 -Djava.security.egd=file:/dev/./urandom -Djava.io.tmpdir=/tmp"
	}]
	health: {
		startup: {
			enabled: true
			...
		}
		...
	}
	...
}
