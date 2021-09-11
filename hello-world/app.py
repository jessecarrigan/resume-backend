import json
import boto3

# import requests


def get_views(event, context):
    """Sample pure Lambda function

    Parameters
    ----------
    event: dict, required
        API Gateway Lambda Proxy Input Format

        Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

    context: object, required
        Lambda Context runtime methods and attributes

        Context doc: https://docs.aws.amazon.com/lambda/latest/dg/python-context-object.html

    Returns
    ------
    API Gateway Lambda Proxy Output Format: dict

        Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html
    """

    # try:
    #     ip = requests.get("http://checkip.amazonaws.com/")
    # except requests.RequestException as e:
    #     # Send some context about this error to Lambda Logs
    #     print(e)

    #     raise e

    client = boto3.client('dynamodb')
    data = client.get_item(
        TableName='views',
        Key={
            'id': {
                'S': 'views'
            }
        }
    )

    response = {
        'statusCode': 200,
        'body': json.dumps(data),
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
    }
    
    return response


def update_views(event, context):
    client = boto3.client('dynamodb')
    count = client.get_item(
        TableName='views',
        Key={
            'id': {
                'S': 'views'
            }
        }
    )

    new_count = int(count['Item']['count']['N']) + 1

    update_count = client.put_item(
        TableName='views',
        Item={
            'id': {
                'S': 'views'
            },
            'count': {
                'N': str(new_count)
            }
        }
    )

    response = {
        'statusCode': 200,
        'body': json.dumps(update_count),
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
    }
    
    return response