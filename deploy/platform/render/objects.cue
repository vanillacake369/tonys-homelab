package platform

import "list"

#Render: {
	app: #WebService

	_policy: #MandatorySecurity & #GatewayPolicy & #NetworkPolicyDefaults

	_labels: {
		"app.kubernetes.io/name":      app.name
		"app.kubernetes.io/component": app.component
	}

	namespace: {
		apiVersion: "v1"
		kind:       "Namespace"
		metadata: {
			name: app.namespace
			labels: {
				"gateway.networking.k8s.io/route-access": _policy.routeAccessLabel
				"pod-security.kubernetes.io/enforce":     "restricted"
				"pod-security.kubernetes.io/audit":       "restricted"
				"pod-security.kubernetes.io/warn":        "restricted"
			}
		}
	}

	serviceAccount: {
		apiVersion: "v1"
		kind:       "ServiceAccount"
		metadata: {
			name:      app.name
			namespace: app.namespace
		}
		imagePullSecrets: [for secret in app.image.pullSecrets {name: secret}]
	}

	deployment: {
		apiVersion: "apps/v1"
		kind:       "Deployment"
		metadata: {
			name:      app.name
			namespace: app.namespace
			labels:    _labels
		}
		spec: {
			replicas: 1
			selector: matchLabels: _labels
			template: {
				metadata: labels: _labels
				spec: {
					serviceAccountName:           app.name
					automountServiceAccountToken: _policy.automountServiceAccountToken
					securityContext: {
						runAsUser:      app.security.runAsUser
						runAsGroup:     app.security.runAsGroup
						runAsNonRoot:   _policy.podSecurityContext.runAsNonRoot
						seccompProfile: _policy.podSecurityContext.seccompProfile
					}
					containers: [{
						name:            app.component
						image:           app.image.ref
						imagePullPolicy: app.image.pullPolicy
						ports: [{
							name:          "http"
							containerPort: app.containerPort
							protocol:      "TCP"
						}]
						env: list.Concat([[for item in app.env {
							name:  item.name
							value: item.value
						}], [for item in app.secretEnv {
							name: item.name
							valueFrom: secretKeyRef: {
								name: item.secret
								key:  item.secretKey
							}
						}]])
						if app.health.startup.enabled {
							startupProbe: {
								httpGet: {
									path: app.health.readinessPath
									port: "http"
								}
								periodSeconds:    app.health.startup.periodSeconds
								timeoutSeconds:   app.health.startup.timeoutSeconds
								failureThreshold: app.health.startup.failureThreshold
							}
						}
						readinessProbe: {
							httpGet: {
								path: app.health.readinessPath
								port: "http"
							}
							periodSeconds:    app.health.readiness.periodSeconds
							timeoutSeconds:   app.health.readiness.timeoutSeconds
							failureThreshold: app.health.readiness.failureThreshold
						}
						livenessProbe: {
							httpGet: {
								path: app.health.livenessPath
								port: "http"
							}
							periodSeconds:    app.health.liveness.periodSeconds
							timeoutSeconds:   app.health.liveness.timeoutSeconds
							failureThreshold: app.health.liveness.failureThreshold
						}
						resources:       app.resources
						securityContext: _policy.containerSecurityContext
						if app.tmpVolume.enabled {
							volumeMounts: [{
								name:      "tmp"
								mountPath: "/tmp"
							}]
						}
					}]
					if app.tmpVolume.enabled {
						volumes: [{
							name: "tmp"
							emptyDir: sizeLimit: app.tmpVolume.sizeLimit
						}]
					}
				}
			}
		}
	}

	service: {
		apiVersion: "v1"
		kind:       "Service"
		metadata: {
			name:      app.name
			namespace: app.namespace
			labels: {
				"app.kubernetes.io/name": app.name
			}
		}
		spec: {
			type:     "ClusterIP"
			selector: _labels
			ports: [{
				name:       "http"
				port:       app.containerPort
				targetPort: "http"
				protocol:   "TCP"
			}]
		}
	}

	httpRoute: {
		apiVersion: "gateway.networking.k8s.io/v1"
		kind:       "HTTPRoute"
		metadata: {
			name:      app.name
			namespace: app.namespace
		}
		spec: {
			parentRefs: [{
				name:      _policy.gatewayName
				namespace: _policy.gatewayNamespace
			}]
			rules: [{
				matches: [{
					path: {
						type:  "PathPrefix"
						value: app.route.pathPrefix
					}
				}]
				backendRefs: [{
					name: app.name
					port: app.containerPort
				}]
			}]
		}
	}

	networkPolicies: {
		defaultDeny: {
			apiVersion: "cilium.io/v2"
			kind:       "CiliumNetworkPolicy"
			metadata: {
				name:      "\(app.name)-default-deny"
				namespace: app.namespace
			}
			spec: {
				endpointSelector: {}
				ingress: []
				egress: []
			}
		}
		workload: {
			apiVersion: "cilium.io/v2"
			kind:       "CiliumNetworkPolicy"
			metadata: {
				name:      "\(app.name)-\(app.component)"
				namespace: app.namespace
			}
			spec: {
				endpointSelector: {
					matchLabels: _labels
				}
				ingress: [{
					fromEntities: ["ingress"]
					toPorts: [{
						ports: [{
							port:     "\(app.containerPort)"
							protocol: "TCP"
						}]
					}]
				}]
				egress: [{
					toEndpoints: [{
						matchLabels: {
							"k8s:k8s-app":                     _policy.dnsApp
							"k8s:io.kubernetes.pod.namespace": _policy.dnsNamespace
						}
					}]
					toPorts: [{
						ports: [
							{port: "53", protocol: "UDP"},
							{port: "53", protocol: "TCP"},
						]
						rules: dns: [{matchPattern: "*"}]
					}]
				}]
			}
		}
	}

	kustomization: {
		apiVersion: "kustomize.config.k8s.io/v1beta1"
		kind:       "Kustomization"
		resources: [
			"namespace.yaml",
			"serviceaccount.yaml",
			"deployment.yaml",
			"service.yaml",
			"httproute.yaml",
			"networkpolicy.yaml",
		]
	}
}

rendered: {
	for name, appIntent in apps {
		"\(name)": #Render & {
			app: appIntent
		}
	}
}
