#!/bin/bash
# Deploy frontend files to S3
aws s3 sync . s3://your-s3-bucket-name --acl public-read
