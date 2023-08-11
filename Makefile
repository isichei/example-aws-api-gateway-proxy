.PHONY: build deploy destroy

build:
	GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bin/bootstrap main.go

deploy:
	terraform apply -auto-approve

destroy:
	terraform destroy -auto-approve