module github.com/xaionaro-go/wingout2

go 1.25.5

require (
	github.com/stretchr/testify v1.11.1
	github.com/xaionaro-go/avpipeline v0.0.0-20260215180403-57903ccb8003
	github.com/xaionaro-go/ffstream v0.0.0-00010101000000-000000000000
	github.com/xaionaro-go/player v0.0.0-20260202200119-7935ded39620
	github.com/xaionaro-go/streamctl v0.0.0-00010101000000-000000000000
	google.golang.org/grpc v1.79.1
	google.golang.org/protobuf v1.36.11
)

require (
	github.com/davecgh/go-spew v1.1.2-0.20180830191138-d8f796af33cc // indirect
	github.com/kr/text v0.2.0 // indirect
	github.com/pmezard/go-difflib v1.0.1-0.20181226105442-5d4384ee4fb2 // indirect
	github.com/xaionaro-go/chatwebhook v0.0.0-20260104185322-4dc28c63093a // indirect
	golang.org/x/net v0.49.0 // indirect
	golang.org/x/sys v0.40.0 // indirect
	golang.org/x/text v0.33.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260120174246-409b4a993575 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace github.com/xaionaro-go/ffstream => /home/streaming/go/src/github.com/xaionaro-go/ffstream

replace github.com/xaionaro-go/avpipeline => /home/streaming/go/src/github.com/xaionaro-go/avpipeline

replace github.com/xaionaro-go/streamctl => /home/streaming/go/src/github.com/xaionaro-go/streamctl

replace github.com/xaionaro-go/chatwebhook => /home/streaming/go/src/github.com/xaionaro-go/chatwebhook

replace github.com/xaionaro-go/player => /home/streaming/go/src/github.com/xaionaro-go/player
