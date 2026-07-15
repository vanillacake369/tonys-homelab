package platform

#Small: {
	resources: {
		requests: {
			cpu:    *"100m" | string
			memory: *"256Mi" | string
		}
		limits: {
			cpu:    *"1" | string
			memory: *"768Mi" | string
		}
	}
	...
}
