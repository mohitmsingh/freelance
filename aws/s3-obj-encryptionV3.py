import boto3
from botocore.exceptions import ClientError
import json

def lambda_handler(event, context):
    s3_client = boto3.client('s3')
    kms_key_id = 'arn:aws:kms:region:account-id:key/key-id'  # Replace with your KMS key ID

    # List of specific buckets to process
    buckets = ['bucket1', 'bucket2']

    for bucket in buckets:
        print(f"Processing bucket: {bucket}")
        continuation_token = None

        while True:
            # List objects in the bucket
            list_objects_params = {
                'Bucket': bucket,
                'ContinuationToken': continuation_token
            } if continuation_token else {
                'Bucket': bucket
            }

            objects_response = s3_client.list_objects_v2(**list_objects_params)

            for obj in objects_response.get('Contents', []):
                key = obj['Key']

                # Get object metadata to check encryption
                try:
                    head_response = s3_client.head_object(Bucket=bucket, Key=key)
                    if head_response.get('ServerSideEncryption') != 'aws:kms':

                        # Copy object to the same location with encryption
                        copy_source = {
                            'Bucket': bucket,
                            'Key': key
                        }
                        s3_client.copy_object(
                            Bucket=bucket,
                            Key=key,
                            CopySource=copy_source,
                            ServerSideEncryption='aws:kms',
                            SSEKMSKeyId=kms_key_id
                        )
                        print(f"Encrypted object: {key} in bucket: {bucket}")
                    else:
                        print(f"Object: {key} in bucket: {bucket} is already encrypted with KMS")
                except ClientError as e:
                    print(f"Error processing object: {key} in bucket: {bucket}. Error: {str(e)}")

            # Check if there are more objects to process
            if objects_response.get('IsTruncated'):
                continuation_token = objects_response.get('NextContinuationToken')
            else:
                break
        # Ensure future objects are encrypted at bucket level
        s3 = boto3.client('s3')
        bucket_policy = {
            "Version": "2012-10-17",
            "Id": "PutObjPolicy",
            "Statement": [
                {
                    "Sid": "DenyUnencryptedObjectUploads",
                    "Effect": "Deny",
                    "Principal": "*",
                    "Action": "s3:PutObject",
                    "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*",
                    "Condition": {
                        "StringNotEquals": {
                            "s3:x-amz-server-side-encryption": "aws:kms"
                        }
                    }
                },
                {
                    "Sid": "RequireSpecificKmsKey",
                    "Effect": "Deny",
                    "Principal": "*",
                    "Action": "s3:PutObject",
                    "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*",
                    "Condition": {
                        "StringNotEquals": {
                            "s3:x-amz-server-side-encryption-aws-kms-key-id": "YOUR_KMS_KEY_ID"
                        }
                    }
                }
            ]
        }
        try:
            s3.put_bucket_policy(
                Bucket=bucket,
                Policy=json.dumps(bucket_policy)
            )
            print(f'Bucket policy updated for {bucket}')
        except ClientError as e: (
                print(e))
    return {
        'statusCode': 200,
        'body': 'Completed encryption update for all objects in specified buckets'
    }
