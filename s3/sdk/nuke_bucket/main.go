package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
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

	fmt.Printf("Are you sure you want to nuke %s? (y/n): ", bucketName)
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	answer := strings.ToLower(strings.TrimSpace(scanner.Text()))
	if answer != "y" && answer != "yes" {
		fmt.Println("Aborted.")
		return nil
	}

	client := s3.NewFromConfig(cfg)

	fmt.Printf("Emptying bucket: %s\n", bucketName)
	if err := emptyBucket(ctx, client, bucketName); err != nil {
		return err
	}
	fmt.Println("Bucket emptied.")

	fmt.Printf("Deleting bucket: %s\n", bucketName)
	_, err = client.DeleteBucket(ctx, &s3.DeleteBucketInput{Bucket: &bucketName})
	if err != nil {
		return fmt.Errorf("delete bucket %q: %w", bucketName, err)
	}
	fmt.Println("Bucket deleted.")

	fmt.Println("Done!")
	return nil
}

func emptyBucket(ctx context.Context, client *s3.Client, bucket string) error {
	paginator := s3.NewListObjectsV2Paginator(client, &s3.ListObjectsV2Input{
		Bucket: &bucket,
	})

	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return fmt.Errorf("list objects: %w", err)
		}
		if len(page.Contents) == 0 {
			continue
		}

		objects := make([]types.ObjectIdentifier, len(page.Contents))
		for i, obj := range page.Contents {
			objects[i] = types.ObjectIdentifier{Key: obj.Key}
		}

		_, err = client.DeleteObjects(ctx, &s3.DeleteObjectsInput{
			Bucket: &bucket,
			Delete: &types.Delete{Objects: objects},
		})
		if err != nil {
			return fmt.Errorf("delete objects: %w", err)
		}
	}
	return nil
}

func getAccountID(ctx context.Context, cfg aws.Config) (string, error) {
	identity, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return "", fmt.Errorf("get caller identity: %w", err)
	}
	return *identity.Account, nil
}
