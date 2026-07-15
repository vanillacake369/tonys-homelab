package platform

apps: {
	invalid: _invalid
}

_invalid: #WebService & #SpringBoot & #Small & #Internal & {
	name:      "invalid"
	namespace: "invalid"
	image: repository: "harbor.home.arpa/invalid/invalid"
	containerPort: 8080
	route: {
		host:       "homelab-1.taild94cc1.ts.net"
		pathPrefix: "/invalid"
	}
	health: {
		readinessPath: "/actuator/health/readiness"
		livenessPath:  "/actuator/health/liveness"
	}
}
