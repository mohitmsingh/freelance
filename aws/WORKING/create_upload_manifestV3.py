import boto3
import csv
from botocore.exceptions import ClientError
import argparse

##########################################################################################

# Usage:
# python3 create_upload_manifest.py --account-name $ACCOUNT_NAME --buckets $BUCKETS --manifest-bucket $MANIFEST_BUCKET
# $BUCKETS can be bucket1,bucket2,bucket3 | all

#########################################################################################


def generate_manifest_and_kms_files(account_name, buckets, manifest_bucket):

    # Initialize a session using Amazon S3
    session = boto3.Session(profile_name=f'{account_name}')  # Modify or remove profile_name as needed
    s3 = session.client('s3')

    # Create CSV files for manifest and unique KMS keys data
    try:
        with open('manifest.csv', mode='w', newline='') as manifest_file, \
                open('unique_kms_keys.csv', mode='w', newline='') as kms_file:
            manifest_writer = csv.writer(manifest_file)
            kms_writer = csv.writer(kms_file)

            manifest_writer.writerow(['Bucket', 'Key'])
            kms_writer.writerow(['unique_kms', 'buckets'])

            kms_key_buckets = {}

            if buckets == ['all']:
                # List all S3 buckets
                try:
                    all_buckets = s3.list_buckets()
                    buckets = [bucket['Name'] for bucket in all_buckets['Buckets']]
                except ClientError as e:
                    print(f"Error listing buckets: {e}")
                    return

            for bucket_name in buckets:
                print(f"Processing bucket: {bucket_name}")

                # Paginate through objects in the bucket
                paginator = s3.get_paginator('list_objects_v2')
                page_iterator = paginator.paginate(Bucket=bucket_name)

                for page in page_iterator:
                    if 'Contents' in page:
                        for obj in page['Contents']:
                            object_key = obj['Key']

                            # Write to manifest.csv
                            manifest_writer.writerow([bucket_name, object_key])

                            # Get object encryption data
                            try:
                                encryption_info = s3.head_object(Bucket=bucket_name, Key=obj['Key'])
                                if 'ServerSideEncryption' in encryption_info and encryption_info['ServerSideEncryption'] == 'aws:kms':
                                    kms_key_id = encryption_info.get('SSEKMSKeyId', '')
                                    if kms_key_id:
                                        if kms_key_id not in kms_key_buckets:
                                            kms_key_buckets[kms_key_id] = set()
                                        kms_key_buckets[kms_key_id].add(bucket_name)
                            except ClientError as e:
                                print(f"Error getting encryption info for {bucket_name}/{object_key}: {e}")

            # Write unique KMS keys and their associated buckets to the CSV file
            for kms_key_id, bucket_names in kms_key_buckets.items():
                kms_writer.writerow([kms_key_id, ','.join(bucket_names)])

        print("Files generated: manifest.csv and unique_kms_keys.csv")

        # Upload the generated files to the specified S3 bucket
        try:
            s3.upload_file('manifest.csv', manifest_bucket, 'manifest.csv')
            s3.upload_file('unique_kms_keys.csv', manifest_bucket, 'unique_kms_keys.csv')
            print(f"Files uploaded to bucket: {manifest_bucket}")
        except ClientError as e:
            print(f"Error uploading files to bucket {manifest_bucket}: {e}")

    except Exception as e:
        print(f"An error occurred: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create manifest and unique KMS key files")
    parser.add_argument("--account-name", required=True, help="AWS Account Name or Profile")
    parser.add_argument("--buckets", required=True, help="Bucket Names (comma-separated)/all")
    parser.add_argument("--manifest-bucket", required=True, help="Destination for Manifest")
    args = parser.parse_args()

    # Split the buckets string into a list
    buckets_list = args.buckets.split(',')

    generate_manifest_and_kms_files(args.account_name, buckets_list, args.manifest_bucket)

