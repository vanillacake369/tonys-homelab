package platform

#DNS1123Name: =~"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"

#Metadata: {
	name:      #DNS1123Name
	namespace: #DNS1123Name | *name
	component: #DNS1123Name | *"api"
	profile?:  string
	...
}
