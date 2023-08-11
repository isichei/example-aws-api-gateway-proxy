package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

type LambdaResponseBody struct {
	Resource   string `json:"resource"`
	Path       string `json:"path"`
	HTTPMethod string `json:"method"`
	Foo        string `json:"foo"`
	Bar        int    `json:"bar"`
}

func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	fmt.Printf("Processing request data for request %s.\n", request.RequestContext.RequestID)
	foo, foo_prs := request.QueryStringParameters["foo"]
	if !foo_prs {
		foo = "not specified"
	}
	bar := -1
	bar_str, bar_prs := request.QueryStringParameters["text"]
	if bar_prs {
		if bar_conv, err := strconv.Atoi(bar_str); err != nil {
			return events.APIGatewayProxyResponse{Body: "Whoops: cannot convert bar to str", StatusCode: 500, Headers: map[string]string{"Content-Type": "text"}}, nil
		} else {
			bar = bar_conv
		}
	}
	resp := LambdaResponseBody{
		Resource:   request.Resource,
		Path:       request.Path,
		HTTPMethod: request.HTTPMethod,
		Foo:        foo,
		Bar:        bar,
	}

	jbytes, _ := json.Marshal(resp)
	jstr := string(jbytes)

	return events.APIGatewayProxyResponse{Body: jstr, StatusCode: 200, Headers: map[string]string{"Content-Type": "application/html"}}, nil
}

func main() {
	lambda.Start(handleRequest)
}
