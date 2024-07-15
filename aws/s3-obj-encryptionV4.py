import boto3
import csv
from io import StringIO

s3_client = boto3.client('s3')
kms_client = boto3.client('kms')

def lambda_handler(event, context):
    # Replace these with your bucket and manifest file name
    manifest_bucket = 'your-manifest-bucket'
    manifest_key = 'manifest.csv'
    kms_key_id = 'your-kms-key-id'

    # Download the manifest file
    response = s3_client.get_object(Bucket=manifest_bucket, Key=manifest_key)
    manifest_content = response['Body'].read().decode('utf-8')

    # Parse the CSV content
    csv_reader = csv.reader(StringIO(manifest_content))
    for row in csv_reader:
        if len(row) != 2:
            continue

        bucket_name, object_key = row

        # Check if KMS encryption is applied to the object
        try:
            response = s3_client.head_object(Bucket=bucket_name, Key=object_key)
            if 'ServerSideEncryption' not in response or response['ServerSideEncryption'] != 'aws:kms':
                # Apply KMS encryption
                copy_source = {'Bucket': bucket_name, 'Key': object_key}
                s3_client.copy_object(
                    Bucket=bucket_name,
                    Key=object_key,
                    CopySource=copy_source,
                    ServerSideEncryption='aws:kms',
                    SSEKMSKeyId=kms_key_id
                )
                print(f'Applied KMS encryption to {object_key} in {bucket_name}')
        except Exception as e:
            print(f'Error processing {object_key} in {bucket_name}: {e}')

    # Set default encryption for each bucket
    s3_resource = boto3.resource('s3')
    for row in csv_reader:
        if len(row) != 2:
            continue

        bucket_name, _ = row
        bucket = s3_resource.Bucket(bucket_name)
        try:
            bucket.encrypt(
                ServerSideEncryptionConfiguration={
                    'Rules': [
                        {
                            'ApplyServerSideEncryptionByDefault': {
                                'SSEAlgorithm': 'aws:kms',
                                'KMSMasterKeyID': kms_key_id
                            }
                        }
                    ]
                }
            )
            print(f'Set default encryption to KMS for bucket {bucket_name}')
        except Exception as e:
            print(f'Error setting default encryption for {bucket_name}: {e}')

    return {
        'statusCode': 200,
        'body': 'Processing completed successfully.'
    }
