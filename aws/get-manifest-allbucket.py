import boto3
import csv

# Initialize a session using Amazon S3
session = boto3.Session(profile_name='your_profile_name')
s3 = session.client('s3')

# Define the bucket name where the generated files will be uploaded
destination_bucket = 'your_destination_bucket_name'

# Create CSV files for manifest and encryption data
with open('manifest.csv', mode='w', newline='') as manifest_file, \
        open('encryption_data.csv', mode='w', newline='') as encryption_file:
    manifest_writer = csv.writer(manifest_file)
    encryption_writer = csv.writer(encryption_file)

    manifest_writer.writerow(['bucket_name', 'object_key'])
    encryption_writer.writerow(['bucket_name', 'object_key', 'encryption_type', 'kms_key_id'])

    # List all S3 buckets
    buckets = s3.list_buckets()

    for bucket in buckets['Buckets']:
        bucket_name = bucket['Name']

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
                    if 'ServerSideEncryption' in encryption_info:
                        encryption_type = encryption_info['ServerSideEncryption']
                        kms_key_id = encryption_info.get('SSEKMSKeyId', '')
                    else:
                        encryption_type = 'None'
                        kms_key_id = ''

                    # Write to encryption_data.csv
                    encryption_writer.writerow([bucket_name, object_key, encryption_type, kms_key_id])

print("Files generated: manifest.csv and encryption_data.csv")

# Upload the generated files to the specified S3 bucket
s3.upload_file('manifest.csv', destination_bucket, 'manifest.csv')
s3.upload_file('encryption_data.csv', destination_bucket, 'encryption_data.csv')

print(f"Files uploaded to bucket: {destination_bucket}")
