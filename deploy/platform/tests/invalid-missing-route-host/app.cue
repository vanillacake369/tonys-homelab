package platform

apps: {
	invalid: _invalid
}

_invalid: #WebService & #SpringBoot & #Small & #Internal & {
	name:      "invalid"
	namespace: "invalid"
	image: {
		repository: "harbor.home.arpa/invalid/invalid"
		digest:     "sha256:1111111111111111111111111111111111111111111111111111111111111111"
	}
	containerPort: 8080
	route: {
		pathPrefix: "/invalid"
	}
	health: {
		readinessPath: "/actuator/health/readiness"
		livenessPath:  "/actuator/health/liveness"
	}
}
