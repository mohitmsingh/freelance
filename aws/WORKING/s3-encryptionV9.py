import boto3
import csv
from io import StringIO
from botocore.exceptions import ClientError


def lambda_handler(event, context):
    kms_key_id = event['kms_key_id']
    manifest_bucket = event['manifest_bucket']
    manifest_key = event['manifest_key']
    account_name = event['account_name']

    # Initialize a session using Amazon S3
    session = boto3.Session(profile_name=f'{account_name}')
    # session = boto3.Session()
    s3_client = session.client('s3')

    # Download the manifest file
    try:
        response = s3_client.get_object(Bucket=manifest_bucket, Key=manifest_key)
        manifest_content = response['Body'].read().decode('utf-8')
    except ClientError as e:
        print(f'Error downloading manifest file: {e}')
        return {
            'statusCode': 500,
            'body': 'Error downloading manifest file.'
        }

    # Parse the CSV content
    csv_data = StringIO(manifest_content)
    csv_reader = csv.reader(csv_data)
    next(csv_reader)  # Skip header row

    processed_buckets = set()

    for row in csv_reader:
        if len(row) != 2:
            continue
        bucket_name, object_key = row

        # Check if KMS encryption is applied to the object
        try:
            response = s3_client.head_object(Bucket=bucket_name, Key=object_key)
            encryption = response.get('ServerSideEncryption')
            existing_kms_key_id = response.get('SSEKMSKeyId')

            # Encryption with KMS already
            if encryption == 'aws:kms':
                # Do not encrypt if already KMS Key matches with existing one
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

            # Apply KMS encryption
            elif encryption != 'aws:kms':
                copy_source = {'Bucket': bucket_name, 'Key': object_key}
                s3_client.copy_object(
                    Bucket=bucket_name,
                    Key=object_key,
                    CopySource=copy_source,
                    ServerSideEncryption='aws:kms',
                    SSEKMSKeyId=kms_key_id
                )
                print(f'Applied KMS encryption to {object_key} in {bucket_name}')
        except ClientError as e:
            print(f'Error processing {object_key} in {bucket_name}: {e}')

        # Set default encryption for each bucket (only once per bucket)
        if bucket_name not in processed_buckets:
            processed_buckets.add(bucket_name)
            try:
                response = s3_client.get_bucket_encryption(Bucket=bucket_name)
                rules = response['ServerSideEncryptionConfiguration']['Rules']
                current_sse_algorithm = rules[0]['ApplyServerSideEncryptionByDefault']['SSEAlgorithm']
                current_kms_key_id = rules[0]['ApplyServerSideEncryptionByDefault'].get('KMSMasterKeyID')

                if current_sse_algorithm == 'aws:kms' and current_kms_key_id == kms_key_id:
                    print(f"Bucket {bucket_name} already uses the specified KMS key for encryption. No changes required.")
                else:
                    raise KeyError

            except (ClientError, KeyError):
                encryption_configuration = {
                    "Rules": [
                        {
                            "ApplyServerSideEncryptionByDefault": {
                                "SSEAlgorithm": "aws:kms",
                                "KMSMasterKeyID": kms_key_id
                            }
                        }
                    ]
                }

                try:
                    s3_client.put_bucket_encryption(
                        Bucket=bucket_name,
                        ServerSideEncryptionConfiguration=encryption_configuration
                    )
                    print(f"Encryption configuration updated successfully for {bucket_name} to use the specified KMS key.")
                except ClientError as e:
                    print(f'Error updating bucket encryption for {bucket_name}: {e}')
                    return {
                        'statusCode': 500,
                        'body': f'Error updating bucket encryption for {bucket_name}.'
                    }

    return {
        'statusCode': 200,
        'body': 'Processing completed successfully.'
    }


# Testing Lambda locally
if __name__ == "__main__":
    event = {
        'kms_key_id': 'arn:aws:kms:us-east-1:077911745872:key/5ad0020b-85ab-43bf-9c8e-2e1b39f3d253',
        'manifest_bucket': 'manifest-metadata',
        'manifest_key': 'manifest.csv',
        'account_name': 'dev-cicm'
    }
    lambda_handler(event, None)