import boto3
import csv
from io import StringIO

s3_client = boto3.client('s3')
kms_client = boto3.client('kms')

def lambda_handler(event, context):
    # Replace these with your bucket and manifest file name
    kms_key_id = event['kms_key_id']
    manifest_bucket = event['manifest_bucket']
    manifest_key = event['manifest_key']

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
            encryption = response.get('ServerSideEncryption')
            existing_kms_key_id = response.get('SSEKMSKeyId')

            if encryption == 'aws:kms':
                if existing_kms_key_id == kms_key_id:
                    print(f'{object_key} in {bucket_name} is already encrypted with the correct KMS key')
                else:
                    # Re-encrypt with the new KMS key
                    copy_source = {'Bucket': bucket_name, 'Key': object_key}
                    s3_client.copy_object(
                        Bucket=bucket_name,
                        Key=object_key,
                        CopySource=copy_source,
                        ServerSideEncryption='aws:kms',
                        SSEKMSKeyId=kms_key_id
                    )
                    print(f'Updated KMS key for {object_key} in {bucket_name}')
            elif encryption is None:
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

# Testing Lambda locally
if __name__ == "__main__":
    event = {
        'bucket_names': ['manifest-demo'],
        'kms_key_id': 'your-kms-key-id',
        'manifest_bucket': 'manifest-metadata',
        'manifest_key': 'manifest.csv'
    }
    lambda_handler(event, None)