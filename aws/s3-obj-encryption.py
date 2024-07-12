import boto3
from botocore.exceptions import ClientError
from datetime import datetime
import csv
import json


def create_inventory(bucket_name):
    s3 = boto3.client('s3')
    objects = s3.list_objects_v2(Bucket=bucket_name)
    inventory = []

    for obj in objects.get('Contents', []):
        inventory.append({
            'Bucket': bucket_name,
            'Key': obj['Key'],
            'LastModified': obj['LastModified'],
            'Size': obj['Size']
        })

    return inventory


def save_inventory_to_s3(inventory, target_bucket, original_bucket_name, kms_key_id):
    date_str = datetime.now().strftime("%Y-%m-%d")
    file_name = f"{original_bucket_name}-inventory-{date_str}.csv"
    file_path = f"/tmp/{file_name}"

    with open(file_path, 'w', newline='') as csvfile:
        fieldnames = ['Key', 'LastModified', 'Size']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(inventory)

    s3 = boto3.client('s3')
    try:
        s3.upload_file(file_path, target_bucket, f'inventory/{file_name}',
                       ExtraArgs={'ServerSideEncryption': 'aws:kms', 'SSEKMSKeyId': kms_key_id})
        print(f'Inventory saved to s3://{target_bucket}/inventory/{file_name}')
    except ClientError as e:
        print(e)


def append_to_manifest_file(inventory, manifest_file_path):
    with open(manifest_file_path, 'a', newline='') as csvfile:
        fieldnames = ['Bucket', 'Key']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        for item in inventory:
            writer.writerow({'Bucket': item['Bucket'], 'Key': item['Key']})


def save_manifest_to_s3(manifest_file_path, target_bucket, kms_key_id):
    date_str = datetime.now().strftime("%Y-%m-%d")
    manifest_file_name = f"combined-manifest-{date_str}.csv"

    s3 = boto3.client('s3')
    try:
        s3.upload_file(manifest_file_path, target_bucket, f'manifests/{manifest_file_name}',
                       ExtraArgs={'ServerSideEncryption': 'aws:kms', 'SSEKMSKeyId': kms_key_id})
        print(f'Manifest saved to s3://{target_bucket}/manifests/{manifest_file_name}')
    except ClientError as e:
        print(e)


def encrypt_existing_objects(bucket_name, kms_key_id):
    s3 = boto3.client('s3')
    objects = s3.list_objects_v2(Bucket=bucket_name)

    for obj in objects.get('Contents', []):
        copy_source = {'Bucket': bucket_name, 'Key': obj['Key']}
        try:
            s3.copy_object(
                CopySource=copy_source,
                Bucket=bucket_name,
                Key=obj['Key'],
                ServerSideEncryption='aws:kms',
                SSEKMSKeyId=kms_key_id
            )
            print(f'Encrypted {obj["Key"]}')
        except ClientError as e:
            print(e)


def lambda_handler(event, context):
    bucket_names = event['bucket_names']
    kms_key_id = event['kms_key_id']
    target_bucket = event['target_bucket']

    date_str = datetime.now().strftime("%Y-%m-%d")
    manifest_file_path = f"/tmp/combined-manifest-{date_str}.csv"

    # Create an empty manifest file with headers if it doesn't exist
    with open(manifest_file_path, 'w', newline='') as csvfile:
        fieldnames = ['Bucket', 'Key']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

    for bucket_name in bucket_names:
        # Create inventory
        inventory = create_inventory(bucket_name)

        # Save inventory to S3
        save_inventory_to_s3(inventory, target_bucket, bucket_name, kms_key_id)

        # Append to manifest
        append_to_manifest_file(inventory, manifest_file_path)

        # Encrypt existing objects
        encrypt_existing_objects(bucket_name, kms_key_id)

        # Ensure future objects are encrypted
        s3 = boto3.client('s3')
        bucket_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "EnforceKMSEncryption",
                    "Effect": "Deny",
                    "Principal": "*",
                    "Action": "s3:PutObject",
                    "Resource": f"arn:aws:s3:::{bucket_name}/*",
                    "Condition": {
                        "StringNotEquals": {
                            "s3:x-amz-server-side-encryption": "aws:kms"
                        }
                    }
                }
            ]
        }
        try:
            s3.put_bucket_policy(
                Bucket=bucket_name,
                Policy=json.dumps(bucket_policy)
            )
            print(f'Bucket policy updated for {bucket_name}')
        except ClientError as e:
            print(e)

    # Save the combined manifest to S3
    save_manifest_to_s3(manifest_file_path, target_bucket, kms_key_id)


# Testing Lambda locally
if __name__ == "__main__":
    event = {
        'bucket_names': ['bucket1', 'bucket2'],
        'kms_key_id': 'your-kms-key-id',
        'target_bucket': 'your-target-bucket'
    }
    lambda_handler(event, None)
