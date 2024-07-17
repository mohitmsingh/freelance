import boto3
import csv
import sys

def generate_manifest_and_kms_files(buckets):
    # Initialize a session using Amazon S3
    session = boto3.Session(profile_name='your_profile_name')
    s3 = session.client('s3')

    # Define the bucket name where the generated files will be uploaded
    destination_bucket = 'your_destination_bucket_name'

    # Create CSV files for manifest and unique KMS keys data
    with open('manifest.csv', mode='w', newline='') as manifest_file, \
            open('unique_kms_keys.csv', mode='w', newline='') as kms_file:
        manifest_writer = csv.writer(manifest_file)
        kms_writer = csv.writer(kms_file)

        manifest_writer.writerow(['bucket_name', 'object_key'])
        kms_writer.writerow(['kms_key_id'])

        unique_kms_keys = set()

        if buckets == ['all']:
            # List all S3 buckets
            all_buckets = s3.list_buckets()
            buckets = [bucket['Name'] for bucket in all_buckets['Buckets']]

        for bucket_name in buckets:
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
                        encryption_info = s3.head_object(Bucket=bucket_name, Key=obj['Key'])
                        if 'ServerSideEncryption' in encryption_info and encryption_info['ServerSideEncryption'] == 'aws:kms':
                            kms_key_id = encryption_info.get('SSEKMSKeyId', '')
                            if kms_key_id:
                                unique_kms_keys.add(kms_key_id)

        # Write unique KMS keys to the CSV file
        for kms_key_id in unique_kms_keys:
            kms_writer.writerow([kms_key_id])

    print("Files generated: manifest.csv and unique_kms_keys.csv")

    # Upload the generated files to the specified S3 bucket
    s3.upload_file('manifest.csv', destination_bucket, 'manifest.csv')
    s3.upload_file('unique_kms_keys.csv', destination_bucket, 'unique_kms_keys.csv')

    print(f"Files uploaded to bucket: {destination_bucket}")


if __name__ == "__main__":
    # Check if the user has provided bucket names as arguments
    if len(sys.argv) < 2:
        print("Usage: python script_name.py <bucket1> <bucket2> ... | all")
        sys.exit(1)

    # Get the list of buckets from the command line arguments
    buckets = sys.argv[1:]

    # Generate manifest and KMS files
    generate_manifest_and_kms_files(buckets)
