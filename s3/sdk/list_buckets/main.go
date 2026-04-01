package main

import (
	"context"
	"fmt"
	"os"
	"sort"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type bucketInfo struct {
	Name         string
	CreationDate int64
	CreatedAt    string
}

type bucketStats struct {
	Count int64
	Size  int64
}

func main() {
	sortMode := "datetime-desc"
	if len(os.Args) > 1 {
		sortMode = os.Args[1]
	}

	if err := run(context.Background(), sortMode); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(ctx context.Context, sortMode string) error {
	if err := validateSortMode(sortMode); err != nil {
		return err
	}

	fmt.Printf("Listing buckets (sorted by: %s)...\n", sortMode)

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}

	client := s3.NewFromConfig(cfg)

	buckets, err := listBuckets(ctx, client)
	if err != nil {
		return err
	}

	sortBuckets(buckets, sortMode)

	for _, b := range buckets {
		stats := getBucketStats(ctx, client, b.Name)
		fmt.Printf("- %s (objects: %d, size: %d bytes) %s\n", b.Name, stats.Count, stats.Size, b.CreatedAt)
	}

	fmt.Println("Done!")
	return nil
}

func validateSortMode(mode string) error {
	switch mode {
	case "datetime-desc", "datetime-asc", "name-asc", "name-desc":
		return nil
	default:
		return fmt.Errorf("invalid sort option %q — use: datetime-desc, datetime-asc, name-asc, name-desc", mode)
	}
}

func formatInLocation(t *time.Time, zone string) string {
	if t == nil {
		return "unknown"
	}
	loc, err := time.LoadLocation(zone)
	if err != nil {
		loc = time.UTC
	}
	return t.In(loc).Format("2006-01-02 15:04:05 MST")
}

func listBuckets(ctx context.Context, client *s3.Client) ([]bucketInfo, error) {
	out, err := client.ListBuckets(ctx, &s3.ListBucketsInput{})
	if err != nil {
		return nil, fmt.Errorf("list buckets: %w", err)
	}

	buckets := make([]bucketInfo, 0, len(out.Buckets))
	for _, b := range out.Buckets {
		var ts int64
		if b.CreationDate != nil {
			ts = b.CreationDate.Unix()
		}
		buckets = append(buckets, bucketInfo{
			Name:         *b.Name,
			CreationDate: ts,
			CreatedAt:    formatInLocation(b.CreationDate, "America/Denver"),
		})
	}
	return buckets, nil
}

func sortBuckets(buckets []bucketInfo, mode string) {
	less := map[string]func(i, j int) bool{
		"datetime-desc": func(i, j int) bool { return buckets[i].CreationDate > buckets[j].CreationDate },
		"datetime-asc":  func(i, j int) bool { return buckets[i].CreationDate < buckets[j].CreationDate },
		"name-asc":      func(i, j int) bool { return buckets[i].Name < buckets[j].Name },
		"name-desc":     func(i, j int) bool { return buckets[i].Name > buckets[j].Name },
	}
	sort.Slice(buckets, less[mode])
}

func getBucketStats(ctx context.Context, client *s3.Client, bucket string) bucketStats {
	var stats bucketStats
	paginator := s3.NewListObjectsV2Paginator(client, &s3.ListObjectsV2Input{Bucket: &bucket})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			break
		}
		stats.Count += int64(len(page.Contents))
		for _, obj := range page.Contents {
			if obj.Size != nil {
				stats.Size += *obj.Size
			}
		}
	}
	return stats
}
