import boto3
from botocore.exceptions import NoCredentialsError, PartialCredentialsError

# AWS configuration
KMS_KEY_ID = "arn:aws:kms:region:account-id:key/key-id"

# List of buckets to encrypt
BUCKETS = ["bucket1", "bucket2"]

# Initialize S3 client
s3_client = boto3.client('s3')

def encrypt_bucket_objects(bucket_name):
    try:
        # List objects in the bucket
        objects = s3_client.list_objects_v2(Bucket=bucket_name)

        if 'Contents' in objects:
            for obj in objects['Contents']:
                object_key = obj['Key']

                # Get the current encryption status of the object
                metadata = s3_client.head_object(Bucket=bucket_name, Key=object_key)
                current_encryption = metadata.get('ServerSideEncryption')

                # Check if the current encryption is not KMS
                if current_encryption != 'aws:kms':
                    # Copy the object to the same location with KMS encryption
                    copy_source = {
                        'Bucket': bucket_name,
                        'Key': object_key
                    }
                    s3_client.copy_object(
                        CopySource=copy_source,
                        Bucket=bucket_name,
                        Key=object_key,
                        SSEKMSKeyId=KMS_KEY_ID,
                        ServerSideEncryption='aws:kms'
                    )
                    print(f"Encrypted: s3://{bucket_name}/{object_key}")
                else:
                    print(f"Already encrypted with KMS: s3://{bucket_name}/{object_key}")
        else:
            print(f"No objects found in bucket: {bucket_name}")

    except NoCredentialsError:
        print("Error: AWS credentials not found.")
    except PartialCredentialsError:
        print("Error: Incomplete AWS credentials found.")
    except Exception as e:
        print(f"An error occurred: {e}")


if __name__ == "__main__":
    for bucket in BUCKETS:
        encrypt_bucket_objects(bucket)
    print("Encryption of objects in all specified buckets is complete.")