package platform

apps: {
	"tonys-gis": _tonysGis
}

_tonysGis: #WebService & #SpringBoot & #Small & #Internal & {
	name:      "tonys-gis"
	namespace: "tonys-gis"
	profile:   "spring-boot-small-internal"

	image: {
		repository: "harbor.home.arpa/tonys-gis/tonys-gis"
		digest:     "sha256:cbae25cb11b4729d4e15f9f2885fbcac0bf787e1df791e5b8c541be4e6e3194c"
		pullSecrets: ["harbor-tonys-gis-pull"]
	}

	containerPort: 8080

	route: {
		host:       "homelab-1.taild94cc1.ts.net"
		pathPrefix: "/tonys-gis"
	}

	health: {
		readinessPath: "/tonys-gis/actuator/health/readiness"
		livenessPath:  "/tonys-gis/actuator/health/liveness"
	}
}
