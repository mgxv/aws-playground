#!/usr/bin/env bash

SORT="${1:-datetime-desc}"

export AWS_CLI_AUTO_PROMPT=off

echo "Listing buckets (sorted by: $SORT)..."

case "$SORT" in
  datetime-desc)
    BUCKETS=$(aws s3api list-buckets --query "sort_by(Buckets, &CreationDate)[::-1][].Name" --output text)
    ;;
  datetime-asc)
    BUCKETS=$(aws s3api list-buckets --query "sort_by(Buckets, &CreationDate)[].Name" --output text)
    ;;
  name-asc)
    BUCKETS=$(aws s3api list-buckets --query "sort_by(Buckets, &Name)[].Name" --output text)
    ;;
  name-desc)
    BUCKETS=$(aws s3api list-buckets --query "sort_by(Buckets, &Name)[::-1][].Name" --output text)
    ;;
  *)
    echo "Invalid sort option. Use: datetime-desc, datetime-asc, name-asc, name-desc"
    exit 1
    ;;
esac

for BUCKET in $BUCKETS; do
  COUNT=$(aws s3api list-objects-v2 --bucket "$BUCKET" --query "length(Contents)" --output text 2>/dev/null)
  SIZE=$(aws s3api list-objects-v2 --bucket "$BUCKET" --query "sum(Contents[].Size)" --output text 2>/dev/null)

  [ "$COUNT" == "None" ] && COUNT=0
  [ "$SIZE" == "None" ] && SIZE=0

  echo "- $BUCKET (objects: $COUNT, size: $SIZE bytes)"
done

export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
