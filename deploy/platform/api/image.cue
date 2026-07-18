package platform

#Digest: =~"^sha256:[a-f0-9]{64}$"

#Image: {
	repository: =~"^[a-z0-9][a-z0-9.-]*(:[0-9]+)?(/[a-z0-9._-]+)+$"
	digest:     #Digest
	ref:        "\(repository)@\(digest)"
	pullPolicy: *"IfNotPresent" | "Always" | "Never"
	pullSecrets: *([]) | [...#DNS1123Name]
}
