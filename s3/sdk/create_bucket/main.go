package main

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/aws/smithy-go/middleware"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <bucket-name>\n", os.Args[0])
		os.Exit(1)
	}

	if err := run(context.Background(), os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(ctx context.Context, baseName string) error {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}

	accountID, err := getAccountID(ctx, cfg)
	if err != nil {
		return err
	}

	region := cfg.Region
	bucketName := fmt.Sprintf("%s-%s-%s-an", baseName, accountID, region)
	fmt.Printf("Account: %s | Region: %s | Bucket: %s\n", accountID, region, bucketName)

	return createBucket(ctx, s3.NewFromConfig(cfg, withNamespaceHeader()), bucketName, region)
}

func getAccountID(ctx context.Context, cfg aws.Config) (string, error) {
	identity, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return "", fmt.Errorf("get caller identity: %w", err)
	}
	return *identity.Account, nil
}

func createBucket(ctx context.Context, client *s3.Client, bucket, region string) error {
	input := &s3.CreateBucketInput{Bucket: &bucket}

	if region != "us-east-1" {
		input.CreateBucketConfiguration = &types.CreateBucketConfiguration{
			LocationConstraint: types.BucketLocationConstraint(region),
		}
	}

	if _, err := client.CreateBucket(ctx, input); err != nil {
		return fmt.Errorf("create bucket %q: %w", bucket, err)
	}

	fmt.Println("Bucket created successfully.")
	return nil
}

func withNamespaceHeader() func(*s3.Options) {
	return func(o *s3.Options) {
		o.APIOptions = append(o.APIOptions, func(stack *middleware.Stack) error {
			return stack.Build.Add(middleware.BuildMiddlewareFunc("AddBucketNamespaceHeader",
				func(ctx context.Context, in middleware.BuildInput, next middleware.BuildHandler) (middleware.BuildOutput, middleware.Metadata, error) {
					if req, ok := in.Request.(*smithyhttp.Request); ok {
						req.Header.Set("x-amz-bucket-namespace", "account-regional")
					}
					return next.HandleBuild(ctx, in)
				}), middleware.After)
		})
	}
}
