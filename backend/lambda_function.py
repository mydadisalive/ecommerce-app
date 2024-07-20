import json

def lambda_handler(event, context):
    # Get the path from the requestContext object
    path = event.get('requestContext', {}).get('path', '')

    if path == "/prod":
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({
                "name": "E-commerce API",
                "version": "1.0.0",
                "description": "Welcome to the E-commerce API. Use this API to manage products, orders, and customers.",
                "endpoints": {
                    "products": "/prod/products"
                },
                "documentation": "https://api.example.com/docs"
            })
        }
    elif path == "/prod/products":
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

        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps(products)
        }
    else:
        return {
            "statusCode": 404,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({"message": "Not Found"})
        }
