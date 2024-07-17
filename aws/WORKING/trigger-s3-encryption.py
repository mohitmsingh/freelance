import boto3
import sys
import os

# Get command line arguments
account_name = sys.argv[1]
manifest_bucket = sys.argv[2]
kms_key_id = sys.argv[3]
lambda_function_arn = sys.argv[4]

account_id = os.environ.get('ACCOUNT_ID')
# your-iam-role-arn
iam_role_arn = os.environ.get('IAM_ROLE_ARN')

# AWS Configuration
# aws_region = os.environ.get('AWS_REGION')
# aws_access_key_id = os.environ.get('AWS_ACCESS_KEY_ID')
# aws_secret_access_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
#
# s3 = boto3.client('s3', region_name=aws_region,
#                   aws_access_key_id=aws_access_key_id,
#                   aws_secret_access_key=aws_secret_access_key)

# AWS

# Initialize a session using Amazon S3
session = boto3.Session(profile_name=f'{account_name}')
# session = boto3.Session()
s3_client = session.client('s3')


def submit_s3_batch_job(bucket_name, manifest_key, kms_key_id, lambda_function_arn):
    response = s3_client.submit_job(
        AccountId=f'{account_id}',
        Operation={
            'LambdaInvoke': {
                'FunctionArn': lambda_function_arn
            }
        },
        Manifest={
            'Spec': {
                'Format': 'S3BatchOperations_CSV_20180820',
                'Fields': ['Bucket', 'Key']
            },
            'Location': {
                'Bucket': manifest_bucket,
                'Key': manifest_key
            }
        },
        Report={
            'Bucket': manifest_bucket,
            'Format': 'Report_CSV_20180820',
            'Enabled': True
        },
        RoleArn='your-iam-role-arn',
        Parameters={
            'kms_key_id': kms_key_id,
            'manifest_bucket': bucket_name,
            'manifest_key': manifest_key,
            'account_name': 'default'  # Replace with your account profile name if needed
        }
    )
    print("Job submitted:", response)

def main():
    manifest_key = 'manifest.csv'
    submit_s3_batch_job(manifest_bucket, manifest_key, kms_key_id, lambda_function_arn)


if __name__ == "__main__":
    main()
