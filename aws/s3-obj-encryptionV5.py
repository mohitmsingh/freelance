import boto3
import csv
from io import StringIO
import json


def update_bucket_policy(s3_client, bucket_name, kms_key_id):
    try:
        policy = s3_client.get_bucket_policy(Bucket=bucket_name)
        policy_json = json.loads(policy['Policy'])

        # Define the required statement
        kms_statement = {
            "Sid": "AllowKMSAccess",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": f"arn:aws:s3:::{bucket_name}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-server-side-encryption": "aws:kms",
                    "s3:x-amz-server-side-encryption-aws-kms-key-id": kms_key_id
                }
            }
        }

        # Check if the statement already exists
        for statement in policy_json['Statement']:
            if statement == kms_statement:
                print(f'Bucket policy already contains the required KMS key statement for bucket: {bucket_name}')
                return

        # Add the statement to the policy
        policy_json['Statement'].append(kms_statement)

        # Update the bucket policy
        s3_client.put_bucket_policy(
            Bucket=bucket_name,
            Policy=json.dumps(policy_json)
        )
        print(f'Updated bucket policy for {bucket_name}')

    except s3_client.exceptions.NoSuchBucketPolicy:
        # No policy exists, create a new one
        policy_json = {
            "Version": "2012-10-17",
            "Statement": [kms_statement]
        }
        s3_client.put_bucket_policy(
            Bucket=bucket_name,
            Policy=json.dumps(policy_json)
        )
        print(f'Created new bucket policy for {bucket_name}')
    except Exception as e:
        print(f'Error updating bucket policy for {bucket_name}: {e}')


def lambda_handler(event, context):
    kms_key_id = event['kms_key_id']
    manifest_bucket = event['manifest_bucket']
    manifest_key = event['manifest_key']

    # Initialize a session using Amazon S3
    session = boto3.Session(profile_name='dev-cicm')
    # session = boto3.Session()
    s3_client = session.client('s3')

    # Download the manifest file
    response = s3_client.get_object(Bucket=manifest_bucket, Key=manifest_key)
    manifest_content = response['Body'].read().decode('utf-8')

    # Parse the CSV content
    csv_data = StringIO(manifest_content)
    csv_reader = csv.reader(csv_data)
    next(csv_reader)

    for row in csv_reader:
        if len(row) != 2:
            continue
        bucket_name, object_key = row

        # Update the bucket policy
        update_bucket_policy(s3_client, bucket_name, kms_key_id)

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
            elif encryption != 'aws:kms':
                # Apply KMS encryption for the first time
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

    return {
        'statusCode': 200,
        'body': 'Processing completed successfully.'
    }


# Testing Lambda locally
if __name__ == "__main__":
    event = {
        'kms_key_id': 'arn:aws:kms:us-east-1:123456789012:key/5ad0020b-85ab-43bf-9c8e-2e1b39f3d253',
        'manifest_bucket': 'manifest-metadata',
        'manifest_key': 'manifest.csv'
    }
    lambda_handler(event, None)
