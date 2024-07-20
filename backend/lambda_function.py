import json

def lambda_handler(event, context):
    products = [
        {
            "id": 1,
            "name": "Product 1",
            "description": "Description for Product 1",
            "image": "images/product1.jpg"
        },
        {
            "id": 2,
            "name": "Product 2",
            "description": "Description for Product 2",
            "image": "images/product2.jpg"
        },
        {
            "id": 3,
            "name": "Product 3",
            "description": "Description for Product 3",
            "image": "images/product3.jpg"
        }
    ]
    
    response = {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        },
        "body": json.dumps(products)
    }
    
    return response
