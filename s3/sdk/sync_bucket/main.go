package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/sts"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s <source-dir> <bucket-name>\n", os.Args[0])
		os.Exit(1)
	}

	if err := run(context.Background(), os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(ctx context.Context, sourceDir, baseName string) error {
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
	fmt.Printf("Syncing %s to bucket: %s\n", sourceDir, bucketName)

	client := s3.NewFromConfig(cfg)

	var uploaded int
	err = filepath.Walk(sourceDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}

		rel, err := filepath.Rel(sourceDir, path)
		if err != nil {
			return err
		}
		key := filepath.ToSlash(rel)

		f, err := os.Open(path)
		if err != nil {
			return fmt.Errorf("open %q: %w", path, err)
		}
		defer f.Close()

		_, err = client.PutObject(ctx, &s3.PutObjectInput{
			Bucket: &bucketName,
			Key:    &key,
			Body:   f,
		})
		if err != nil {
			return fmt.Errorf("upload %q: %w", key, err)
		}

		fmt.Printf("- uploaded: %s\n", key)
		uploaded++
		return nil
	})
	if err != nil {
		return err
	}

	fmt.Printf("Done! %d file(s) uploaded.\n", uploaded)
	return nil
}

func getAccountID(ctx context.Context, cfg aws.Config) (string, error) {
	identity, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return "", fmt.Errorf("get caller identity: %w", err)
	}
	return *identity.Account, nil
}
