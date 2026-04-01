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
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s <source-bucket> <destination-bucket>\n", os.Args[0])
		os.Exit(1)
	}

	if err := run(context.Background(), os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(ctx context.Context, srcBase, dstBase string) error {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}

	accountID, err := getAccountID(ctx, cfg)
	if err != nil {
		return err
	}

	region := cfg.Region
	srcBucket := fmt.Sprintf("%s-%s-%s-an", srcBase, accountID, region)
	dstBucket := fmt.Sprintf("%s-%s-%s-an", dstBase, accountID, region)
	fmt.Printf("Account: %s | Region: %s\n", accountID, region)
	fmt.Printf("Copying from: %s\n", srcBucket)
	fmt.Printf("Copying to:   %s\n", dstBucket)

	client := s3.NewFromConfig(cfg)

	paginator := s3.NewListObjectsV2Paginator(client, &s3.ListObjectsV2Input{
		Bucket: &srcBucket,
	})

	var copied int
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return fmt.Errorf("list objects in %q: %w", srcBucket, err)
		}
		for _, obj := range page.Contents {
			src := fmt.Sprintf("%s/%s", srcBucket, *obj.Key)
			_, err := client.CopyObject(ctx, &s3.CopyObjectInput{
				Bucket:     &dstBucket,
				Key:        obj.Key,
				CopySource: aws.String(src),
			})
			if err != nil {
				return fmt.Errorf("copy %q: %w", *obj.Key, err)
			}
			fmt.Printf("- copied: %s\n", *obj.Key)
			copied++
		}
	}

	fmt.Printf("Done! %d object(s) copied.\n", copied)
	return nil
}

func getAccountID(ctx context.Context, cfg aws.Config) (string, error) {
	identity, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return "", fmt.Errorf("get caller identity: %w", err)
	}
	return *identity.Account, nil
}
