package main

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/sts"
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
	fmt.Printf("Account: %s | Region: %s\n", accountID, region)
	fmt.Printf("Deleting bucket: %s\n", bucketName)

	_, err = s3.NewFromConfig(cfg).DeleteBucket(ctx, &s3.DeleteBucketInput{
		Bucket: &bucketName,
	})
	if err != nil {
		return fmt.Errorf("delete bucket %q: %w", bucketName, err)
	}

	fmt.Println("Done!")
	return nil
}

func getAccountID(ctx context.Context, cfg aws.Config) (string, error) {
	identity, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return "", fmt.Errorf("get caller identity: %w", err)
	}
	return *identity.Account, nil
}
