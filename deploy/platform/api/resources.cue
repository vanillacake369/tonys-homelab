package platform

#Quantity: =~"^[0-9]+(m|Mi|Gi)?$"

#Resources: {
	requests: {
		cpu:    #Quantity
		memory: #Quantity
	}
	limits: {
		cpu:    #Quantity
		memory: #Quantity
	}
}
